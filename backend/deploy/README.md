# Backend job deployment (Phase 1: `compute_risk` only)

Closes the gap found in the production investigation: `compute_risk` writes
correct risk data when run, but nothing in production ever ran it — there was
no Cloud Scheduler trigger. This directory provisions **exactly one** job,
per ADR-002 (Cloud Scheduler → Cloud Run), and nothing else yet.

**Out of scope for Phase 1 (deliberately):** `dispatch_alerts`, `weekly_report`,
Cloud Monitoring alert policies, CI/CD auto-deploy. Those are later phases —
see the deployment-architecture discussion in this project's chat history.
Nothing in `app/jobs/*.py`, `compose.yaml`, or the `Dockerfile` is modified by
this phase; these scripts only add infrastructure config that targets the
existing, unchanged `python -m app.jobs.compute_risk` entrypoint.

## Files

| File | Purpose |
|---|---|
| `config.env.example` | Copy to `config.env` (git-ignored) and adjust; no secrets in it |
| `provision_compute_risk.sh` | Idempotent `gcloud` script: Artifact Registry, image build (Cloud Build — no local Docker needed), service accounts, Cloud Run Job, Cloud Scheduler trigger |
| `verify_compute_risk.sh` | Triggers one real execution now and checks it succeeded, instead of waiting until next Monday |
| `read_heartbeat.py` | Ops helper to read `jobHeartbeats/compute_risk` (service-only collection, not readable from the console UI without the Admin SDK) |

## Prerequisites

- `gcloud` CLI installed and authenticated (`gcloud auth login`), with
  `gcloud config set project foreseeme-83587` — **not available in this dev
  sandbox** (confirmed absent during this session); run these from a machine
  or CI runner that has it, or install it locally first.
- Billing enabled on the project (APIs are enabled by the script, but billing
  must already be active).
- No service-account JSON is created or downloaded anywhere in this flow —
  the Cloud Run Job authenticates as its attached service account via
  Application Default Credentials, which `init_firestore_repository()` in
  `app/jobs/compute_risk.py` already supports with **zero code change**. This
  keeps `GOLDEN_RULES.md` §7 intact (no secrets in source; nothing new to
  `.gitignore`).

## Run it

```bash
cd backend
cp deploy/config.env.example deploy/config.env   # adjust only if needed
source deploy/config.env
./deploy/provision_compute_risk.sh
./deploy/verify_compute_risk.sh
```

## What gets created

- Artifact Registry Docker repo `backend` in `us-central1`.
- Service account `risk-jobs-sa` — granted **only** `roles/datastore.user` in
  this phase (Firestore read/write for `riskEstimates` + `jobHeartbeats`).
  It does **not** get `roles/firebasemessaging.admin` yet — that's added in
  Phase 2 when `dispatch_alerts` is provisioned, kept out now on purpose
  (least-privilege, scoped to what's actually deployed).
- Service account `scheduler-invoker-sa` — granted `roles/run.invoker` on
  the `compute-risk-job` resource only (not project-wide), so it can trigger
  that one execution and nothing else.
- Cloud Run Job `compute-risk-job` — same image as the existing `Dockerfile`,
  command overridden to `python -m app.jobs.compute_risk` (the same override
  `compose.yaml`'s `compute-risk-job` service already uses locally).
- Cloud Scheduler job `compute-risk-weekly` — Monday 00:00 UTC, calls the
  Cloud Run Admin API (`.../jobs/compute-risk-job:run`) via OAuth as
  `scheduler-invoker-sa`.

## Local verification performed before writing these scripts

Before touching any cloud config, the job's actual execution path was run
locally: Firestore emulator (`firebase emulators:start --only firestore`) +
`python -m app.jobs.compute_risk` under Python 3.12 (matching the
Dockerfile's `python:3.12-slim`), exercising the real network path
(`OpenMeteoWeeklyBaseProvider` hitting the live Open-Meteo API — not a fake),
the real promoted model artifact, and a real Firestore write + heartbeat.
See the session's verification output for the result. This is the same
module invocation Cloud Run will run in production — the container build
step itself (`gcloud builds submit`) additionally isn't a local-Docker
concern, since Cloud Build builds server-side.

## Rollback

```bash
gcloud scheduler jobs delete compute-risk-weekly --location=us-central1
gcloud run jobs delete compute-risk-job --region=us-central1
# Service accounts and the Artifact Registry repo are left in place —
# harmless if idle, and Phase 2 reuses risk-jobs-sa.
```
