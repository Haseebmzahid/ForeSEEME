# ForeSeeMe card-ready deployment preparation

**NOT CARD-READY** — inspected 2026-10-12 (America/Los_Angeles). All commands in the release sections below are future operator commands, not actions performed during preparation. Project: foreseeme-83587; region: us-central1.

The supported scheduler-free release command is now `python -B deploy/compute_risk_control.py one-time` from backend, or `bash deploy/provision_compute_risk.sh --one-time`. Follow the one-time section of backend/deploy/README.md: its preflight retains every non-scheduler prerequisite. The earlier cloud snapshot below is historical, not a new cloud check. Scheduler-specific API/account/IAM and schedule-enablement instructions apply only to separately authorized recurring deployment. Never follow one-time with the verify wrapper, which executes again.

## Confirmed facts and blockers

| Check | Read-only result |
|---|---|
| Branch | main; existing modified/untracked files retained |
| Active CLI project / identity | foreseeme-83587; an active authenticated account exists |
| Project | ACTIVE; number 298087029692 |
| Billing | billingEnabled=false |
| Required enabled APIs | firestore, cloudresourcemanager, serviceusage, logging |
| Required missing APIs | run.googleapis.com, cloudscheduler.googleapis.com, artifactregistry.googleapis.com, iam.googleapis.com, cloudbilling.googleapis.com |
| FCM | Already enabled, but unnecessary for compute-risk evaluation |
| Cloud Run / Scheduler visibility | SERVICE_DISABLED; job/schedule existence unknown, even when failed output contains [] |
| Registry repositories / image list | SERVICE_DISABLED; repository/image/digest existence unknown |
| Service accounts | Successful list returned only the enabled Firebase Admin SDK account; neither intended deployment account appears |
| Project IAM | Readable; lacks intended jobs-SA datastore.user, scheduler-SA run.invoker and service-298087029692@gcp-sa-cloudscheduler.iam.gserviceaccount.com cloudscheduler.serviceAgent bindings |
| Job-level invoker IAM | Unreadable while Run API is disabled; not proof of absence |
| Docker | CLI 29.1.3 installed; one docker version check found desktop-linux daemon pipe unavailable |

The initial sandbox prevented gcloud credential-database access. The same read-only commands were repeated with approved local SDK access and produced the results above. No enablement prompts were accepted. Project/IAM list visibility does not prove effective deployment, actAs, image-pull or ADC permissions.

Local config was parsed as assignments without sourcing/executing it or printing any values. It is ignored by Git. Both controller REQUIRED lists were compared. Compute lacks FIRESTORE_AUTH_MODE, VERIFY_TIMEOUT_SECONDS, VERIFY_MAX_AGE_SECONDS, VERIFY_MIN_WRITTEN, RISK_DATA_DELAY_DAYS, RISK_WEATHER_MAX_TRAILING_GAP_DAYS, RISK_AQI_MAX_TRAILING_GAP_DAYS. Dispatch lacks the first three shared settings. IMAGE is a mutable tag and fails the controllers' project/region/digest format requirement. Local PROJECT_ID and REGION match the target; no conflicting optional Firebase/Google project values or emulator/credential-file overrides were found. Flutter Firebase platform configuration also points at foreseeme-83587.

Both local service-account references have valid identities in the target project. Local compute cadence matches the daily example and uses UTC. The original 31 modified/untracked files were hashed before preparation edits and matched afterward; the ignored config was never edited. main remains active, the index has no staged changes, and git diff --check passed (only existing LF/CRLF conversion notices). Only the three new preparation files were added; no dependencies, existing source files or controllers were changed. No cloud mutations, controller runs, builds, image pushes, staging, commits or pushes occurred.

Exact image requirement: obtain a reviewed, existing Linux-compatible backend image in this project's regional Artifact Registry, with an actual 64-lowercase-hex sha256 digest and evidence it contains this runtime/model/cache implementation. Verify it with authenticated registry reads after API access is available. An immutable reference alone does not prove the contents match current modified code. If no suitable image exists, a separately authorized build/push/release is required. No digest is invented and no latest tag is substituted. Docker daemon unavailability blocks a local image inspection/build, but not authenticated registry metadata reads.

## Runtime and context review

The Dockerfile expects backend as build context. It uses python:3.12-slim (a mutable base tag), installs the existing pinned requirements, copies app, ml/pipelines, ml/config and ml/artifacts, and defaults to the HTTP uvicorn service. Compute must override this with `python -m app.jobs.compute_risk`; no backfill argument. PYTHONUNBUFFERED=1, PYTHONDONTWRITEBYTECODE=1 and FORESEEME_ML_DATA_DIR=/home/appuser/ml-cache are image settings. PORT=8000 is irrelevant to the job.

The added backend/.dockerignore permits only runtime Python, YAML config, requirements and promoted model_*.joblib artifacts. It excludes local config, .env files, secure/, credentials JSON, deploy scripts, raw data, tests and caches from a future context transfer. Git ignores alone were insufficient; selective COPY avoided baking top-level secrets into layers but did not exclude them from context upload. No image was built. A future release must review any additional runtime files before changing this allowlist; use the backend context, not the repository root.

The local promoted artifact model_1.0.0.joblib exists (5,472,641 bytes); highest semantic-version promoted artifact is selected. candidate_model.joblib is not selected and is excluded from the future context. Code/model presence is confirmed locally; container dependency compatibility and model loading remain unproven. Config YAML and feature/acquisition Python are included. The non-root UID 1000 appuser owns /home/appuser/ml-cache; acquisition derives raw/manifest.json under the overridden cache and writes there atomically. Source code/config/model paths can stay read-only. Cloud Run cache is ephemeral, so each execution may reacquire the 12-week input window. Writable permissions are established by Dockerfile intent, not a tested existing image.

Unsafe or unsuitable evaluation defaults: daily compute plus daily dispatch in the example; provision automatically enables scheduling after backend assertions; VERIFY_MIN_WRITTEN=1 accepts degraded partial results; 512Mi/600s are unmeasured; Docker base is mutable for future builds. Missing attached-auth config must be explicit before deployment. Dispatch offset is not a hard dependency and is unnecessary here. Keep dispatch disabled; do not reuse its controller to evaluate the card.

## Actual freshness and smallest practical schedule

Normal compute sets generatedAt to the UTC run start/generation time, serializes an ISO-8601 UTC string, and upserts `{city}_{YYYY-MM-DD}` with merge=True. Same-day executions overwrite that city's daily document. Historical backfill uses week-start timestamps and is not part of initial deployment. Weather and AQI use a 12-week window ending UTC today minus five days; each required variable must meet the zero trailing-gap gate before inference. A fresh generatedAt is therefore generation freshness, not a claim that observations include today. Invalid/unavailable inputs can skip cities and leave their older documents visible.

Flutter queries riskEstimates by city, orders generatedAt descending and takes one document. The model normalizes timestamps to UTC. RiskCard and HomeRiskField show an age label and the shared notice only when age is **greater than nine days**; exactly nine days remains fresh. There is no 24-hour expiry. The age label switches to days at 24 hours, which is formatting only. Repository get() may return cached data offline; FutureProvider is not a Firestore live stream. Labels are computed on widget rebuild, not by a freshness timer. Reopen/reload the app online for verification; do not assume a running card automatically updates after a backend write.

Recommendation: one verified manual run immediately before a short evaluation, no scheduler. For recurring evaluation beyond a week, weekly Monday 00:00 UTC (`0 0 * * 1`) is the smallest practical regular cadence consistent with the nine-day UI threshold and its two-day weekly grace. Monitor failures; do not wait for the UI threshold to diagnose them. Daily only if the evaluation explicitly needs daily changes. This is a recommendation, not a config/contract modification. The example is daily; the actual deployed cadence cannot be read yet.

## Ordered future release commands

Use PowerShell from this repository and an existing Python environment containing backend requirements. Stop on every nonzero exit; do not paste this whole section as an unattended script. No controller is invoked during preparation. Operator values come from the separate checklist, not secret output.

1. After explicit billing authorization, set the chosen account and link it. Verify project identity first.

```powershell
$env:CLOUDSDK_CORE_DISABLE_PROMPTS = 'true'
$env:CLOUDSDK_CORE_SHOULD_PROMPT_TO_ENABLE_API = 'false'
gcloud config get-value project
gcloud projects describe foreseeme-83587 --format='json(projectId,projectNumber,lifecycleState)' --quiet
$BillingAccountId = '<authorized-billing-account-id>'
gcloud billing projects link foreseeme-83587 --billing-account=$BillingAccountId --quiet
gcloud billing projects describe foreseeme-83587 --format='json(projectId,billingEnabled)' --quiet
```

2. After authorization, enable only the five missing APIs required by the compute controller; re-read the list first in case state changed. The nine total required APIs are the four enabled and five missing listed above. No Cloud Build, FCM enablement or HTTP service deployment is needed for this plan.

```powershell
gcloud services list --enabled --project=foreseeme-83587 --format='value(config.name)' --quiet
gcloud services enable run.googleapis.com cloudscheduler.googleapis.com artifactregistry.googleapis.com iam.googleapis.com cloudbilling.googleapis.com --project=foreseeme-83587 --quiet
```

Then stop until separately authorized prerequisite setup is complete. Required accounts must exist/enabled; jobs SA needs unconditional roles/datastore.user; scheduler SA needs unconditional roles/run.invoker at project scope for first creation (existing-job scope accepted later); Scheduler service agent needs roles/cloudscheduler.serviceAgent. Operator needs job/scheduler writes, service-account actAs, registry reads, logging reads and operator ADC Firestore reads. Validate image-pull identity/access. This document deliberately includes no IAM grant or service-account creation commands because those need separate review.

3. Verify prerequisites and actual digest. Review the ignored config privately; export reviewed settings into this PowerShell session using `$env:NAME = 'reviewed-value'`, including every compute REQUIRED variable from config.env.example. Do not print/source secret-bearing config or use automatic translation from shell syntax. Review ambient project/key/emulator variables. Set IMAGE to the verified immutable reference, never a placeholder.

```powershell
gcloud iam service-accounts describe risk-jobs-sa@foreseeme-83587.iam.gserviceaccount.com --project=foreseeme-83587 --format='json(email,disabled)' --quiet
gcloud iam service-accounts describe scheduler-invoker-sa@foreseeme-83587.iam.gserviceaccount.com --project=foreseeme-83587 --format='json(email,disabled)' --quiet
gcloud projects get-iam-policy foreseeme-83587 --format=json --quiet
gcloud artifacts repositories list --project=foreseeme-83587 --location=us-central1 --quiet
gcloud artifacts docker images list us-central1-docker.pkg.dev/foreseeme-83587/backend --include-tags --quiet
gcloud artifacts docker images describe $env:IMAGE --project=foreseeme-83587 --format=json --quiet
Set-Location 'D:\FYP ForeSeeMe\fyp_foreseeme\backend'
python -c "import os; from deploy.compute_risk_control import Controller; Controller(dict(os.environ)).preflight()"
```

Preflight is read-only, including captured ADC token and limited Firestore reads; it rejects missing prerequisites. Runtime identity/content review still needs release evidence. If accounts, API reads, image, model or permissions fail, stop; do not improvise prerequisites or credentials.

4. For a scheduler-free evaluation, use the public one-time mode below. It performs full non-scheduler preflight, creates/updates the job and verifies the one execution it submits. Scheduler configuration, API and IAM are not prerequisites for this mode; omit them from the earlier recurring prerequisite steps. Its verifier requires all configured cities and at least five fresh documents, even with the shared minimum of 1. Existing schedules are neither inspected nor paused by this mode. Independently establish that unrelated triggers will not interfere; no claim of globally exclusive execution is made. The earlier standalone recurring preflight command is not needed: one-time runs its own mandatory preflight. Do not call internal controller methods from an ad hoc script.

```powershell
python -B deploy/compute_risk_control.py one-time
```

Run one task, zero retries, python command, attached jobs SA, explicit Firebase project and freshness env. One-time never creates/activates/modifies recurrence, including on failure. A verification timeout does not cancel a running execution; inspect that exact execution before retrying. Never execute again merely to collect evidence. Do not follow one-time with the separate verify wrapper, which executes again.

5. Before any schedule: confirm the output includes the evaluation city, sensible values and generatedAt matching this run; heartbeat counts/times and per-city status must agree. Partial success is degraded, not proof that the chosen city refreshed. Open/reload Flutter online in the same Firebase project with a supported city and read access. Confirm visible confidence/risk and updated age, no stale notice, and no active override masking the model. Check Firestore composite index/read rules if the query fails. Initial verification does not prove Flutter presentation or device connectivity.

6. Only after backend AND visible-card success, and only if recurrence is approved, create a weekly schedule. Read/list first to distinguish successful absence from errors. Choose create for confirmed absence or update for an existing schedule, leaving existing schedules paused until this step. Use a start date/time safely after card verification. If no recurring evaluation is needed, skip this step entirely.

```powershell
gcloud scheduler jobs list --project=foreseeme-83587 --location=us-central1 --quiet
# Confirmed absent: create. Existing paused: replace 'create' with 'update'.
gcloud scheduler jobs create http $env:COMPUTE_RISK_SCHEDULER_NAME --project=foreseeme-83587 --location=us-central1 --schedule='0 0 * * 1' --time-zone=UTC --uri="https://us-central1-run.googleapis.com/v2/projects/foreseeme-83587/locations/us-central1/jobs/$($env:COMPUTE_RISK_JOB_NAME):run" --http-method=POST --oauth-service-account-email=$env:SA_SCHEDULER --max-retry-attempts=0 --max-retry-duration=0s --quiet
# Only for an existing schedule updated above:
# gcloud scheduler jobs resume $env:COMPUTE_RISK_SCHEDULER_NAME --project=foreseeme-83587 --location=us-central1 --quiet
gcloud scheduler jobs describe $env:COMPUTE_RISK_SCHEDULER_NAME --project=foreseeme-83587 --location=us-central1 --format='json(state,schedule,timeZone,httpTarget,retryConfig)' --quiet
```

Verify ENABLED, weekly UTC, correct URI/OAuth identity and retry policy. Scheduler delivery is not exactly-once; date-key upserts limit duplicated documents but duplicated execution can still incur costs. Monitor the first scheduled execution by its exact execution/evidence. Do not use scheduler run-now or run dispatch controllers.

## Cost limits and shutdown

Keep one job/task, no task retries, no HTTP service, no dispatch, no backfill and no recurrence for a short evaluation. Resource values are a trial, not a promise of adequate memory. Measure execution duration and peak memory before enabling a schedule. Existing unrelated project usage is outside this preparation.

Cloud Run jobs bill for instance lifetime with a one-minute minimum ([Cloud Run pricing](https://cloud.google.com/run/pricing)). Paused Scheduler jobs still count toward billing; free allocation is shared by billing account ([Scheduler pricing](https://cloud.google.com/scheduler/pricing)). Registry storage, Firestore reads/writes/storage, logging, network transfer and external data usage may add costs. Total cannot yet be estimated without actual image size, runtime/memory, Firestore location/usage, evaluation duration, log retention, other account usage/free allocation and source-access terms. Source acquisition may dominate duration because cache is ephemeral. Enabling an API alone is not an evaluation spend estimate.

Shutdown checklist (future authorized session):

- [ ] Pause the approved compute schedule and confirm PAUSED. Inspect dispatch schedules too; pause only ones authorized for shutdown. Do not run them.
- [ ] List job executions; wait for an already-started execution to finish, or separately authorize cancellation. Pause prevents future dispatch, not an execution already running.
- [ ] Confirm no other scheduler/event source triggers this compute job. Keep riskEstimates, heartbeat and necessary evaluation data intact.
- [ ] If no schedule was created, there is no scheduler shutdown step. An idle Cloud Run Job definition does not execute itself.
- [ ] Review retained registry/log/Firestore costs. Deleting an evaluation-only Scheduler definition can avoid its retained job charge, but requires explicit deletion authorization; retain the runbook and data. Do not delete models/data or unlink billing blindly.

```powershell
gcloud scheduler jobs pause $env:COMPUTE_RISK_SCHEDULER_NAME --project=foreseeme-83587 --location=us-central1 --quiet
gcloud scheduler jobs describe $env:COMPUTE_RISK_SCHEDULER_NAME --project=foreseeme-83587 --location=us-central1 --format='value(state)' --quiet
gcloud run jobs executions list --job=$env:COMPUTE_RISK_JOB_NAME --project=foreseeme-83587 --region=us-central1 --quiet
```

Scheduler CLI flags follow the official [create HTTP reference](https://docs.cloud.google.com/sdk/gcloud/reference/scheduler/jobs/create/http). These commands are staged instructions only; none of the release/shutdown operations above were run during preparation.
