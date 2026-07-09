#!/usr/bin/env bash
# ForeSeeMe — Phase 1 production provisioning: compute_risk ONLY.
#
# Follows ADR-002 (Cloud Scheduler -> Cloud Run) and docs/deployment.md.
# Scope is deliberately narrow: this script provisions exactly what compute_risk
# needs. dispatch_alerts / weekly_report are NOT provisioned here (Phase 2+).
#
# Idempotent: safe to re-run. Each step checks for the resource before
# creating it, or uses `update`/`add-iam-policy-binding` which are themselves
# idempotent.
#
# Prerequisites (not automated by this script):
#   - gcloud CLI installed and authenticated (`gcloud auth login`)
#   - `gcloud config set project <project>` OR pass PROJECT_ID below
#   - APIs billing enabled on the project (Cloud Build/Run/Scheduler are
#     enabled by this script, but billing itself must already be active)
#
# Usage:
#   cp deploy/config.env.example deploy/config.env   # adjust if needed
#   source deploy/config.env
#   ./deploy/provision_compute_risk.sh
#
# Run from the `backend/` directory (so the Cloud Build context is correct).

set -euo pipefail

# --- Load config --------------------------------------------------------
: "${PROJECT_ID:?Set PROJECT_ID (see deploy/config.env.example)}"
: "${REGION:?Set REGION}"
: "${AR_REPO:?Set AR_REPO}"
: "${IMAGE:?Set IMAGE}"
: "${SA_JOBS:?Set SA_JOBS}"
: "${SA_JOBS_ID:?Set SA_JOBS_ID}"
: "${SA_SCHEDULER:?Set SA_SCHEDULER}"
: "${SA_SCHEDULER_ID:?Set SA_SCHEDULER_ID}"
: "${JOB_NAME:?Set JOB_NAME}"
: "${JOB_TIMEOUT:?Set JOB_TIMEOUT}"
: "${JOB_MEMORY:?Set JOB_MEMORY}"
: "${JOB_CPU:?Set JOB_CPU}"
: "${RISK_LOOKBACK_WEEKS:?Set RISK_LOOKBACK_WEEKS}"
: "${LOG_LEVEL:?Set LOG_LEVEL}"
: "${SCHEDULER_NAME:?Set SCHEDULER_NAME}"
: "${SCHEDULE:?Set SCHEDULE}"
: "${TIME_ZONE:?Set TIME_ZONE}"

echo "== Preflight =========================================================="
command -v gcloud >/dev/null 2>&1 || { echo "gcloud CLI not found. Install it first."; exit 1; }
ACTIVE_PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
if [ "$ACTIVE_PROJECT" != "$PROJECT_ID" ]; then
  echo "gcloud active project is '${ACTIVE_PROJECT}', expected '${PROJECT_ID}'."
  echo "Run: gcloud config set project ${PROJECT_ID}"
  exit 1
fi
echo "Project OK: ${PROJECT_ID}"

echo "== 1. Enable required APIs ============================================"
gcloud services enable \
  run.googleapis.com \
  cloudscheduler.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  --project="${PROJECT_ID}"

echo "== 2. Artifact Registry repo ==========================================="
if ! gcloud artifacts repositories describe "${AR_REPO}" \
      --location="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud artifacts repositories create "${AR_REPO}" \
    --repository-format=docker \
    --location="${REGION}" \
    --project="${PROJECT_ID}" \
    --description="ForeSeeMe backend images (risk service + scheduled jobs)"
else
  echo "Repo ${AR_REPO} already exists."
fi

echo "== 3. Build & push image (Cloud Build — no local Docker needed) ======="
# Run from backend/ so the Dockerfile at ./Dockerfile is the build context.
gcloud builds submit . --tag="${IMAGE}" --project="${PROJECT_ID}"

echo "== 4. Service accounts ================================================="
if ! gcloud iam service-accounts describe "${SA_JOBS}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud iam service-accounts create "${SA_JOBS_ID}" \
    --project="${PROJECT_ID}" \
    --display-name="ForeSeeMe scheduled jobs (compute_risk, dispatch_alerts, weekly_report)"
else
  echo "SA ${SA_JOBS} already exists."
fi

if ! gcloud iam service-accounts describe "${SA_SCHEDULER}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud iam service-accounts create "${SA_SCHEDULER_ID}" \
    --project="${PROJECT_ID}" \
    --display-name="Cloud Scheduler -> Cloud Run Jobs invoker"
else
  echo "SA ${SA_SCHEDULER} already exists."
fi

# compute_risk needs Firestore read/write only (riskEstimates + jobHeartbeats).
# NOTE: do NOT add roles/firebasemessaging.admin here — that's dispatch_alerts'
# requirement, added in Phase 2, not before (least-privilege, phase-scoped).
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${SA_JOBS}" \
  --role="roles/datastore.user" \
  --condition=None >/dev/null

echo "== 5. Cloud Run Job: ${JOB_NAME} ========================================"
# No JSON key involved: the job authenticates as SA_JOBS via its attached
# identity (Application Default Credentials), which app/jobs/compute_risk.py's
# init_firestore_repository() already picks up with zero code change.
COMMON_ARGS=(
  --image="${IMAGE}"
  --region="${REGION}"
  --project="${PROJECT_ID}"
  --service-account="${SA_JOBS}"
  --command="python"
  --args="-m,app.jobs.compute_risk"
  --set-env-vars="LOG_LEVEL=${LOG_LEVEL},RISK_LOOKBACK_WEEKS=${RISK_LOOKBACK_WEEKS}"
  --memory="${JOB_MEMORY}"
  --cpu="${JOB_CPU}"
  --task-timeout="${JOB_TIMEOUT}"
  --max-retries=1
)
if gcloud run jobs describe "${JOB_NAME}" --region="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud run jobs update "${JOB_NAME}" "${COMMON_ARGS[@]}"
else
  gcloud run jobs create "${JOB_NAME}" "${COMMON_ARGS[@]}"
fi

# Let the scheduler's invoker SA (only) trigger executions of this one job.
gcloud run jobs add-iam-policy-binding "${JOB_NAME}" \
  --region="${REGION}" \
  --project="${PROJECT_ID}" \
  --member="serviceAccount:${SA_SCHEDULER}" \
  --role="roles/run.invoker" >/dev/null

echo "== 6. Cloud Scheduler: ${SCHEDULER_NAME} ==============================="
RUN_URI="https://${REGION}-run.googleapis.com/v2/projects/${PROJECT_ID}/locations/${REGION}/jobs/${JOB_NAME}:run"
if gcloud scheduler jobs describe "${SCHEDULER_NAME}" --location="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud scheduler jobs update http "${SCHEDULER_NAME}" \
    --location="${REGION}" \
    --project="${PROJECT_ID}" \
    --schedule="${SCHEDULE}" \
    --time-zone="${TIME_ZONE}" \
    --uri="${RUN_URI}" \
    --http-method=POST \
    --oauth-service-account-email="${SA_SCHEDULER}"
else
  gcloud scheduler jobs create http "${SCHEDULER_NAME}" \
    --location="${REGION}" \
    --project="${PROJECT_ID}" \
    --schedule="${SCHEDULE}" \
    --time-zone="${TIME_ZONE}" \
    --uri="${RUN_URI}" \
    --http-method=POST \
    --oauth-service-account-email="${SA_SCHEDULER}"
fi

echo "== Done ================================================================"
echo "Provisioned: Artifact Registry image, ${SA_JOBS_ID}, ${SA_SCHEDULER_ID},"
echo "Cloud Run Job '${JOB_NAME}', Cloud Scheduler '${SCHEDULER_NAME}'."
echo "Next: run ./deploy/verify_compute_risk.sh"
