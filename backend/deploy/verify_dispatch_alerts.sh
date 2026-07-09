#!/usr/bin/env bash
# ForeSeeMe — verify dispatch_alerts' Cloud Run Job + Cloud Scheduler.
#
# Run AFTER provision_dispatch_alerts.sh (and after compute_risk has written
# at least one riskEstimates doc per city — dispatch_alerts needs "latest
# two" per city to detect a transition; with only one estimate on record it
# will correctly report zero sends, which is `ok`, not a failure).
#
# Usage:
#   source deploy/config.env
#   ./deploy/verify_dispatch_alerts.sh [--project-id <id>]   # project id used
#                                                             # by the python
#                                                             # audit helpers

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

: "${PROJECT_ID:?Set PROJECT_ID}"
: "${REGION:?Set REGION}"
: "${DISPATCH_ALERTS_JOB_NAME:?Set DISPATCH_ALERTS_JOB_NAME}"
: "${DISPATCH_ALERTS_SCHEDULER_NAME:?Set DISPATCH_ALERTS_SCHEDULER_NAME}"

JOB_NAME="${DISPATCH_ALERTS_JOB_NAME}"
SCHEDULER_NAME="${DISPATCH_ALERTS_SCHEDULER_NAME}"

echo "== 1. Resource existence checks ========================================"
gcloud run jobs describe "${JOB_NAME}" --region="${REGION}" --project="${PROJECT_ID}" \
  --format="yaml(metadata.name, spec.template.spec.template.spec.serviceAccountName, spec.template.spec.template.spec.containers[0].image)"

gcloud scheduler jobs describe "${SCHEDULER_NAME}" --location="${REGION}" --project="${PROJECT_ID}" \
  --format="yaml(name, schedule, timeZone, httpTarget.uri, state)"

echo "== 2. Trigger one real execution now ===================================="
EXECUTION_1="$(trigger_and_wait "${JOB_NAME}" "${SCHEDULER_NAME}")"
echo "Execution 1: ${EXECUTION_1}"

echo "== 3. Execution result =================================================="
gcloud run jobs executions describe "${EXECUTION_1}" \
  --region="${REGION}" --project="${PROJECT_ID}" \
  --format="yaml(status.succeededCount, status.failedCount, status.conditions)"

echo "== 4. Job stdout/stderr (per-user dispatch outcomes) ===================="
gcloud logging read \
  "resource.type=\"cloud_run_job\" AND resource.labels.job_name=\"${JOB_NAME}\" AND labels.\"run.googleapis.com/execution_name\"=\"${EXECUTION_1}\"" \
  --project="${PROJECT_ID}" --limit=200 --order=asc \
  --format="value(textPayload, jsonPayload.message)"

echo "== 5. Structured job_run signal (observability, Sprint 5 P12) =========="
gcloud logging read \
  "resource.type=\"cloud_run_job\" AND resource.labels.job_name=\"${JOB_NAME}\" AND jsonPayload.event=\"job_run\"" \
  --project="${PROJECT_ID}" --limit=1 --order=desc --format=json

echo "== 6. Idempotency check: trigger again immediately ======================"
echo "A second run within the same cycle must show skipped_idempotent for any"
echo "user who received a send in execution 1 -- never a duplicate send."
EXECUTION_2="$(trigger_and_wait "${JOB_NAME}" "${SCHEDULER_NAME}")"
echo "Execution 2: ${EXECUTION_2}"
gcloud logging read \
  "resource.type=\"cloud_run_job\" AND resource.labels.job_name=\"${JOB_NAME}\" AND labels.\"run.googleapis.com/execution_name\"=\"${EXECUTION_2}\"" \
  --project="${PROJECT_ID}" --limit=200 --order=asc \
  --format="value(textPayload, jsonPayload.message)"

echo
echo "== Manual validation checklist ==========================================="
cat <<'EOF'
[ ] Both executions show Completed=True, failedCount=0.
[ ] Step 5's job_run log shows status="ok" (zero sends is `ok` here by
    design -- only an actual FCM send failure grades "degraded").
[ ] Execution 2 (step 6) shows skipped_idempotent for anything execution 1
    sent -- proves idempotency (no duplicate alertDispatchLog / no
    duplicate FCM send / no duplicate userAlerts doc for the same estimate).
[ ] Audit log populated:
      python deploy/read_dispatch_audit.py --project <id> log
    shows recent alertDispatchLog entries (status=sent/skipped_*/failed as
    applicable).
[ ] Notification Center populated (only for a "sent" outcome):
      python deploy/read_dispatch_audit.py --project <id> inbox --uid <uid>
    shows the userAlerts/{uid}/items doc, and the Flutter app's alert inbox
    screen reflects it after a refresh/relaunch.
[ ] jobHeartbeats/dispatch_alerts has a fresh finishedAt:
      python deploy/read_heartbeat.py --project <id> --job dispatch_alerts

NOT verifiable from this script (external dependency, not a code gap):
  - Genuine FCM push DELIVERY to a physical/emulated device. That requires a
    real user with a real fcmToken captured by a running, signed-in Flutter
    app instance -- outside what a backend deployment script can produce.
    If no user matched the targeting predicate this cycle (no risk
    transition, or no consenting user), step 4/6 will show zero sends,
    which is the correct, expected `ok` outcome, not a failure to chase.
EOF
