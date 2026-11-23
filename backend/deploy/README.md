## Compute-risk release-candidate workflow (authoritative)

### Scheduler-free one-time deployment

In an explicitly authorized release session, export the reviewed non-secret
compute settings from `config.env.example` (and the actual reviewed digest-pinned
`IMAGE`). Do not overwrite the ignored local config. Then use the public mode:

```powershell
Set-Location 'D:\FYP ForeSeeMe\fyp_foreseeme\backend'
python -B deploy/compute_risk_control.py one-time
```

Equivalent Bash entrypoint, with the same exported settings:

```bash
cd backend
bash deploy/provision_compute_risk.sh --one-time
```

This mode runs the mandatory read-only preflight, creates/updates the job, submits
one execution, and verifies that exact execution and persisted Firestore evidence.
It never reads or modifies Scheduler resources, including on failure. Scheduler
API, account, service-agent/invoker bindings and all four scheduler config values
(`SA_SCHEDULER`, `COMPUTE_RISK_SCHEDULER_NAME`, `COMPUTE_RISK_SCHEDULE`,
`COMPUTE_RISK_TIME_ZONE`) are not required. The CLI transport also rejects any
Scheduler command in this mode. No prerequisite infrastructure is provisioned.

Required APIs: `run.googleapis.com`, `artifactregistry.googleapis.com`,
`firestore.googleapis.com`, `iam.googleapis.com`,
`cloudresourcemanager.googleapis.com`, `serviceusage.googleapis.com`,
`logging.googleapis.com`, `cloudbilling.googleapis.com`. Billing must already
be enabled; project/CLI identity, operator ADC, digest/image availability,
enabled jobs service account, unconditional jobs-SA `roles/datastore.user`, and
operator heartbeat/risk-query read access are checked before job mutation.
Effective operator job create/update/execute, image-read and service-account
actAs permissions still require authorized cloud validation, as in recurring mode.
Specifically, the release operator needs `run.jobs.create`/`run.jobs.update`,
`run.jobs.run`, job/execution read permissions and `iam.serviceAccounts.actAs`
on the attached identity, plus registry/log read access. Operator ADC separately
needs Firestore entity get/list access. Configuration and project IAM role
read-back do not prove these effective permissions, inherited policies,
conditions, deny policies or actual image pull/runtime behavior. Offline tests
do not establish live authorization.

The shared heartbeat factory also requires the legacy dispatch initializer to
use the same guarded client; this release includes only that runtime
compatibility change, not the separate dispatch deployment-controller workflow.

All other compute config remains required, with example resources/freshness:
`PROJECT_ID=foreseeme-83587`, `REGION=us-central1`,
`SA_JOBS=risk-jobs-sa@foreseeme-83587.iam.gserviceaccount.com`,
`COMPUTE_RISK_JOB_NAME=compute-risk-job`, timeout `600s`, memory `512Mi`, CPU `1`,
`LOG_LEVEL=INFO`, `FIRESTORE_AUTH_MODE=attached`, lookback `12`, data delay `5`,
both source trailing gaps `0`, verification timeout/max age `900` seconds.
Set `VERIFY_MIN_WRITTEN=5` for clarity. Even if the shared default is `1`,
one-time acceptance requires every configured city and at least five fresh
documents; partial output fails without printing successful verification.

The exact-execution polling, runtime read-back, timestamp/count checks and
bounded verification deadline are shared with recurring deployment. Failures
are not retried and never trigger scheduler cleanup. A timeout/uncertain execute
response does not cancel a task and is not permission to submit a second one.
Existing triggers are untouched and uninspected: this mode guarantees one
submission by this invocation, not absence of unrelated concurrent executions.
The operator must independently establish an appropriate evaluation window.
Do not bypass preflight by invoking internal deploy/verify methods directly.
Do not run the separate verify wrapper after successful one-time deployment:
it would submit another execution and uses recurring-mode scheduler prerequisites.

### Existing recurring deployment and verify-only workflow

The remaining compute instructions below describe the unchanged recurring path.
Without `--one-time`, provision enables recurrence after successful verification.

The compute-risk scripts now use `compute_risk_control.py`. They require Python
with the existing backend requirements, gcloud CLI login, **operator ADC** for
read-only Firestore verification, and a matching active gcloud project. The
runtime uses its attached `SA_JOBS` identity, not a JSON key. Verification reads
service-only documents, so the operator needs read access. Token output is
captured and never printed.

APIs, billing, Artifact Registry image, service accounts, Firestore access for
`SA_JOBS`, and Cloud Run invoker access for `SA_SCHEDULER` must already exist and
be reviewed separately. Compute-risk provisioning no longer enables APIs,
builds/pushes images, creates service accounts, or grants IAM. No script in this
workflow has been executed against cloud resources during the readiness fix.

Both controllers require an explicit, reviewed **digest-pinned** `IMAGE` in the
configured Artifact Registry project/region. Tags (including `latest` or a commit
SHA tag) are mutable and rejected. The example intentionally leaves `IMAGE=`
empty, so copying it without operator review fails preflight. Supply the full
reference of an already existing image, for example
`us-central1-docker.pkg.dev/foreseeme-83587/backend/foreseeme-backend@sha256:<64-lowercase-hex-digest>`.
Replace the placeholder with the reviewed image digest obtained from existing
release evidence or an authorized read-only registry inspection. These scripts
never build, push, resolve a moving tag, or modify the ignored local config.
In an authorized release session an operator must review/update/export local
settings; old configuration fails preflight. Export settings (plain `source`
does not export them to Python):

```bash
cd backend
set -a
source deploy/config.env
set +a
# Explicit cloud operations; execute only in an authorized release session:
bash deploy/provision_compute_risk.sh
# A separate verification pauses any existing recurring schedule and leaves it paused:
bash deploy/verify_compute_risk.sh
```

Compute-risk read-only preflight validates configuration (including freshness,
command policy, resources and digest), matching active CLI/project identity,
ACTIVE project ID/number, enabled billing, and already enabled Run, Scheduler,
Artifact Registry, Firestore, IAM, Resource Manager, Service Usage, Logging and
Cloud Billing APIs. It confirms the pinned image exists and both service accounts
are enabled and match their configured identities. Required unconditional roles
are `roles/datastore.user` for `SA_JOBS`, `roles/run.invoker` for `SA_SCHEDULER`
at project or existing-job scope, and `roles/cloudscheduler.serviceAgent` for the
project-number Scheduler service agent. First job creation requires a project
invoker binding. Custom/inherited/conditional equivalents fail conservatively.
Operator ADC must read the heartbeat and a limited risk collection query; an
absent first-run heartbeat is allowed. No FCM API/role is required for compute-risk.
The CLI operator's effective job/scheduler write and service-account actAs rights
still require authorized cloud validation; role read-back is not a complete
effective-permission evaluator. Desired runtime configuration is validated before
mutation; deployed runtime configuration is read back after job update and before
execution. All CLI calls use closed stdin, `--quiet`, API-enable prompt suppression
and bounded timeouts. The transport rejects prerequisite provisioning and direct
scheduler-run commands. Provision checks these prerequisites before mutation.
It pauses an existing named schedule, creates/updates the job with one
task and no retries, checks the deployed command (`python -m
app.jobs.compute_risk`), image, identity and environment, and executes the job
directly. It captures the execution returned by that invocation, never a latest
execution list. It polls `Completed` by type and rejects unsuccessful/cancelled
states, failed tasks, absent proof and timeout. CLI calls, log polling and
Firestore reads share a bounded verification deadline. Timeout does not cancel
the running task; the recurring schedule remains paused/absent.

Only after successful execution AND post-run assertions does provision
create/update and enable the named scheduler. Failures leave the existing
schedule paused or the new one absent; scheduler creation/activation failures
attempt a compensating pause with a fresh timeout budget. All failures after
preflight also attempt pause, including uncertain pause/update responses. If
cleanup fails, the original exception remains the cause, both exception types
are reported without raw error text, and the named schedule state is explicitly
unknown: an operator must inspect and pause it before retrying. A cloud outage can
prevent cleanup; successful cleanup is never assumed. The separate verify
command never enables a schedule. It intentionally requires the same full configuration.

Required runtime settings: `FIREBASE_PROJECT_ID` is explicitly set from
`PROJECT_ID`; `FIRESTORE_AUTH_MODE=attached`; `RISK_LOOKBACK_WEEKS=12`;
`RISK_DATA_DELAY_DAYS=5`; both `RISK_*_MAX_TRAILING_GAP_DAYS=0`. These retain the
current five-day source lag and real, valid observation freshness requirements.
The schedule accepts numeric cron fields and UTC only; LOG_LEVEL must retain
INFO evidence (INFO or DEBUG). All runtime settings are validated and read back
before execution. No schema or Flutter
contract changed. Writable ML cache and manifest ownership remain as implemented
in the existing Dockerfile/acquisition changes.

Verification requires execution-scoped `run_evidence` logs, exactly the configured
city set from `cities.yaml`, consistent per-status counts, at least
`VERIFY_MIN_WRITTEN` fresh documents (default 1), and a persisted heartbeat whose
start/finish timestamps and counts exactly match that run. Every written risk
document must have the exact run `generatedAt`. The source freshness gate runs
before inference; a regenerated timestamp alone does not bypass it. Log delivery
is retried until `VERIFY_TIMEOUT_SECONDS` (900 by default); evidence older than
`VERIFY_MAX_AGE_SECONDS` (900) is rejected. A later/concurrent heartbeat overwrite
fails closed; verify again while schedules are paused.

All cities written means `ok`. Partial output remains an allowed **degraded**
result, printed with actual counts; it is never described as full success. Zero
output fails. A heartbeat write failure changes the caller's report to `failed`,
emits an alert with the exception type (no raw secret-bearing error text), and
the scheduled entrypoint exits nonzero. Partial runs exit zero per the existing
contract, while their structured logs/heartbeat retain `degraded` and alert=true.
Changing `VERIFY_MIN_WRITTEN` strengthens only deployment acceptance, not runtime
freshness. It must be between 1 and the configured city count.

## Dispatch-alert release workflow

`provision_dispatch_alerts.sh` and `verify_dispatch_alerts.sh` now use
`dispatch_alerts_control.py`. The former enables recurring dispatch only after
one verified initial execution; the latter performs one execution with the
schedule paused and leaves it paused. Verification no longer triggers a second
potentially sending run to claim idempotency; the existing offline dispatch and
pipeline tests cover that property. A zero-send run is healthy and does not prove
FCM device delivery. Any degraded/failed run blocks deployment acceptance while
the runtime's existing dispatch semantics and exit policy remain unchanged.

Export the shared config using `set -a; source deploy/config.env; set +a`, then
use the dispatch entrypoints in an explicitly authorized cloud release session.
Do not run them as an offline readiness test: they execute the real dispatch job,
which can send FCM messages and write the audit/inbox/heartbeat collections.
All `DISPATCH_ALERTS_*` values, `PROJECT_ID`, `REGION`, `IMAGE`, `SA_JOBS`,
`SA_SCHEDULER`, `FIRESTORE_AUTH_MODE=attached`, `LOG_LEVEL=INFO` (or DEBUG),
`VERIFY_TIMEOUT_SECONDS` and `VERIFY_MAX_AGE_SECONDS` are required. The shared
900-second verification timeout must exceed the 300-second task timeout.
Numeric five-field cron and UTC are supported. The ignored local `config.env`
is not updated automatically and must include/export the required settings.

Before any deployment/scheduler mutation, read-only preflight checks require:

- Matching active gcloud project, a CLI identity and usable operator ADC.
- Already enabled Run, Scheduler, Artifact Registry, Firestore, FCM, IAM,
  Resource Manager, Service Usage, Logging and Cloud Billing APIs.
- An ACTIVE project with the expected identifier/number and already enabled
  billing (read-only checks; never linked/enabled by the controller).
- An existing reviewed digest-pinned Artifact Registry image in the configured region/project.
- Existing, enabled `SA_JOBS` and `SA_SCHEDULER` accounts in that project.
- Unconditional project bindings for `SA_JOBS`: `roles/datastore.user` and
  `roles/firebasemessaging.admin`; `SA_SCHEDULER`: `roles/run.invoker` at the
  project or already-existing job. For a first job creation, scheduler invoker
  access must already exist at project scope. Preflight conservatively rejects
  custom/inherited/conditional equivalents; those need a reviewed authorization
  strategy rather than an implicit IAM grant.
- The project-number Scheduler service agent with its existing unconditional
  `roles/cloudscheduler.serviceAgent` binding.
- Operator ADC read access to `jobHeartbeats/dispatch_alerts` (an absent first-run
  document is permitted). The CLI operator also needs job/scheduler write and
  service-account actAs permissions; those actual operations remain unvalidated
  until an authorized cloud session. Preflight requires permission to read
  project/billing/IAM state; it cannot grant missing permissions.

No deploy path enables APIs, grants IAM, creates accounts/repositories, or builds
or pushes images. Both CLI transports allow only the required read/job/scheduler
commands,
disable SDK API-enable prompts, and run noninteractively.
`common.sh` is retired and fails closed for old callers; no
supported entrypoint sources it. Compute-risk shares the prerequisite safety
policy, excluding dispatch-only FCM requirements; its freshness policy is
unchanged. Legacy `read_heartbeat.py` / `read_dispatch_audit.py` remain
operator helpers, not exact-execution proof.

Dispatch uses the guarded Firestore factory with attached ADC in Cloud Run,
explicit `FIREBASE_PROJECT_ID`, and no key/emulator override. The verifier uses
operator ADC in its fresh CLI process. Deployment reads back the command
`python -m app.jobs.dispatch_alerts`, image, service account, project/auth/log
settings, single-task configuration and zero retries before executing.

An existing schedule is paused and its state confirmed before deployment or
execution. The execution returned by the current direct `gcloud run jobs execute`
invocation is polled by exact name and creation timestamp under a shared bounded
deadline. Failed/cancelled/unsuccessful terminals, timeout, missing/ambiguous
execution-scoped `job_run` logs and degraded/failed signals are rejected. Logs
are scoped to project, region, job and execution. The persisted heartbeat must
match that run's start/finish times, counts, total and successful status; stale
or overwritten heartbeats fail closed. Zero sends is permitted. No new document
field, target predicate, throttle, idempotency key or FCM behavior was introduced.

Failures after preflight attempt a compensating scheduler pause, including after
a timed-out create/resume response. Cleanup has a fresh timeout budget. If it
also fails, the error names both failure types and explicitly reports unknown
schedule state requiring operator action. A network outage can prevent cleanup;
a verification timeout does not cancel the running task. Device delivery, actual
cloud response/IAM behavior, the image and end-to-end runtime remain unvalidated
by offline tests.

## Module 8 deployment

See [Module 8 deployment and recovery](../../docs/MODULE_8_FINALIZATION.md#deployment-and-recovery) for the dedicated HTTPS admin API, MFA cutover, rules and indexes, aggregation, model evidence and directory backfill.
