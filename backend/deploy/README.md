# Backend job deployment (Phase 2: `compute_risk` + `dispatch_alerts`)

Closes the gap found in the production investigation: both jobs write
correct data when run, but nothing in production ever ran either — there
was no Cloud Scheduler trigger for either. This directory provisions
**two** jobs, per ADR-002 (Cloud Scheduler → Cloud Run). `weekly_report` is
still **not** provisioned — that's a later phase, and its cadence is
unchanged (weekly).

Nothing in `app/jobs/*.py`, `compose.yaml`, or the `Dockerfile` is modified
by this phase; these scripts only add infrastructure config targeting the
existing, unchanged `python -m app.jobs.<name>` entrypoints. No Pub/Sub,
Eventarc, Cloud Tasks, Cloud Workflows, or Firebase Scheduled Functions were
introduced — the architecture stays exactly "independent Cloud Scheduler →
Cloud Run Job" per job, as decided.

## Phase 2 architectural decision: `compute_risk` is now daily, not weekly

The model is already trained; a scheduled run only performs **inference**
over fresh weather/AQI data, which is cheap. Users should never see a
week-old "Updated 7 days ago" card. **No code change was needed**:
`app/jobs/compute_risk.py`'s `document_id()` already names each scheduled
document by the run's actual calendar date (`{city}_{YYYY-MM-DD}` from
`generated_at.strftime('%Y-%m-%d')`), not by ISO week — only `backfill()`
(a separate, manual, unscheduled operator path) uses the ISO-week Monday.
Invoking the existing `run()` path daily therefore already produces one
fresh `riskEstimates` doc per city per day, with no change to the model,
the feature pipeline, or the Firestore write path. This is purely a
`config.env` schedule-string change (`"0 0 * * *"` instead of a weekly cron).

`dispatch_alerts` moves to daily too (10 minutes after `compute_risk`), so
it evaluates each day's fresh estimate instead of stale week-old data — this
also means its existing 24h throttle window is now actually exercised as
designed (previously, with a weekly cadence, the 24h throttle was
structurally unreachable). `weekly_report` is intentionally left alone.

## Files

| File | Purpose |
|---|---|
| `config.env.example` | Copy to `config.env` (git-ignored) and adjust; no secrets in it. Shared vars + a `COMPUTE_RISK_*` block + a `DISPATCH_ALERTS_*` block |
| `common.sh` | Shared, idempotent `gcloud` helpers (Phase 2: factored out of Phase 1's single script once a second job needed the same steps) — sourced by both `provision_*.sh` scripts, not run directly |
| `provision_compute_risk.sh` | Provisions `compute-risk-job` + `compute-risk-daily` scheduler |
| `verify_compute_risk.sh` | Triggers one real execution now and checks it succeeded |
| `provision_dispatch_alerts.sh` | Provisions `dispatch-alerts-job` + `dispatch-alerts-daily` scheduler; additionally grants the shared job SA `roles/firebasemessaging.admin` |
| `verify_dispatch_alerts.sh` | Triggers two consecutive executions (proves idempotency), pulls logs + heartbeat |
| `read_heartbeat.py` | Ops helper: read `jobHeartbeats/{job}` (service-only, not console-visible) |
| `read_dispatch_audit.py` | Ops helper: read recent `alertDispatchLog` entries, or a user's `userAlerts/{uid}/items` (Notification Center contents) |

## Prerequisites

- `gcloud` CLI installed and authenticated (`gcloud auth login`), with
  `gcloud config set project foreseeme-83587` — **not available in this dev
  sandbox** (confirmed absent); run these from a machine or CI runner that
  has it.
- Billing enabled on the project (APIs are enabled by the scripts, but
  billing itself must already be active).
- No service-account JSON anywhere in this flow — each Cloud Run Job
  authenticates as its attached service account via Application Default
  Credentials, which `init_firestore_repository()` / `init_firestore()`
  already support with **zero code change**. Keeps `GOLDEN_RULES.md` §7
  intact.

## Run it

```bash
cd backend
cp deploy/config.env.example deploy/config.env   # adjust only if needed
source deploy/config.env

./deploy/provision_compute_risk.sh
./deploy/verify_compute_risk.sh

./deploy/provision_dispatch_alerts.sh
./deploy/verify_dispatch_alerts.sh
```

## What gets created (Phase 2 additions on top of Phase 1)

- Cloud Run Job `dispatch-alerts-job` — same shared image, command
  overridden to `python -m app.jobs.dispatch_alerts`.
- Cloud Scheduler job `dispatch-alerts-daily` — 00:10 UTC daily (10 minutes
  after `compute-risk-daily`'s 00:00 UTC), OAuth as `scheduler-invoker-sa`.
- `risk-jobs-sa` (the same shared SA from Phase 1) additionally granted
  `roles/firebasemessaging.admin` — layered on now because this is the job
  that actually needs it (least-privilege, phase-scoped: Phase 1's
  `compute_risk` still only needed `roles/datastore.user`).
- `compute-risk-weekly` is renamed to `compute-risk-daily` with a daily
  schedule (Phase 1 never actually provisioned real cloud resources in this
  sandbox — `gcloud` wasn't available to run it — so this is a rename in
  the scripts, not a live migration of an existing Cloud Scheduler job).

**Ordering is soft, by design, not by a hard dependency:** if `compute_risk`
runs late or fails on a given day, `dispatch_alerts` simply re-reads
yesterday's still-valid "latest two" estimates, finds no transition, and
grades the run `ok` (zero sends is not a failure — see
`classify_run()`/`docs/observability.md`). No Pub/Sub or event chaining was
introduced to make this "hard," per the architecture constraint — the
failure mode of a schedule race is benign, not corrupting, and the
idempotency key (`{uid}__{riskEstimateId}__{category}`) prevents any
double-send regardless of timing.

## Verification performed this session

**compute_risk (Phase 1, unchanged):** real Firestore emulator + real
Open-Meteo network calls + real model, run under Python 3.12. All 5 cities
written, heartbeat `ok`. See prior session output.

**dispatch_alerts (Phase 2, new):**
- *Business logic* (targeting, 24h throttle, idempotency, audit logging,
  inbox write, token pruning): already covered by 9 existing unit tests in
  `backend/tests/test_dispatch_alerts.py` against fakes — re-run this
  session, still green (see verification log).
- *Firestore integration* (the parts unit tests use fakes for and therefore
  cannot prove): `FirestoreRiskHistoryProvider`, `FirestoreUserDirectory`,
  `FirestoreDispatchRepository` were exercised for real against the local
  emulator this session — seeded a risk transition + a matching test user,
  ran the real `dispatch_alerts.run()` orchestration (only the FCM `send()`
  seam was stubbed — see below), and confirmed a real `alertDispatchLog`
  write, a real `userAlerts/{uid}/items` write, and idempotency on a second
  run. Details and output in this session's transcript / the Phase 2
  deliverables summary.

**Not verified — external dependency, not a code or deployment gap:**
genuine FCM push delivery to a physical/emulated device, and the Flutter
Notification Center reflecting it live. Real FCM send requires a real,
signed production service-account credential (this sandbox has none —
confirmed the same way Phase 1 confirmed `gcloud` was absent) *and* a real
device/emulator running the signed-in Flutter app to capture a genuine
`fcmToken`. Both are unavailable in this environment. The `--message_id`
returned by a real send, and the on-device notification banner + in-app
Notification Center refresh, need to be confirmed once against a real
device as part of this project's still-open "device e2e" item (tracked
since Sprint 3's close-out).

## Rollback

```bash
gcloud scheduler jobs delete compute-risk-daily --location=us-central1
gcloud run jobs delete compute-risk-job --region=us-central1
gcloud scheduler jobs delete dispatch-alerts-daily --location=us-central1
gcloud run jobs delete dispatch-alerts-job --region=us-central1
# Service accounts and the Artifact Registry repo are left in place —
# harmless if idle, and a future weekly_report phase reuses risk-jobs-sa.
# To also remove the FCM permission dispatch_alerts added:
gcloud projects remove-iam-policy-binding foreseeme-83587 \
  --member="serviceAccount:risk-jobs-sa@foreseeme-83587.iam.gserviceaccount.com" \
  --role="roles/firebasemessaging.admin"
```
