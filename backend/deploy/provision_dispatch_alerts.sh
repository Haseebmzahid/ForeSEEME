#!/usr/bin/env bash
# ForeSeeMe — provision dispatch_alerts (Cloud Scheduler -> Cloud Run Job).
# Follows ADR-002. Sibling of compute_risk; same deployment style (Phase 1),
# reusing the shared common.sh helpers so nothing is duplicated.
#
# Scheduled 10 minutes after compute_risk's daily run (soft ordering by
# schedule offset — see config.env.example and the architecture discussion:
# no Pub/Sub/Eventarc/Workflows introduced, per the explicit constraint).
#
# Usage (run from backend/):
#   source deploy/config.env
#   ./deploy/provision_dispatch_alerts.sh
#
# Prerequisite: provision_compute_risk.sh should already have run at least
# once (creates the shared SA_JOBS/SA_SCHEDULER and Artifact Registry repo),
# though this script is idempotent and safe to run first too.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

: "${PROJECT_ID:?Set PROJECT_ID (see deploy/config.env.example)}"
: "${REGION:?Set REGION}"
: "${IMAGE:?Set IMAGE}"
: "${SA_JOBS:?Set SA_JOBS}" "${SA_JOBS_ID:?Set SA_JOBS_ID}"
: "${SA_SCHEDULER:?Set SA_SCHEDULER}" "${SA_SCHEDULER_ID:?Set SA_SCHEDULER_ID}"
: "${DISPATCH_ALERTS_JOB_NAME:?Set DISPATCH_ALERTS_JOB_NAME}"
: "${DISPATCH_ALERTS_SCHEDULER_NAME:?Set DISPATCH_ALERTS_SCHEDULER_NAME}"
: "${DISPATCH_ALERTS_SCHEDULE:?Set DISPATCH_ALERTS_SCHEDULE}"
: "${DISPATCH_ALERTS_TIME_ZONE:?Set DISPATCH_ALERTS_TIME_ZONE}"
: "${DISPATCH_ALERTS_TIMEOUT:?Set DISPATCH_ALERTS_TIMEOUT}"
: "${DISPATCH_ALERTS_MEMORY:?Set DISPATCH_ALERTS_MEMORY}"
: "${DISPATCH_ALERTS_CPU:?Set DISPATCH_ALERTS_CPU}"
: "${LOG_LEVEL:?Set LOG_LEVEL}"

echo "== Preflight ==========================================================="
require_gcloud_project

echo "== 1. Enable required APIs ============================================="
enable_apis

echo "== 2. Artifact Registry repo ============================================"
ensure_artifact_registry

echo "== 3. Build & push image (shared by all jobs) =========================="
# Same image as compute_risk -- rebuilding here is a harmless no-op if the
# source hasn't changed since compute_risk's provisioning; kept so this
# script is runnable standalone.
build_and_push_image

echo "== 4. Service accounts =================================================="
ensure_service_account "${SA_JOBS}" "${SA_JOBS_ID}" \
  "ForeSeeMe scheduled jobs (compute_risk, dispatch_alerts, weekly_report)"
ensure_service_account "${SA_SCHEDULER}" "${SA_SCHEDULER_ID}" \
  "Cloud Scheduler -> Cloud Run Jobs invoker"

# dispatch_alerts needs Firestore read/write (riskEstimates read;
# alertDispatchLog + userAlerts + jobHeartbeats write) AND FCM send. The
# Firestore role is idempotent to re-grant if compute_risk's script already
# ran; the FCM role is dispatch_alerts' addition, layered on now that this
# is the job that actually needs it (least-privilege, phase-scoped — see
# backend/deploy/README.md).
grant_project_role "serviceAccount:${SA_JOBS}" "roles/datastore.user"
grant_project_role "serviceAccount:${SA_JOBS}" "roles/firebasemessaging.admin"

echo "== 5. Cloud Run Job: ${DISPATCH_ALERTS_JOB_NAME} ======================="
create_or_update_run_job "${DISPATCH_ALERTS_JOB_NAME}" \
  --image="${IMAGE}" \
  --region="${REGION}" \
  --project="${PROJECT_ID}" \
  --service-account="${SA_JOBS}" \
  --command="python" \
  --args="-m,app.jobs.dispatch_alerts" \
  --set-env-vars="LOG_LEVEL=${LOG_LEVEL}" \
  --memory="${DISPATCH_ALERTS_MEMORY}" \
  --cpu="${DISPATCH_ALERTS_CPU}" \
  --task-timeout="${DISPATCH_ALERTS_TIMEOUT}" \
  --max-retries=1

grant_run_invoker "${DISPATCH_ALERTS_JOB_NAME}" "serviceAccount:${SA_SCHEDULER}"

echo "== 6. Cloud Scheduler: ${DISPATCH_ALERTS_SCHEDULER_NAME} (daily, +10min) =="
create_or_update_scheduler \
  "${DISPATCH_ALERTS_SCHEDULER_NAME}" \
  "${DISPATCH_ALERTS_SCHEDULE}" \
  "${DISPATCH_ALERTS_TIME_ZONE}" \
  "$(run_job_uri "${DISPATCH_ALERTS_JOB_NAME}")" \
  "${SA_SCHEDULER}"

echo "== Done ================================================================="
echo "Provisioned: image, ${SA_JOBS_ID} (+firebasemessaging.admin), ${SA_SCHEDULER_ID},"
echo "Cloud Run Job '${DISPATCH_ALERTS_JOB_NAME}', Cloud Scheduler '${DISPATCH_ALERTS_SCHEDULER_NAME}' (daily, 10min after compute_risk)."
echo "Next: ./deploy/verify_dispatch_alerts.sh"
