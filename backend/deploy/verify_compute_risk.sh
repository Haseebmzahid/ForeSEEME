#!/usr/bin/env bash
# ForeSeeMe — verify compute_risk's Cloud Run Job + Cloud Scheduler.
#
# Run AFTER provision_compute_risk.sh. Triggers one real execution and checks
# it succeeded, so you don't have to wait until the next scheduled run.
#
# Usage:
#   source deploy/config.env
#   ./deploy/verify_compute_risk.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

: "${PROJECT_ID:?Set PROJECT_ID}"
: "${REGION:?Set REGION}"
: "${COMPUTE_RISK_JOB_NAME:?Set COMPUTE_RISK_JOB_NAME}"
: "${COMPUTE_RISK_SCHEDULER_NAME:?Set COMPUTE_RISK_SCHEDULER_NAME}"

JOB_NAME="${COMPUTE_RISK_JOB_NAME}"
SCHEDULER_NAME="${COMPUTE_RISK_SCHEDULER_NAME}"

echo "== 1. Resource existence checks ========================================"
gcloud run jobs describe "${JOB_NAME}" --region="${REGION}" --project="${PROJECT_ID}" \
  --format="yaml(metadata.name, spec.template.spec.template.spec.serviceAccountName, spec.template.spec.template.spec.containers[0].image)"

gcloud scheduler jobs describe "${SCHEDULER_NAME}" --location="${REGION}" --project="${PROJECT_ID}" \
  --format="yaml(name, schedule, timeZone, httpTarget.uri, state)"

echo "== 2. Trigger one real execution now ==================================="
EXECUTION="$(trigger_and_wait "${JOB_NAME}" "${SCHEDULER_NAME}")"
echo "Execution: ${EXECUTION}"

echo "== 3. Execution result =================================================="
gcloud run jobs executions describe "${EXECUTION}" \
  --region="${REGION}" --project="${PROJECT_ID}" \
  --format="yaml(status.succeededCount, status.failedCount, status.conditions)"

echo "== 4. Job stdout/stderr (per-city outcomes + heartbeat status line) ===="
gcloud logging read \
  "resource.type=\"cloud_run_job\" AND resource.labels.job_name=\"${JOB_NAME}\" AND labels.\"run.googleapis.com/execution_name\"=\"${EXECUTION}\"" \
  --project="${PROJECT_ID}" --limit=200 --order=asc \
  --format="value(textPayload, jsonPayload.message)"

echo "== 5. Structured job_run signal (observability, Sprint 5 P12) =========="
gcloud logging read \
  "resource.type=\"cloud_run_job\" AND resource.labels.job_name=\"${JOB_NAME}\" AND jsonPayload.event=\"job_run\"" \
  --project="${PROJECT_ID}" --limit=1 --order=desc --format=json

echo
echo "== Manual validation checklist =========================================="
cat <<'EOF'
[ ] Execution status above shows Completed=True, failedCount=0.
[ ] Step 4 output lists all 5 cities as "written" (or explains any
    skipped/error with a real reason — a city being skipped is not
    itself a failure if others succeeded).
[ ] Step 5's job_run log shows status="ok" (not "degraded"/"failed").
[ ] jobHeartbeats/compute_risk in Firestore has a fresh finishedAt
    (use deploy/read_heartbeat.py --job compute_risk, or the Firebase
    console — this collection is service-only, denied to clients).
[ ] riskEstimates/{city}_{today's date} documents exist with the new
    generatedAt (Firebase console, or the app's Risk Card after a refresh).
[ ] Cloud Scheduler job state is ENABLED and schedule reads "0 0 * * *"
    (daily, not weekly — Phase 2 cadence change).
[ ] No unexpected IAM errors in step 4's logs.
EOF
