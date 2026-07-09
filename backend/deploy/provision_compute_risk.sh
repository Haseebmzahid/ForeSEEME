#!/usr/bin/env bash
# ForeSeeMe — provision compute_risk (Cloud Scheduler -> Cloud Run Job).
# Follows ADR-002. Idempotent: safe to re-run.
#
# Phase 2 update: cadence changed from weekly to DAILY (see config.env.example
# for why). No change to app/jobs/compute_risk.py was needed for this.
#
# Usage (run from backend/):
#   cp deploy/config.env.example deploy/config.env   # adjust if needed
#   source deploy/config.env
#   ./deploy/provision_compute_risk.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

: "${PROJECT_ID:?Set PROJECT_ID (see deploy/config.env.example)}"
: "${REGION:?Set REGION}"
: "${IMAGE:?Set IMAGE}"
: "${SA_JOBS:?Set SA_JOBS}" "${SA_JOBS_ID:?Set SA_JOBS_ID}"
: "${SA_SCHEDULER:?Set SA_SCHEDULER}" "${SA_SCHEDULER_ID:?Set SA_SCHEDULER_ID}"
: "${COMPUTE_RISK_JOB_NAME:?Set COMPUTE_RISK_JOB_NAME}"
: "${COMPUTE_RISK_SCHEDULER_NAME:?Set COMPUTE_RISK_SCHEDULER_NAME}"
: "${COMPUTE_RISK_SCHEDULE:?Set COMPUTE_RISK_SCHEDULE}"
: "${COMPUTE_RISK_TIME_ZONE:?Set COMPUTE_RISK_TIME_ZONE}"
: "${COMPUTE_RISK_TIMEOUT:?Set COMPUTE_RISK_TIMEOUT}"
: "${COMPUTE_RISK_MEMORY:?Set COMPUTE_RISK_MEMORY}"
: "${COMPUTE_RISK_CPU:?Set COMPUTE_RISK_CPU}"
: "${RISK_LOOKBACK_WEEKS:?Set RISK_LOOKBACK_WEEKS}"
: "${LOG_LEVEL:?Set LOG_LEVEL}"

echo "== Preflight ==========================================================="
require_gcloud_project

echo "== 1. Enable required APIs ============================================="
enable_apis

echo "== 2. Artifact Registry repo ============================================"
ensure_artifact_registry

echo "== 3. Build & push image (shared by all jobs) =========================="
build_and_push_image

echo "== 4. Service accounts =================================================="
ensure_service_account "${SA_JOBS}" "${SA_JOBS_ID}" \
  "ForeSeeMe scheduled jobs (compute_risk, dispatch_alerts, weekly_report)"
ensure_service_account "${SA_SCHEDULER}" "${SA_SCHEDULER_ID}" \
  "Cloud Scheduler -> Cloud Run Jobs invoker"

# compute_risk needs Firestore read/write only (riskEstimates + jobHeartbeats).
# NOTE: roles/firebasemessaging.admin is NOT granted here — that's
# dispatch_alerts' requirement, added by provision_dispatch_alerts.sh
# (least-privilege, added only when the job that needs it is provisioned).
grant_project_role "serviceAccount:${SA_JOBS}" "roles/datastore.user"

echo "== 5. Cloud Run Job: ${COMPUTE_RISK_JOB_NAME} =========================="
# No JSON key involved: authenticates as SA_JOBS via its attached identity
# (Application Default Credentials) -- app/jobs/compute_risk.py's
# init_firestore_repository() already supports this with zero code change.
create_or_update_run_job "${COMPUTE_RISK_JOB_NAME}" \
  --image="${IMAGE}" \
  --region="${REGION}" \
  --project="${PROJECT_ID}" \
  --service-account="${SA_JOBS}" \
  --command="python" \
  --args="-m,app.jobs.compute_risk" \
  --set-env-vars="LOG_LEVEL=${LOG_LEVEL},RISK_LOOKBACK_WEEKS=${RISK_LOOKBACK_WEEKS}" \
  --memory="${COMPUTE_RISK_MEMORY}" \
  --cpu="${COMPUTE_RISK_CPU}" \
  --task-timeout="${COMPUTE_RISK_TIMEOUT}" \
  --max-retries=1

grant_run_invoker "${COMPUTE_RISK_JOB_NAME}" "serviceAccount:${SA_SCHEDULER}"

echo "== 6. Cloud Scheduler: ${COMPUTE_RISK_SCHEDULER_NAME} (daily) =========="
create_or_update_scheduler \
  "${COMPUTE_RISK_SCHEDULER_NAME}" \
  "${COMPUTE_RISK_SCHEDULE}" \
  "${COMPUTE_RISK_TIME_ZONE}" \
  "$(run_job_uri "${COMPUTE_RISK_JOB_NAME}")" \
  "${SA_SCHEDULER}"

echo "== Done ================================================================="
echo "Provisioned: image, ${SA_JOBS_ID}, ${SA_SCHEDULER_ID},"
echo "Cloud Run Job '${COMPUTE_RISK_JOB_NAME}', Cloud Scheduler '${COMPUTE_RISK_SCHEDULER_NAME}' (daily)."
echo "Next: ./deploy/verify_compute_risk.sh"
