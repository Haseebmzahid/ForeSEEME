# Module 8 engineering report

## Baseline and incident analysis

Discovery started on `main` at `188ff15`, tracking `origin/main`, with no uncommitted changes. Commits `44c4d1b`, `3023691`, `ba81325` and `a3cc795` already implemented the dashboard and admin shell, activity log, Resource Center CMS and user directory. The earlier Module 8 audit predates those commits. The checked-in SDS §4.8 defines FR8.1–FR8.5 and its security section defines NFR-S3. The repository did not contain a standalone SRS. No screenshots, device traces or affected account identifiers accompanied the request.

The app and local Cloud CLI project selector both pointed to `foreseeme-83587`. The deployment runbook and control scripts use digest-pinned Cloud Run Jobs and Cloud Scheduler for risk compute and dispatch. Weekly report has a runnable entry point. Its schedule was absent from the repository provisioning configuration. A later authorized read-only request used the configured Google identity. The deployed Firestore rules matched neither the starting repository rules nor this working copy. They had no references to the log, directory, heartbeats or operational metrics. Read-only checks confirmed gaps in user-directory coverage and scheduled-job telemetry. Administrator MFA configuration and recovery must be validated during the coordinated rollout. The operator identity received HTTP 403 from Cloud Run and Scheduler, so those resource states could not be established.

| Reported screen | Confirmed source findings | Runtime interpretation |
|---|---|---|
| Logs | Ordered Firestore query and Riverpod future had no deadline or manual refresh. | Deployed default-deny rules had no activity-log match. The production collection read was therefore denied. A successful permitted empty query should display the empty state. A pending request could leave the spinner open indefinitely. |
| Users | Same deadline gap. Firestore `orderBy('createdAt')` excludes docs without that field. Onboarding can create status-only rows. Older and Google-only accounts were not always projected. | Deployed rules denied the directory read. A read-only Auth comparison also confirmed that existing accounts needed a directory backfill. |
| Jobs and Alerts | The dashboard fetched all heartbeats as one unbounded future and counted the entire dispatch ledger. Missing heartbeats and empty counts were valid responses. | A pending read could stall a card. The deployed rules lack the heartbeat grant present in the starting repository, which confirms deployment drift. A stalled request or UI behavior during the reported session still requires a runtime trace. |

The normal admin reads use explicit deadlines, bounded diagnostics, server snapshots, refresh and recoverable errors. A malformed or unavailable heartbeat leaves other jobs and metrics visible. No aggregate metric displays zero before its first successful publication.

## Architecture and schema

The existing AdminShell, dark theme, navigation, Riverpod and repository boundaries remain in use. Risk override and CMS reuse their public Firestore projections. Neither the ML algorithm nor health, adherence or medication storage was changed.

| Location | Changes |
|---|---|
| `operationalMetrics/{accounts,alerts,deployedModel}` | Server-written aggregate metrics or verified deployment version. MFA-admin reads only. |
| `jobHeartbeats/{job}` | Retains prior successful run time and the successful compute batch model when a later job fails. New errors use a fixed safe code. |
| `userDirectory/{uid}` | Adds service-owned `authDisabled`. Existing owner onboarding writes are constrained to known, typed fields. |
| `adminActivityLog/{eventId}` | Adds event and request IDs, outcome, and Firestore commit timestamp. All client writes are denied. Legacy events remain readable and visibly marked. |
| `adminRateLimits/{actorHash}`, `adminAccountOperations/{uid}` | Service-only rate counters, account operation reservations and deletion markers. The default-deny rule covers both collections. |
| `overrides/{city}`, `articles/{id}` | Client-visible projections. The API is the writer and commits the corresponding success event atomically. |
| `alertDispatchLog/{id}` | Service-only. Aggregate success counts replace client access to individual dispatch records. |
| `users/{uid}/…` | Owner-only, including medication and adherence. Existing rules remain intact. |

The module adds no composite index. Alerts count `status == "sent"` with a single-field index. Existing composite indexes still support risk and dispatch queries. Log ordering uses the existing single-field index on `createdAt`.

The dedicated FastAPI entry point is `app.admin_api:app`. The inference app remains `app.main:app` with its current permissions. The admin app exposes `POST /v1/articles/{id}`, `POST /v1/overrides/{city}`, `POST /v1/overrides/{city}/clear`, `POST /v1/users/{uid}`, and `POST /v1/invitations`. It verifies Firebase bearer tokens with revocation checks, the token claim and current Auth administrator role, an actual MFA session claim and a five-minute authentication window. A transaction limits each verified actor to ten requests per minute. Requests validate targets and typed fields. Web CORS origins are explicit and default to none. Error responses contain safe codes, and ambiguous writes use correlation IDs. A client timeout may leave an operation in progress.

Override form submissions require confirmation and a reason. New overrides expire after 24 hours through the app. The API permits explicit expiries up to seven days. The existing city-level override projection stores the selected disease and takes precedence in the headline with manual attribution. Risk Details retains the original estimate and confidence. One override slot per city is the existing design. Simultaneous independent overrides per disease would require a product and schema decision.

## Deployment and recovery

1. **Prepare a staging release.** Use the same project for Flutter, Firestore and Auth within one environment. Use the generated Flutter Firebase options and set `--dart-define=ADMIN_API_URL=https://<admin-service>`. Build for a FlutterFire MFA-capable Android, iOS or web client and verify that platform in staging. Native Windows Firebase MFA is unsupported. Confirm the application's current Firebase project before diagnosing missing data. After an admin role removal, revoke refresh tokens and verify affected sessions. The operator claim script revokes refresh tokens on role removal. [Flutter MFA platform requirements](https://firebase.google.com/docs/auth/flutter/multi-factor)
2. **Prove administrator recovery before enforcing MFA.** Enable Firebase Authentication with Identity Platform and TOTP in staging. Provision an individual staging Auth account with a verified email and the existing `backend/scripts/set_admin_claim.py` operator workflow. Test email verification, authenticator enrollment from Profile, sign-out and full MFA sign-in on a supported device. Test all admin reads and a write after a new sign-in and verify a password-only token is rejected. Prepare a second, independently enrolled and verified operator. Simulate losing the first factor device in staging and make sure the second can retain access. Account recovery uses an independently authorized Cloud identity to remove a lost enrollment through Identity Platform, revoke sessions and require fresh enrollment. Log that separately as a privileged IAM operation. Do not use a production administrator for this rehearsal. [Firebase TOTP MFA](https://firebase.google.com/docs/auth/web/totp-mfa)
3. **Deploy the separate admin service.** Use a reviewed digest of the backend image and the command `uvicorn app.admin_api:app --host 0.0.0.0 --port <PORT> --proxy-headers`. Configure the proxy trust list for the deployment so ASGI sees verified HTTPS. Keep the container reachable only via the managed ingress. The public Flutter endpoint needs an HTTPS ingress capable of carrying Firebase bearer tokens, edge request throttling and restricted direct access if a load balancer is used. Configure `FIREBASE_PROJECT_ID`, `FIRESTORE_AUTH_MODE=attached` and matching `ADMIN_WEB_ORIGINS` for web. Use a dedicated attached service account with only the Firebase Auth user and Firestore permissions required by the service. Keep Auth mutation permissions away from inference and scheduled job identities. Keep credentials and headers out of access logs. Configure a restricted Firebase project API key in `ADMIN_INVITATION_API_KEY` and enable the Flutter invitation control only after testing the Firebase email template, reset link and delivery in staging. [Cloud Run TLS contract](https://docs.cloud.google.com/run/docs/container-contract)
4. **Validate and coordinate the rules cutover.** Run the emulator suites, check live rule parity with an authorized read-only identity, validate user data boundaries, and run the new binary and API in staging. Deploy reviewed Firestore rules and indexes to the explicitly selected project using `firebase deploy --only firestore:rules,firestore:indexes --project <project>`. Coordinate the release because older clients use now-denied direct admin writes. Keep backend, app, and rules versions aligned during rollback and preserve the audit trust boundary.
5. **Schedule aggregation and directory sync.** Deploy `python -m app.jobs.account_metrics` as an isolated Cloud Run Job using Auth user-list access and Firestore read/write rights, then add a daily Cloud Scheduler trigger with a separate invocation identity. Set `ADMIN_ACTIVITY_WINDOW_DAYS` to 1–365 days as needed. Run the backfill preview and apply sequence from [User management](user_management.md), and run it after account imports or on a separate periodic schedule when needed. Backfill preserves legitimate names and existing onboarding markers. It can recover a missing marker with an existence-only Firestore read using an empty field mask. Review failed and skipped counts before claiming directory coverage.
6. **Verify telemetry.** Use the existing compute and dispatch runbooks in `backend/deploy/README.md`. Configure a weekly Cloud Run Job/scheduler for `python -m app.jobs.weekly_report` only after validating its messaging prerequisites in staging. Register a sent-count/aggregation job execution, the resulting account and alert docs and all three heartbeat docs. After a compute deployment or rollback, run `python -m app.jobs.publish_model_deployment --project <project> --region <region> --job <compute-job> --image <reviewed-image@sha256:digest>` from that exact reviewed image with a publisher identity that can read the Cloud Run job and write deployment evidence. It verifies remote generation, command and image reference before publishing the model artifact's version. Alert on failed/stale jobs, missing aggregation, audit persistence failures and account reservations. A TLS probe, CORS probe and denied non-admin API request should be part of staging verification.
7. **Reconcile an ambiguous account change.** Record the request reference, drain privileged writers and confirm the targeted service revision has finished all in-flight requests. Inspect the reservation and the actual account state using an authorized operator identity. From `backend`, use `python -m scripts.reconcile_admin_account <uid> <request-id> --writers-drained`. It verifies Auth state, completes refresh-token revocation if needed, corrects the directory and appends a reconciliation event. Reopen writers once the expected outcome and audit evidence are confirmed. The script does not repeat deletion or dispatch email. For a reserved invitation it checks the real account state, records a reconciliation event, and releases the reservation or makes the verified account eligible for a new email request. A request for data erasure requires a different, explicitly scoped workflow.

No production deployment, IAM mutation, credential rotation, or production account operation was performed.

## File inventory

<details>
<summary>Added files</summary>

- `backend/app/admin_api.py`
- `backend/app/jobs/account_metrics.py`
- `backend/app/jobs/publish_model_deployment.py`
- `backend/scripts/reconcile_admin_account.py`
- `backend/tests/test_admin_api.py`
- `backend/tests/test_admin_emulator.py`
- `docs/MODULE_8_FINALIZATION.md`
- `lib/features/admin/data/repositories/admin_api_client.dart`
- `lib/features/admin/domain/models/operational_metrics.dart`
- `lib/features/admin/presentation/admin_read.dart`
- `lib/features/admin/presentation/widgets/admin_mfa_enrollment.dart`
- `lib/features/auth/domain/models/second_factor_challenge.dart`
- `lib/features/auth/presentation/widgets/second_factor_dialog.dart`
- `test/features/admin/admin_read_test.dart`
- `test/features/admin/fake_admin_api.dart`

</details>

<details>
<summary>Modified files</summary>

- `analysis_options.yaml`
- `.github/workflows/ci.yml`
- `backend/app/jobs/compute_risk.py`
- `backend/app/jobs/dispatch_alerts.py`
- `backend/app/jobs/observability.py`
- `backend/app/jobs/weekly_report.py`
- `backend/deploy/README.md`
- `backend/scripts/set_admin_claim.py`
- `backend/tests/test_compute_risk_freshness.py`
- `backend/tests/test_observability.py`
- `docs/MODULE_8_AUDIT.md`
- `docs/admin_activity_log.md`
- `docs/admin_override.md`
- `docs/resource_content_management.md`
- `docs/system_monitoring_dashboard.md`
- `docs/user_management.md`
- `firebase.json`
- `firestore.rules`
- `lib/core/routes/app_router.dart`
- `lib/features/admin/data/repositories/firebase_admin_repository.dart`
- `lib/features/admin/data/repositories/firestore_admin_activity_log_repository.dart`
- `lib/features/admin/data/repositories/firestore_system_status_repository.dart`
- `lib/features/admin/domain/models/admin_activity_log_entry.dart`
- `lib/features/admin/domain/models/job_heartbeat.dart`
- `lib/features/admin/domain/repositories/admin_activity_log_repository.dart`
- `lib/features/admin/domain/repositories/system_status_repository.dart`
- `lib/features/admin/presentation/activity_log_providers.dart`
- `lib/features/admin/presentation/admin_activity_log_screen.dart`
- `lib/features/admin/presentation/admin_article_form_screen.dart`
- `lib/features/admin/presentation/admin_content_providers.dart`
- `lib/features/admin/presentation/admin_content_screen.dart`
- `lib/features/admin/presentation/admin_dashboard_screen.dart`
- `lib/features/admin/presentation/admin_override_screen.dart`
- `lib/features/admin/presentation/admin_providers.dart`
- `lib/features/admin/presentation/admin_shell.dart`
- `lib/features/admin/presentation/admin_user_detail_screen.dart`
- `lib/features/admin/presentation/admin_users_providers.dart`
- `lib/features/admin/presentation/admin_users_screen.dart`
- `lib/features/admin/presentation/system_status_providers.dart`
- `lib/features/auth/data/repositories/firebase_auth_repository.dart`
- `lib/features/auth/data/repositories/firestore_user_directory_repository.dart`
- `lib/features/auth/domain/exceptions/auth_exception.dart`
- `lib/features/auth/domain/models/user_directory_entry.dart`
- `lib/features/auth/presentation/auth_notifier.dart`
- `lib/features/auth/presentation/auth_state.dart`
- `lib/features/auth/presentation/login_screen.dart`
- `lib/features/profile/presentation/profile_screen.dart`
- `lib/features/risk/data/repositories/firestore_risk_override_repository.dart`
- `lib/features/risk/presentation/risk_override_provider.dart`
- `lib/main.dart`
- `test/features/admin/admin_activity_log_repository_test.dart`
- `test/features/admin/admin_activity_log_screen_test.dart`
- `test/features/admin/admin_article_form_screen_test.dart`
- `test/features/admin/admin_dashboard_screen_test.dart`
- `test/features/admin/admin_user_detail_screen_test.dart`
- `test/features/admin/admin_users_screen_test.dart`
- `test/features/admin/risk_override_test.dart`
- `test/features/admin/system_status_repository_test.dart`
- `test_rules/firestore_rules.test.mjs`

</details>

## Residual limitations and security assessment

Invitation provisioning uses Firebase password-reset email delivery. The optional control stays hidden until an operator configures the server key and verifies staging delivery. Separate operator access to Firebase and Cloud IAM remains a privileged trust boundary. Firebase Admin SDK identities can bypass Firestore rules. Restrict those identities, enable appropriate Cloud audit logging, and retain audit exports if organizational policy requires stronger preservation.

Production rules and MFA require the documented coordinated release. Directory population, scheduler state and platform sign-in recovery require release verification. Browser origins and ingress are deployment configuration. MFA write authorization uses Firebase claims and recent authentication. Direct Firestore read authorization uses signed token claims and cannot independently perform Admin SDK revocation checks. Existing Auth sessions can retain short-lived access. See [Firebase session behavior](https://firebase.google.com/docs/auth/admin/manage-sessions).

## Verification and traceability

The [Module 9 verification and closure report](MODULE_9_VERIFICATION_AND_CLOSURE_REPORT.md#f-module-8-regression-assurance) adds targeted evidence for the retained admin claim, phone and TOTP factor claims, recent authentication, live role removal, and stale-session denial. All 90 current Firestore demo checks passed during final consolidation, including MFA and stale administrator checks. The two paired demo Auth and Firestore workflows also passed, including phone MFA and retry-safe account invitation. Staging enrollment and recovery and deployed rule parity are still required.

| Requirement | Implementation | Test | Status |
|---|---|---|---|
| FR8.1 | Firebase Auth activity, successful dispatches, model deployment and batch evidence, and job health | `system_status_repository_test.dart`, `admin_dashboard_screen_test.dart`, backend aggregation and demo integration | Implemented and locally verified. Production schedules, snapshots and model-publisher run required. |
| FR8.2 | Confirmed city and disease override with expiry, the original prediction record and a trusted audit event | `risk_override_test.dart`, Auth/Firestore demo workflow and rules suite | Implemented and locally verified. Staging cutover required. |
| FR8.3 | Structured CMS publishes to the live collection and keeps article IDs and source attribution | `admin_article_form_screen_test.dart`, Resource Center suite, demo create/edit and rules suite | Implemented and locally verified. Staging cutover required. |
| FR8.4 | Server-created append-only audit, legacy labeling, filtering, correlation and reconciliation | activity-log widget/repository tests, demo audit outcomes and forgery/immutability rules | Implemented and locally verified. Staging IAM and audit sinks required. |
| FR8.5 | Directory backfill, search and filters, minimal details, real account actions and opt-in password-reset invitations | directory/detail widget tests, demo Auth suspension/sign-in rejection/reactivation/delete/retention/backfill and invitation retry | Implemented and locally verified. Live directory backfill and invitation delivery checks required. |
| NFR-S3 | Signed MFA session claim for panel and API, live role and revocation checks for writes, recent authentication | backend authorization tests, password-only deny and real SMS MFA Auth emulator, MFA Firestore rules tests | Server and rules behavior verified locally. TOTP enrollment and recovery require staging rehearsal. Production MFA rollout remains pending. |

| Test run | Result |
|---|---|
| Flutter full suite | 926 passed, 4 skipped under the repository's golden-test configuration. |
| Flutter follow-up suites | 102 admin, auth and navigation tests passed. Seven dashboard and user-details tests passed after adding model-mismatch and deletion-confirmation cases. The final CMS timeout change passed 13 focused CMS tests. |
| Flutter analysis | `flutter analyze --no-pub` passed with no issues, as did analysis limited to `lib test`. The initial whole-workspace run included a pre-existing generated SDK copy under `build/`. The analyzer now excludes generated build output. |
| Firestore rules | `npm --prefix test_rules test` passed. The final rules also passed all 61 checks in the combined demo emulator run. |
| Firebase Auth + Firestore demo | Two workflows passed, including real SMS MFA claims, genuine account lifecycle, retry-safe invitation and password setup. The emulator does not validate TOTP platform enrollment or live email delivery. |
| Backend lint | The CI Ruff error classes passed. |
| Backend full suite | 694 passed, 2 emulator-only tests skipped, and 1 Starlette test-client deprecation warning. Initial failures came from stale assertions against the existing `diseaseEstimates` schema and the new safe heartbeat error. The final run preserved the model output schema. |
