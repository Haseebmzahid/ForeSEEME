#!/usr/bin/env bash
# ForeSeeMe — shared gcloud provisioning helpers for scheduled backend jobs.
#
# Sourced by provision_<job>.sh scripts (compute_risk, dispatch_alerts, and any
# future sibling job). Not meant to be run directly. Factored out in Phase 2
# once a second job needed the same ~10 gcloud steps, so job-specific scripts
# stay short and nothing is duplicated (Phase 1's provision_compute_risk.sh
# had all of this inline; it now sources this file too).
#
# Every function is idempotent (describe-then-create/update, or an
# inherently-idempotent `add-iam-policy-binding`), matching the Phase 1
# convention: safe to re-run.

set -euo pipefail

require_gcloud_project() {
  command -v gcloud >/dev/null 2>&1 || { echo "gcloud CLI not found. Install it first."; exit 1; }
  local active
  active="$(gcloud config get-value project 2>/dev/null || true)"
  if [ "${active}" != "${PROJECT_ID}" ]; then
    echo "gcloud active project is '${active}', expected '${PROJECT_ID}'."
    echo "Run: gcloud config set project ${PROJECT_ID}"
    exit 1
  fi
  echo "Project OK: ${PROJECT_ID}"
}

enable_apis() {
  gcloud services enable \
    run.googleapis.com \
    cloudscheduler.googleapis.com \
    cloudbuild.googleapis.com \
    artifactregistry.googleapis.com \
    --project="${PROJECT_ID}"
}

ensure_artifact_registry() {
  if ! gcloud artifacts repositories describe "${AR_REPO}" \
        --location="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    gcloud artifacts repositories create "${AR_REPO}" \
      --repository-format=docker \
      --location="${REGION}" \
      --project="${PROJECT_ID}" \
      --description="ForeSeeMe backend images (risk service + scheduled jobs)"
  else
    echo "Artifact Registry repo ${AR_REPO} already exists."
  fi
}

build_and_push_image() {
  # ONE image shared by every job (ADR-002: "one deployable artifact") — only
  # the Cloud Run Job's --command/--args override differs per job. Built via
  # Cloud Build so no local Docker daemon is required.
  # Run from backend/ so ./Dockerfile is the build context.
  gcloud builds submit . --tag="${IMAGE}" --project="${PROJECT_ID}"
}

ensure_service_account() {
  local sa_email="$1" sa_id="$2" display_name="$3"
  if ! gcloud iam service-accounts describe "${sa_email}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    gcloud iam service-accounts create "${sa_id}" \
      --project="${PROJECT_ID}" \
      --display-name="${display_name}"
  else
    echo "SA ${sa_email} already exists."
  fi
}

grant_project_role() {
  local member="$1" role="$2"
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="${member}" \
    --role="${role}" \
    --condition=None >/dev/null
}

# $1=job_name, remaining args are passed straight through to `gcloud run jobs
# create|update` (image, service-account, command/args, env, resources...).
create_or_update_run_job() {
  local job_name="$1"; shift
  if gcloud run jobs describe "${job_name}" --region="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    gcloud run jobs update "${job_name}" "$@"
  else
    gcloud run jobs create "${job_name}" "$@"
  fi
}

grant_run_invoker() {
  local job_name="$1" member="$2"
  gcloud run jobs add-iam-policy-binding "${job_name}" \
    --region="${REGION}" --project="${PROJECT_ID}" \
    --member="${member}" --role="roles/run.invoker" >/dev/null
}

run_job_uri() {
  local job_name="$1"
  echo "https://${REGION}-run.googleapis.com/v2/projects/${PROJECT_ID}/locations/${REGION}/jobs/${job_name}:run"
}

create_or_update_scheduler() {
  local scheduler_name="$1" schedule="$2" tz="$3" uri="$4" oauth_sa="$5"
  if gcloud scheduler jobs describe "${scheduler_name}" --location="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    gcloud scheduler jobs update http "${scheduler_name}" \
      --location="${REGION}" --project="${PROJECT_ID}" \
      --schedule="${schedule}" --time-zone="${tz}" \
      --uri="${uri}" --http-method=POST \
      --oauth-service-account-email="${oauth_sa}"
  else
    gcloud scheduler jobs create http "${scheduler_name}" \
      --location="${REGION}" --project="${PROJECT_ID}" \
      --schedule="${schedule}" --time-zone="${tz}" \
      --uri="${uri}" --http-method=POST \
      --oauth-service-account-email="${oauth_sa}"
  fi
}

# Waits for the most recent execution of a job to appear, then for it to
# finish. Shared by verify_<job>.sh scripts. Echoes the execution name.
trigger_and_wait() {
  local job_name="$1" scheduler_name="$2"
  gcloud scheduler jobs run "${scheduler_name}" --location="${REGION}" --project="${PROJECT_ID}" >&2

  local execution=""
  for _ in $(seq 1 30); do
    execution="$(gcloud run jobs executions list \
      --job="${job_name}" --region="${REGION}" --project="${PROJECT_ID}" \
      --sort-by="~metadata.creationTimestamp" --limit=1 \
      --format="value(metadata.name)" 2>/dev/null || true)"
    [ -n "${execution}" ] && break
    sleep 2
  done
  if [ -z "${execution}" ]; then
    echo "No execution appeared after 60s for ${job_name}." >&2
    return 1
  fi

  for _ in $(seq 1 60); do
    local status
    status="$(gcloud run jobs executions describe "${execution}" \
      --region="${REGION}" --project="${PROJECT_ID}" \
      --format="value(status.conditions[0].type,status.conditions[0].status)")"
    echo "  poll: ${status}" >&2
    echo "${status}" | grep -q "Completed.*True\|Failed.*True" && break
    sleep 5
  done
  echo "${execution}"
}
