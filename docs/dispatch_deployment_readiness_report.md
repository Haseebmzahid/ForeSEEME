ForeSeeMe dispatch deployment blocker fix — October 12, 2026


> **Historical phase report � superseded findings (October 12, 2026).**
> The validation and preservation figures below describe that earlier phase only.
> Later dispatch-controller work retired unsafe `common.sh` provisioning and
> fixed dispatch ordering/exact-execution verification. The final local gate
> subsequently passed 532 unique tests, including API (18) and prediction (5),
> with guarded functioning Windows IPC. The earlier ASGI exclusions remain
> accurate historical limitations, not current unresolved test failures.
> The subsequent release-review corrections added compute-risk prerequisite
> checks/noninteractive transport, original-plus-cleanup failure reporting and
> mandatory digest-pinned images for both controllers. See the current
> [deployment workflow](../backend/deploy/README.md) for implementation details.
> Cloud responses, IAM/attached identity, actual image execution, source availability
> and FCM/device delivery remain unvalidated. Docker's Linux daemon was unavailable
> at the final local gate. The ignored local config was not modified and still
> requires operator review. No cloud readiness or deployment is claimed.
> This correction phase ran only the focused readiness suites under Python 3.12.2:
> 93 compute + 93 dispatch = 186 unique passes, no failures/skips on the final run.
> The first run had one new deadline regression fail; deadline calculation was
> moved outside the CLI error wrapper, preserving TimeoutError before subprocess
> invocation. Both transports now have regression coverage. Python syntax, six
> shell/config parse checks and git diff --check passed. No full-suite rerun or
> cloud/container operation was performed in this correction phase.


The legacy dispatch deployment blocker is fixed in code and tested offline. Actual cloud deployment, attached identity, image execution and FCM delivery remain unvalidated.

Confirmed defects and fixes:

- Legacy provision_dispatch_alerts.sh enabled APIs, created infrastructure/accounts, built/pushed images and granted IAM implicitly. Both dispatch entrypoints now delegate to dispatch_alerts_control.py. Preflight only reads prerequisite state; the transport rejects API enabling, builds, IAM changes, account/repository creation and scheduler-run commands. SDK API-enable prompts are explicitly disabled, stdin is closed and CLI calls are bounded. common.sh is retired and fails closed; no supported entrypoint sources it.
- Schedules were active before the initial verification. The new order is preflight → confirmed schedule pause → job create/update → runtime read-back → exact initial execution and persisted heartbeat verification → scheduler create/update/resume with ENABLED confirmation. The standalone verify command never activates a schedule.
- trigger_and_wait selected a latest execution, accepted failed conditions and returned after polling exhaustion. Verification now uses only the execution returned by the current direct invocation; validates its identity/creation time; polls Completed by condition type; rejects failed, cancelled, unsuccessful and timed-out executions. CLI calls, log polling and heartbeat reads share the configured verification deadline. No old execution list is used.
- Logs were not execution-scoped, heartbeat checking was manual, and a second sending run was used to suggest idempotency proof. Verification now performs one execution, scopes job_run logs to project/region/job/execution, rejects missing/ambiguous/stale/degraded signals, and requires the persisted heartbeat to match exact timestamps, counts, total and ok status. Zero sends remains valid. Existing offline engine/pipeline tests retain idempotency coverage; this script does not claim device delivery or production idempotency proof.
- Failures could leave recurring work enabled with no clear cleanup outcome. Failures after preflight attempt a compensating scheduler pause using a fresh cleanup budget, including after ambiguous create/resume timeouts. A cleanup failure explicitly reports both failure types, unknown schedule state and required operator action; original failure context is retained without echoing raw CLI output or tokens.
- Dispatch initialization required a service-account JSON key for real Firestore and bypassed the guarded factory. It now uses firestore_runtime.get_firestore_client(): attached/local ADC and anonymous emulator credentials are supported, with existing project/endpoint/credential provenance protections intact. Deployment explicitly sets FIREBASE_PROJECT_ID and FIRESTORE_AUTH_MODE=attached, rejects key/emulator overrides and reads those settings back.

Dispatch targeting, throttling, claiming/idempotency, token pruning, FCM behavior, runtime outcome/exit policy, audit/inbox/heartbeat shapes and Flutter contracts are unchanged. A degraded runtime may still exit zero per its existing contract, but deployment verification rejects it. Compute-risk controller, freshness policy and all prior runtime fixes are unchanged.

Files changed this phase:

| File | Reason |
|---|---|
| backend/deploy/dispatch_alerts_control.py | Read-only preflight, restricted CLI transport, safe ordering, exact execution proof and compensating cleanup |
| backend/deploy/provision_dispatch_alerts.sh | Delegate to controller; remove implicit infrastructure provisioning |
| backend/deploy/verify_dispatch_alerts.sh | Delegate to bounded exact-execution verification; leave schedules paused |
| backend/deploy/common.sh | Retire unsafe unused helpers and fail closed for old callers |
| backend/app/jobs/dispatch_alerts.py | Replace credential initialization only with guarded ADC factory |
| backend/deploy/README.md | Replace the legacy-dispatch blocker note with the actual workflow, prerequisites, failure modes and limits |
| backend/tests/test_dispatch_deployment.py | 87 focused offline regressions |
| docs/dispatch_deployment_readiness_report.md | This completion report |

Validation:

- Interpreter: C:\Users\HP\.venvs\foreseeme-py312\Scripts\python.exe, established Python 3.12.2 environment. Used -B and pytest -p no:cacheprovider; no dependencies installed/upgraded.
- In-process guards blocked socket connects, requests HTTP, httpx external transport, google.auth credential discovery, real Firestore client construction and subprocess.run. Tests deliberately replaced individual seams with mocks/fakes. Windows local platform metadata was initialized before blocking subprocesses, as established in the prior phase.
- Final focused run: test_dispatch_deployment.py (87) + test_deployment_readiness.py (53): **140 passed, zero failures**. Earlier incremental focused runs passed 113, 123 and 134 tests, also zero failures.
- Relevant broader run: backend/tests with test_api.py and test_predict.py excluded for the established Windows local ASGI/IPC limitation: **313 passed, zero failures**. Scratch files used a fresh --basetemp under the writable visualization root to preserve atomic file writes. No ASGI pass is claimed.
- Direct-file CLI usage guard: invoking the controller without arguments returned the expected failure before instantiating the controller or contacting cloud services. Bash entrypoints were inspected; no provision/verify cloud mode was executed.
- git diff --check passed (existing LF/CRLF notices only). Tracked changes and new code/tests were reviewed; new Python source syntax and whitespace were also checked without generating bytecode. No Docker build or runtime validation performed.

Per-file broader test counts (all zero failures):

| Test file | Passed |
|---|---:|
| backend/tests/test_compute_risk.py | 22 |
| backend/tests/test_compute_risk_acquisition.py | 8 |
| backend/tests/test_compute_risk_freshness.py | 23 |
| backend/tests/test_compute_risk_initialization.py | 13 |
| backend/tests/test_deployment_readiness.py | 53 |
| backend/tests/test_dispatch_alerts.py | 15 |
| backend/tests/test_dispatch_deployment.py | 87 |
| backend/tests/test_e2e_dispatch.py | 4 |
| backend/tests/test_e2e_pipeline.py | 5 |
| backend/tests/test_explain.py | 10 |
| backend/tests/test_firestore_runtime.py | 12 |
| backend/tests/test_messaging.py | 7 |
| backend/tests/test_observability.py | 13 |
| backend/tests/test_recommendation_lookup.py | 3 |
| backend/tests/test_schemas.py | 11 |
| backend/tests/test_targeting.py | 12 |
| backend/tests/test_throttle.py | 7 |
| backend/tests/test_weekly_report.py | 8 |

Remaining cloud/runtime blockers:

- Cloud preflight itself was exercised only through fakes. Actual API/billing/project state, service-agent setup, image existence/content, identities and IAM permissions remain unvalidated. Read-only preflight is designed to reject missing prerequisites before mutation, not supply them.
- Preflight requires an ACTIVE project, matching project ID/number, enabled billing, required APIs, existing enabled accounts and image, the Scheduler service-agent binding, explicit unconditional datastore/FCM roles for SA_JOBS, scheduler invoker access and operator Firestore read access. It intentionally rejects custom/inherited/conditional role equivalents instead of guessing effective authorization.
- The CLI operator also requires actual job/scheduler write and service-account actAs rights. Read-back of standard IAM bindings is not a complete effective-permission evaluator for that operator. These rights and actual operations must be confirmed in an authorized release environment; deployment failure leaves/attempts to leave the scheduler paused.
- The ignored backend/deploy/config.env is byte-for-byte unchanged and lacks the prior phase's required auth/verification settings. An operator must review/export the intended configuration before an authorized release attempt. No automatic configuration overwrite occurred.
- A timeout does not cancel the running task. Concurrent/manual runs can overwrite the singleton heartbeat and cause fail-closed verification. A cloud outage can prevent compensating cleanup; the controller reports unknown schedule state rather than claiming cleanup succeeded.
- **Historical phase status; ASGI portion superseded by the final local gate:** Attached ADC, real Firestore/FCM behavior, device delivery, the actual image, SDK/cloud response compatibility and ASGI tests remain unvalidated. No schema migration or production runtime test was required or performed.

Git preservation:

Before: main, 12 modified / 9 untracked files. After: main, 16 modified / 12 untracked files (including this report). No staged changes, resets/reverts, removed prior files, branches, commits or pushes. Every initial path remains present with its original status. SHA-256 comparison confirms every initially modified/untracked file is byte-for-byte unchanged except backend/deploy/README.md, whose compute-risk content is preserved and legacy dispatch note is intentionally updated. The ignored config.env hash is unchanged.

| Path | Before | After |
|---|---|---|
| backend/.env.example | M | M |
| backend/Dockerfile | M | M |
| backend/app/jobs/compute_risk.py | M | M |
| backend/app/jobs/dispatch_alerts.py | clean/absent | M |
| backend/app/jobs/firestore_runtime.py | ?? | ?? |
| backend/app/jobs/observability.py | M | M |
| backend/deploy/README.md | M | M |
| backend/deploy/common.sh | clean/absent | M |
| backend/deploy/compute_risk_control.py | ?? | ?? |
| backend/deploy/config.env.example | M | M |
| backend/deploy/dispatch_alerts_control.py | clean/absent | ?? |
| backend/deploy/provision_compute_risk.sh | M | M |
| backend/deploy/provision_dispatch_alerts.sh | clean/absent | M |
| backend/deploy/verify_compute_risk.sh | M | M |
| backend/deploy/verify_dispatch_alerts.sh | clean/absent | M |
| backend/ml/pipelines/acquisition_base.py | M | M |
| backend/ml/pipelines/acquisition_common.py | M | M |
| backend/ml/tests/test_acquisition_common.py | M | M |
| backend/tests/test_compute_risk_acquisition.py | ?? | ?? |
| backend/tests/test_compute_risk_freshness.py | ?? | ?? |
| backend/tests/test_compute_risk_initialization.py | ?? | ?? |
| backend/tests/test_deployment_readiness.py | ?? | ?? |
| backend/tests/test_dispatch_deployment.py | clean/absent | ?? |
| backend/tests/test_firestore_runtime.py | ?? | ?? |
| docs/deployment.md | M | M |
| docs/deployment_readiness_report.md | ?? | ?? |
| docs/dispatch_deployment_readiness_report.md | clean/absent | ?? |
| docs/risk_input_freshness.md | ?? | ?? |
