#!/usr/bin/env bash
# ForeSeeMe — Phase 1 verification: compute_risk Cloud Run Job + Cloud Scheduler.
#
# Run AFTER provision_compute_risk.sh. Triggers one real execution and checks
# it succeeded, so you don't have to wait until next Monday to find out.
#
# Usage:
#   source deploy/config.env
#   ./deploy/verify_compute_risk.sh

set -euo pipefail

: "${PROJECT_ID:?Set PROJECT_ID}"
: "${REGION:?Set REGION}"
: "${JOB_NAME:?Set JOB_NAME}"
: "${SCHEDULER_NAME:?Set SCHEDULER_NAME}"

echo "== 1. Resource existence checks ======================================="
gcloud run jobs describe "${JOB_NAME}" --region="${REGION}" --project="${PROJECT_ID}" \
  --format="yaml(metadata.name, spec.template.spec.template.spec.serviceAccountName, spec.template.spec.template.spec.containers[0].image)"

gcloud scheduler jobs describe "${SCHEDULER_NAME}" --location="${REGION}" --project="${PROJECT_ID}" \
  --format="yaml(name, schedule, timeZone, httpTarget.uri, state)"

echo "== 2. Trigger one real execution now (don't wait for Monday) =========="
gcloud scheduler jobs run "${SCHEDULER_NAME}" --location="${REGION}" --project="${PROJECT_ID}"

echo "Waiting for the Cloud Run execution to appear..."
EXECUTION=""
for i in $(seq 1 30); do
  EXECUTION="$(gcloud run jobs executions list \
    --job="${JOB_NAME}" --region="${REGION}" --project="${PROJECT_ID}" \
    --sort-by="~metadata.creationTimestamp" --limit=1 \
    --format="value(metadata.name)" 2>/dev/null || true)"
  [ -n "${EXECUTION}" ] && break
  sleep 2
done
if [ -z "${EXECUTION}" ]; then
  echo "No execution appeared after 60s — check Scheduler's last attempt:"
  echo "  gcloud scheduler jobs describe ${SCHEDULER_NAME} --location=${REGION} --format='yaml(status)'"
  exit 1
fi
echo "Execution: ${EXECUTION}"

echo "== 3. Wait for completion, then show status ==========================="
for i in $(seq 1 60); do
  STATUS="$(gcloud run jobs executions describe "${EXECUTION}" \
    --region="${REGION}" --project="${PROJECT_ID}" \
    --format="value(status.conditions[0].type,status.conditions[0].status)")"
  echo "  poll ${i}: ${STATUS}"
  echo "${STATUS}" | grep -q "Completed.*True\|Failed.*True" && break
  sleep 5
done
gcloud run jobs executions describe "${EXECUTION}" \
  --region="${REGION}" --project="${PROJECT_ID}" \
  --format="yaml(status.succeededCount, status.failedCount, status.conditions)"

echo "== 4. Job stdout/stderr (per-city outcomes + heartbeat status line) ==="
gcloud logging read \
  "resource.type=\"cloud_run_job\" AND resource.labels.job_name=\"${JOB_NAME}\" AND labels.\"run.googleapis.com/execution_name\"=\"${EXECUTION}\"" \
  --project="${PROJECT_ID}" --limit=200 --order=asc \
  --format="value(textPayload, jsonPayload.message)"

echo "== 5. Structured job_run signal (observability, Sprint 5 P12) ========="
gcloud logging read \
  "resource.type=\"cloud_run_job\" AND resource.labels.job_name=\"${JOB_NAME}\" AND jsonPayload.event=\"job_run\"" \
  --project="${PROJECT_ID}" --limit=1 --order=desc --format=json

echo
echo "== Manual validation checklist ========================================"
cat <<'EOF'
[ ] Execution status above shows Completed=True, failedCount=0.
[ ] Step 4 output lists all 5 cities as "written" (or explains any
    skipped/error with a real reason — a city being skipped is not
    itself a failure if others succeeded).
[ ] Step 5's job_run log shows status="ok" (not "degraded"/"failed").
[ ] jobHeartbeats/compute_risk in Firestore has a fresh finishedAt
    (use deploy/read_heartbeat.py, or the Firebase console — this
    collection is service-only, denied to clients by firestore.rules).
[ ] riskEstimates/{city}_{today's date} documents exist with the new
    generatedAt (Firebase console, or the app's Risk Card after a refresh).
[ ] Cloud Scheduler job state is ENABLED (from step 1's describe output).
[ ] No unexpected IAM errors in step 4's logs (would indicate the
    SA_JOBS role binding from provisioning didn't take effect).
EOF
