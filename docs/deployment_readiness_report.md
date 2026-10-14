ForeSeeMe deployment readiness fix report â€” October 12, 2026


> **Historical phase report — superseded findings (October 12, 2026).**
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


Ready for a deployment-readiness review of compute-risk. This is not a cloud-validated release candidate. A local emulator/runtime test should run in an environment with working local IPC and isolated credentials/cache; no real job was executed in this session.

Confirmed defects and implemented fixes:

- Scheduler activation preceded initial verification. The compute-risk controller now preflights, confirms any existing schedule is paused, deploys the job, verifies its exact initial execution and persisted results, then schedules. A verification failure cannot create/activate a schedule. Scheduler mutation failures attempt a compensating pause.
- Verification selected the newest listed execution, accepted unsuccessful states, and returned after timeout. It now captures the execution from the current direct invocation, checks its identity/creation time, locates Completed by condition type, rejects failed/cancelled/unsuccessful states, and shares a bounded deadline across polling, CLI and Firestore reads. No old execution list is used.
- Deployment omitted project and freshness settings. It now explicitly passes and reads back FIREBASE_PROJECT_ID, FIRESTORE_AUTH_MODE=attached, the 12-week lookback, five-day data delay and zero additional trailing-gap tolerances. Preflight rejects conflicting projects, credential/emulator overrides, invalid values, hidden INFO evidence, and an unsupported schedule/time zone. The attached identity requires no JSON key.
- Heartbeat errors were swallowed while the caller could report ok. A heartbeat error now changes the report to failed, emits an alert with the exception type, and makes compute-risk exit nonzero. Shared emit callers also receive the failed report. Degraded partial output retains its documented zero exit status but is explicitly reported as degraded with counts and alert=true.
- Post-run verification was a manual checklist and could read another run's signal. It now asserts execution/region-scoped logs, the configured city set, consistent counts/status, at least one fresh write by default, exact persisted heartbeat timestamps and exact generatedAt for every written risk document. A partial result is permitted and reported, never labeled ok. Missing, stale, insufficient or concurrent overwritten evidence fails closed.
- Instructions incorrectly implied key-file authentication and infrastructure setup by compute-risk provisioning. Updated instructions require pre-existing APIs, reviewed image, accounts and IAM; this path no longer enables APIs, builds/pushes images or grants permissions.

Firestore document shapes, Flutter-facing fields, source validity/freshness policy, model/feature path, cache ownership and the existing user's fixes are preserved. New run_evidence fields exist only in logs.

Files changed in this phase:

| File | Purpose |
|---|---|
| backend/app/jobs/compute_risk.py | Exact run timestamps/evidence and explicit data-delay environment setting |
| backend/app/jobs/observability.py | Caller-visible heartbeat failure and safe fallback diagnostic signal |
| backend/app/jobs/firestore_runtime.py | Explicit attached/ADC/emulator mode validation; extends existing untracked factory |
| backend/deploy/compute_risk_control.py | Offline-testable preflight, deployment ordering, execution verification and read-only assertions |
| backend/deploy/provision_compute_risk.sh | Delegate to safe controller; removes API/IAM/image-build side effects |
| backend/deploy/verify_compute_risk.sh | Delegate to exact execution verification; leaves schedules paused |
| backend/deploy/config.env.example | Required auth/freshness/verification settings and exported environment instructions |
| backend/.env.example | Accurate ADC/emulator/attached identity and freshness instructions |
| backend/deploy/README.md | Current workflow, prerequisites, partial outcomes and failure/timeout behavior |
| docs/deployment.md | Pointer to authoritative backend workflow |
| backend/tests/test_deployment_readiness.py | 53 focused offline regressions |
| docs/deployment_readiness_report.md | This validation/status report |

Validation:

- Verified interpreter: C:\Users\HP\.venvs\foreseeme-py312\Scripts\python.exe, Python 3.12.2. Used -B and pytest -p no:cacheprovider throughout.
- In-process guards blocked socket connects, requests HTTP, httpx external transport, google.auth credential discovery, real Firestore client construction, and subprocess.run. Tests explicitly replace seams with mocks/fakes. Local Windows platform metadata was initialized before the subprocess guard; no cloud command ran.
- Final feasible broader run: backend/tests and backend/ml/tests, excluding test_api.py and test_predict.py, with a fresh --basetemp under the writable visualization root: **419 passed, zero failures** (226 backend + 193 ML).
- Final focused rerun after the execution-region assertion: **53 passed, zero failures**. An intermediate guarded focused run covering readiness, observability, initialization and runtime reuse passed all 75 tests.
- Earlier focused attempt: 74 passed, one failure in a new fake-clock fixture; fixed and rerun. An overly broad initial subprocess guard produced four collection errors in Windows platform detection; corrected by initializing that local metadata first.
- Initial broad attempt: 376 passed, 58 failed because the socket guard blocked Windows ASGI socketpairs and the sandbox's default temporary directory rejected atomic file replacement. A subsequent full rerun was stopped when the sandbox also stalled actual local socketpair creation. No test or application safety assertion was weakened. Relocating scratch files resolved the file errors; ASGI files remain unvalidated here.
- Diagnostic reproductions: one ASGI health test failed on the socket guard and one quality-report atomic-write test failed in the default sandbox temporary directory, matching the broad-run failures above.
- git diff --check passed. Full tracked diff and new source/test files reviewed. No Docker build/test performed; daemon availability remains unvalidated. No dependency installation/upgrade.

Per-file counts for the final feasible broader run (all zero failures):

| Test file | Passed |
|---|---:|
| backend/ml/tests/test_acquire_aqi.py | 6 |
| backend/ml/tests/test_acquire_weather.py | 5 |
| backend/ml/tests/test_acquisition_base.py | 12 |
| backend/ml/tests/test_acquisition_common.py | 15 |
| backend/ml/tests/test_artifact.py | 15 |
| backend/ml/tests/test_clean.py | 12 |
| backend/ml/tests/test_discover_sources.py | 8 |
| backend/ml/tests/test_disease_reference_guard.py | 7 |
| backend/ml/tests/test_evaluate.py | 11 |
| backend/ml/tests/test_features.py | 8 |
| backend/ml/tests/test_labels.py | 8 |
| backend/ml/tests/test_lineage.py | 9 |
| backend/ml/tests/test_merge.py | 6 |
| backend/ml/tests/test_paths.py | 12 |
| backend/ml/tests/test_preprocessing_stages.py | 15 |
| backend/ml/tests/test_quality_report.py | 22 |
| backend/ml/tests/test_train.py | 12 |
| backend/ml/tests/test_validate.py | 10 |
| backend/tests/test_compute_risk.py | 22 |
| backend/tests/test_compute_risk_acquisition.py | 8 |
| backend/tests/test_compute_risk_freshness.py | 23 |
| backend/tests/test_compute_risk_initialization.py | 13 |
| backend/tests/test_deployment_readiness.py | 53 |
| backend/tests/test_dispatch_alerts.py | 15 |
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

Remaining blockers and assumptions:

- Cloud resources, billing/API state, IAM, operator ADC permissions, attached runtime identity, the actual container image, source availability and real read-back are unvalidated. gcloud and Docker executables exist, but neither authentication nor daemon readiness was inferred from that.
- The ignored local backend/deploy/config.env was deliberately left untouched. It lacks the new required settings and will fail clearly until an operator updates/exports it from the example.
- **Superseded by the final local gate; historical phase limitation:** The ASGI test files test_api.py and test_predict.py need a machine with working local Windows IPC. The supplied 129-pass baseline was treated as existing evidence; this session does not claim a clean rerun of the full baseline including those files.
- **Superseded by the dispatch-controller fix; historical blocker:** Legacy dispatch-alert provisioning/shared common.sh still contain API/IAM/build side effects, scheduler-first ordering and latest-execution verification. They are outside the new compute-risk controller and remain a blocker to claiming deployment readiness for the entire backend. Do not infer readiness for them from compute-risk results.
- A verification timeout leaves the task potentially running and does not cancel it. Existing schedules remain paused; concurrent/manual runs can overwrite the single heartbeat and cause verification to fail closed. A cloud outage during compensating pause can prevent cleanup and requires operator intervention.
- The documented compute-risk deployment path now supports numeric cron and UTC, one task, zero retries, and INFO/DEBUG logging. Minimum accepted writes default to one, preserving the allowed partial-result contract; a release reviewer can require more without weakening source validation.

Git preservation:

Initial branch main: six modified and six untracked files. Final branch main: twelve modified and nine untracked files (including this report). No staged changes, removed files, branches, commits, tags, resets, reverts or pushes. Every initial path remains present with its original status. The existing Dockerfile/acquisition changes and original untracked tests/freshness documentation were not edited; runtime files were extended in place.

| Path | Before | After |
|---|---|---|
| backend/.env.example | clean/absent | M |
| backend/Dockerfile | M | M |
| backend/app/jobs/compute_risk.py | M | M |
| backend/app/jobs/observability.py | M | M |
| backend/deploy/README.md | clean/absent | M |
| backend/deploy/config.env.example | clean/absent | M |
| backend/deploy/provision_compute_risk.sh | clean/absent | M |
| backend/deploy/verify_compute_risk.sh | clean/absent | M |
| backend/ml/pipelines/acquisition_base.py | M | M |
| backend/ml/pipelines/acquisition_common.py | M | M |
| backend/ml/tests/test_acquisition_common.py | M | M |
| docs/deployment.md | clean/absent | M |
| backend/app/jobs/firestore_runtime.py | ?? | ?? |
| backend/deploy/compute_risk_control.py | clean/absent | ?? |
| backend/tests/test_compute_risk_acquisition.py | ?? | ?? |
| backend/tests/test_compute_risk_freshness.py | ?? | ?? |
| backend/tests/test_compute_risk_initialization.py | ?? | ?? |
| backend/tests/test_deployment_readiness.py | clean/absent | ?? |
| backend/tests/test_firestore_runtime.py | ?? | ?? |
| docs/deployment_readiness_report.md | clean/absent | ?? |
| docs/risk_input_freshness.md | ?? | ?? |

Command semantics were checked against the installed Google SDK source and [the official execute reference](https://docs.cloud.google.com/sdk/gcloud/reference/run/jobs/execute). No cloud response was fetched to validate this implementation.
