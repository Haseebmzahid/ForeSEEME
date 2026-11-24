# Module 9 security, privacy and compliance evidence

Baseline was clean on `main` at `3ac3b5dfa007b494424ca2d60efaf7ac4b0d06ec`, the same revision referenced in the brief. The exact named SRS and SDS Word files were unavailable in the repository. The implementation uses the user-supplied requirements, the checked-in SDS transcription at sections 2.6, 2.7.4 and 4.3, and the historical RTM extract. The authoritative wording and the historical extract remain intact. This report supersedes the historical Module 9 verification status for this working tree.

This report describes the implementation and preserves the earlier test runs. The [verification and closure report](MODULE_9_VERIFICATION_AND_CLOSURE_REPORT.md) is the current evidence record for the specified SDS transcription. It carries forward 83 distinct passing backend cases and records the final Flutter, Android APK, and Firebase demo emulator results. FR9.5 remains partial pending an approved Android persistence decision. FR9.4 still requires production ingress and pinning evidence. Staging, production, and privacy sign-off remain separate from repository publication.

## Session revocation and release hardening

`POST /v1/session/logout` first commits the inclusive `sessionRevocations/{uid}.throughAuthTime` cutoff and a service-only receipt at `sessionRevocations/{uid}/logoutIntents/{auth_time}` in one Firestore transaction. The receipt captures the original logout boundary and a server timestamp. The same account record coordinates one Firebase mutation through a renewable ten-minute lease. No bearer token or FCM token is stored in the receipt.

Firestore rules, privileged API authorization, FCM registration and dispatch use the cutoff. The service acknowledges logout only after Firebase reports a revocation time strictly after the receipt boundary and the account record durably records the confirmed boundary. It reconciles from Firebase evidence before making another mutation. A retry after confirmation returns 204 without revoking a later login. While a lease is held, concurrent requests can receive 503. After a crashed or ambiguous attempt, a retry can take over after lease expiry. This recovery is request-driven. A genuinely incomplete account-wide operation can invalidate sessions created before it finishes.

Logout is the only route that retries signature validation without the Firebase revocation lookup, and only after Firebase explicitly reports the bearer revoked. The UID and authentication time still come from a valid Firebase ID token, and a revoked caller can resume only its existing receipt. Normal protected API calls keep Firebase revocation checks and the independent Firestore cutoff. Flutter retries a transient failure once using the same in-memory bearer before proceeding with local sign-out. Offline users still receive an unconfirmed global result.

Admin suspension, deletion and the supported role-removal command record the cutoff before changing Auth and advance it after the operation. Reactivation preserves that cutoff. First-party URL checks reject invalid ports in addition to invalid or non-HTTPS origins. Admin and session requests continue to reject redirects. Production ingress, trusted proxy settings and SDK or device behaviour need staging evidence.

## Server-owned push registration

This change started on clean `main` at `3ff200c529624b9355e23efa4e96b95b123bb428`. It separates Firebase Auth sessions from FCM delivery registrations. It does not change native Auth persistence, the SRS or SDS, or the certificate-pinning disposition.

- `POST /v1/notifications/register` accepts `token` and optional `previousToken` for rotation. `POST /v1/notifications/unregister` accepts `token`. Both use the existing HTTPS API and Firebase bearer verification with revocation checking. They derive `uid` and `auth_time` from claims and check `sessionRevocations` in the write transaction. They return 204 for an acknowledged operation, 401 for an inactive session, and 409 for a conflicting registration. A removal for an association owned by a different session is an idempotent no-op.
- `notificationRegistrations/{sha256(token)}` uniquely identifies an active registration. It stores `uid`, `token`, `authTime`, a server-generated `generation`, and `updatedAt` from the server. Repeating the same active binding is idempotent. Newer verified sessions can take ownership. An older session or an equal-time different UID cannot. Rotation retires the previous token only if it belongs to the same session. Retirement removes the raw token and retains the ordering metadata so a delayed request cannot recreate the old association. Client access to the registry and client writes to the legacy FCM fields are denied.
- Both jobs preserve the existing user-level targeting, throttle and dispatch keys. The weekly report also claims its user/week key transactionally before sending. For each alert, the jobs fan out to current registrations and write one user-level audit record and one inbox item after at least one accepted send. Audit records include per-device outcome counts. Registration and session identity are rechecked before delivery, and invalid-token pruning compares UID, authentication time, token and generation transactionally. Neither job reads the legacy token.
- Flutter starts synchronization for an authenticated user with existing OS permission and retains the explicit permission path. It serializes registration work, uses the current user to obtain the bearer and rechecks the session before network operations. Logout stops refresh work and attempts unregister before the existing revocation and local sign-out. Offline or failed unregistration does not prevent local sign-out. The SDK token is not deleted locally. A subsequent user can claim the same token with a newer verified sign-in.
- Risk and weekly notifications show **ForeSeeMe update** and **Health awareness only — not a medical diagnosis. Open ForeSeeMe to view your updates.** Push data carries the recipient UID and an opaque inbox reference. Foreground and tap handlers check the current Firebase UID. Account-specific routing comes from a server read of the current user's inbox, with a second UID check before navigation. The payload contains no personalized text or route. The same checks apply to taps on foreground notifications displayed by the local plugin.

## Push rollout and limitations

Coordinate a staging cutover of the registry-capable API, rules, Flutter release, and both job images. Measure successful registrations and confirm that updated clients register on launch or resume. Legacy fields remain intact but are not safe to import automatically, and users who have not re-enrolled cannot receive new pushes after the jobs switch to registry-only delivery. Communicate the transition and stop legacy senders before enabling registry-only dispatch. Do not roll back to senders that trust legacy ownership or display personalized copy. If delivery must be paused, retain the inbox and rules and resume with the reviewed job build.

The registry authenticates the account and matches the submitted opaque FCM token. It adds no installation attestation or proof-of-delivery handshake. Equal-second conflicting sign-ins require a later Firebase authentication. The retirement records require an approved retention policy that preserves the stale-request boundary. Offline logout cannot guarantee immediate remote cleanup. FCM and the OS can deliver already-accepted notifications following logout. New notification copy is neutral. Older queued or delivered notifications from legacy senders cannot be recalled by this change.

Medication notification scheduling and dose tracking were left unchanged. The local scheduler can retain medication content on the device. The inspected logout path has no medication-specific cancellation, so previously scheduled reminders may remain visible after an account switch. Verify this separately in Module 2.

## Original security requirements

The following statements come from the checked-in SDS transcription. The business rules in its Module 9 table remain part of the acceptance criteria.

| ID | Original statement |
| --- | --- |
| FR9.1 | The system shall store all user data including health profiles, medication logs, and adherence records encrypted within Firebase Firestore. |
| FR9.2 | The system shall implement Firestore Security Rules ensuring that a user can only read or write their own documents. |
| FR9.3 | The system shall not collect, store, or process detailed diagnostic symptoms, clinical test results, or any medical record data beyond the user's self-reported chronic condition category. |
| FR9.4 | The system shall enforce HTTPS for all communications between the mobile application and the backend API and Firebase services. |
| FR9.5 | The system shall securely store authentication tokens on the device and invalidate all active tokens upon user logout. |
| FR9.6 | The system shall display a prominent disclaimer on the Risk Dashboard and in all push alert content clarifying that ForeSeeMe is a health awareness tool only and does not provide medical diagnoses. |
| NFR-S1 | All user passwords must be stored using Firebase Authentication's built-in bcrypt hashing. Plaintext passwords must never be stored or transmitted. |
| NFR-S2 | The FastAPI ML microservice must only accept requests from the authenticated backend service, not from the mobile client directly. An internal API key or Firebase service account token must be required for all inference calls. |
| NFR-S3 | The admin panel must require multi-factor authentication. A single-factor login to the admin interface is not permitted. |
| NFR-S4 | All collected user data must be handled in accordance with Pakistan's applicable data protection guidelines. No user data may be shared with or sold to third parties. |

## Requirement traceability and implementation checklist

| ID | Requirement | Implementation and local evidence | Status and remaining evidence |
| --- | --- | --- | --- |
| FR9.1 | Store user data, including health profiles, medication logs and adherence records, encrypted in Firestore using the specified default at-rest protection. | Profile, medication and adherence repositories store the system of record in Firestore. Firebase SDK offline caches, local reminder content, medication scheduling identifiers and milestones use device storage. No custom database, encryption, or user-record export was added. | Google documents default server-side encryption. Confirm the project's actual database key configuration and region, IAM, backups/exports, and native cache/backup device behavior. [Firestore server-side encryption](https://docs.cloud.google.com/firestore/native/docs/server-side-encryption) |
| FR9.2 | Firestore rules must restrict users to their own records, with cross-account access rejected at the database. | `firestore.rules` retains owner checks, MFA, service-only writes and default deny. It adds explicit settings/profile paths, owner-bound acceptance and the service-only revocation boundary. Public-to-authenticated risk/content projections remain as designed. Rules tests cover owner and cross-owner reads/writes, operational restrictions, MFA, revocation and consent. | Local rules evidence and deployed parity are separate. Stage rules before distributing the client. |
| FR9.3 | Do not collect, store or process detailed diagnostic symptoms, clinical results or medical records beyond the self-reported chronic condition category. Expanded collection requires explicit informed consent. | Health-profile writes are limited to supported cities, selected categories and profile metadata. The settings schema rejects arbitrary keys. Clinical data intake is absent. Medication and adherence remain supported as specified. Identifiers and profile values were removed from active onboarding diagnostics. | Current collection inventoried. Review legacy documents, medication free text and retention. Require approved collection rationale and informed consent before adding clinical data. |
| FR9.4 | Require HTTPS between the app, backend and Firebase, rejecting plain HTTP at both client and server. | Admin and logout clients validate explicit HTTPS URLs and decline redirects. Places uses fixed HTTPS and declines redirects. Android cleartext is disabled and iOS ATS is explicit. Inference and admin API use the ASGI scheme from a trusted TLS ingress. Local model health probes may use cleartext. | Confirm release APK manifest, iOS archive, HTTPS-only production ingress/proxy behavior and external redirect tests. Production pinning requires the approved hostname and current and backup SPKIs, rotation overlap and a recovery/release plan. |
| FR9.5 | Use secure token storage and invalidate all active tokens upon logout. | Firebase Auth owns token persistence. Web requests memory-only persistence. Logout passes only the current Firebase ID token to the HTTPS API, which derives the UID, invokes Firebase revocation and records a monotonic Firestore cutoff. Firebase and Google local cleanup run even if revocation cannot be confirmed. Admin APIs check both Firebase revocation and the Firestore cutoff. | Partial. Inspection of the installed Android Firebase Auth 24.1.0 AAR found the Auth token store uses SDK-owned app-private SharedPreferences. The Flutter SDK does not expose a native persistence override. App backup is disabled in the Android manifest. Verify device transfer, actual iOS/desktop behavior, two-device logout, already-issued tokens and cutoff failure recovery. Managed endpoints that lack the cutoff can accept existing ID tokens until expiry. [Flutter Auth persistence](https://firebase.google.com/docs/auth/flutter/start) · [Firebase session revocation](https://firebase.google.com/docs/auth/admin/manage-sessions) |
| FR9.6 | Display a prominent dashboard and push disclaimer, and require first-time acceptance before dashboard access. | The current version is `v1`. The router gates authenticated, profile-complete users on a server-confirmed account/version record. Writes are immutable and server-timestamped. Profile-ready and notification-permission screens stay independent. Risk and weekly push paths use the compact notice via the shared FCM sender. Foreground re-display adds it if needed. The dashboard and in-app alert surfaces retain the longer wording where applicable. | Verify existing and new accounts, a new version, offline behavior, background pushes and visible truncation across platforms in staging. |
| NFR-S1 | Firebase Authentication must hash passwords. SRS/SDS specifies bcrypt and prohibits plaintext storage/transmission. | App forwards passwords to Firebase's TLS API. Repository inspection found no application-owned password store. Firebase documents modified SCRYPT as default, with imported hashes potentially using other algorithms until sign-in. | Actual project algorithm and import history unverified. An authorized operator should verify only the algorithm label and migration history. Preserve the requirement pending approval. Proposed wording is “Passwords shall be handled by Firebase Authentication using Firebase-managed password hashing and sent only over TLS. ForeSeeMe shall not persist plaintext passwords.” [Firebase password import and hashing](https://firebase.google.com/docs/cli/auth) |
| NFR-S2 | Inference accepts only an authenticated backend service, with no direct mobile inference. | `POST /predict` validates Google-signed OIDC signature, issuer, expiry, audience and the configured dedicated service-account subject. Missing configuration denies inference. The scheduled job invokes the model in-process and writes Firestore, which Flutter reads. No client caller or privileged client secret was added. | Verify a private deployed Cloud Run service and dedicated invoker, or confirm that only the scheduled job is deployed. Unit verification cannot establish live IAM. [Cloud Run service authentication](https://docs.cloud.google.com/run/docs/authenticating/service-to-service) |
| NFR-S3 | Admin panel requires MFA and denies single-factor access. | Existing custom claims, phone/TOTP flows, guarded admin shell, MFA rule checks, recent-auth checks, live role checks, audit records and throttling remain. The claim-removal operator command now records the Firestore session cutoff in addition to revoking refresh tokens. | Verify current rules and active operator claims through authorized review, rehearse MFA enrollment and recovery in staging, and use the cutoff-aware operator command for role removal. Direct out-of-band Auth edits require a matching cutoff to deny already-issued Firestore tokens immediately. |
| NFR-S4 | Handle data in accordance with applicable Pakistani data-protection requirements. Do not sell or improperly share user data. | [Privacy and data handling draft](MODULE_9_PRIVACY_DATA_HANDLING_DRAFT.md) maps data, purpose, recipients, access and unresolved obligations. | Legal and organizational review pending. Approve data inventory, processor terms, retention/deletion, user rights and incident responsibilities before a legal compliance claim. |

## Operations and versioning

- Inference uses `INFERENCE_AUDIENCE` and `INFERENCE_SERVICE_ACCOUNT_SUBJECT`. Set the audience to the Cloud Run service audience and the subject to the dedicated caller identity's numeric unique ID. Require Cloud Run IAM authentication with the dedicated caller as invoker, check inherited IAM and restrict ingress as appropriate. Use metadata/attached identity Google ID tokens. When both IAM and application verification are enabled, use `X-Serverless-Authorization` for IAM and preserve the intact signed bearer in `Authorization` for the application. The scheduled compute job needs no inference credentials for its in-process call. Preserve Cloud Run's TLS termination and pin trusted forwarding peers when starting Uvicorn. Keep container ports unreachable directly. [Cloud Run service authentication](https://docs.cloud.google.com/run/docs/authenticating/service-to-service) · [Cloud Run container contract](https://docs.cloud.google.com/run/docs/container-contract)
- Deploy the Firestore rules and HTTPS API in staging before a client configured with `ADMIN_API_URL`. Test a two-device sign-in followed by logout and an immediate read/write with the old ID token. Compare Auth's validity boundary with the service-only Firestore cutoff. A sign-in in the cutoff second must be repeated after that second. Auth and Firestore have separate commits. The client reports uncertainty if either side fails and still attempts local cleanup. Recover by checking the Auth cutoff and Firestore document, then recording the confirmed higher cutoff or repeating logout after reauthentication. Protect the public TLS endpoint with edge rate limiting. The runtime uses the existing Auth admin and Firestore identity.
- Ship any materially changed disclaimer under a fresh version. Add its exact version to the Firestore rule before shipping the corresponding binary. Retain older immutable records and preserve supported older clients through a controlled rules transition. A missing, invalid or unreadable current record leaves the dashboard gated. A previously committed record can be read from the Firestore cache on the same device. The transaction requires an online commit for new acceptance, and local pending writes cannot satisfy the guard. Account deletion and retention policy must account for the acceptance record.
- Review current MFA platform support, exercise phone and TOTP in staging, rehearse recovery, verify removal of both API and Firestore access with a stale token, and monitor the original administrative audit events. Production IAM, deployment, Firebase configuration, accounts, and data were left untouched.

## Reproduction

Run backend, Flutter and demo emulator checks from the repository root.

```powershell
python -m pytest -q -rs backend
flutter analyze --no-pub
flutter test --no-pub
firebase emulators:exec --only firestore --project demo-foreseeme "node test_rules/firestore_rules.test.mjs"
firebase emulators:exec --only auth,firestore --project demo-foreseeme "python -m pytest -q backend/tests/test_admin_emulator.py"
flutter build apk --debug --no-pub
```

The registered emulator project is `demo-foreseeme`. The Firestore rules runner loads the checked-in rules explicitly and prints its assertion totals. Live provider access, FCM delivery, console hashing/IAM evidence, iOS build and qualified legal review require the corresponding authorized environments.

## Earlier implementation verification

| Check | Result |
| --- | --- |
| Full backend and ML rerun | 725 passed, zero failed, and two Auth/Firestore emulator tests skipped. Ran `pytest -q -rs backend` using the Windows selector test driver. The later test for rejecting an unexpected inference field was collected and passed in the focused and complementary runs. |
| Focused backend | 108 passed, zero failed or skipped. The sandbox blocks the default Windows asyncio loopback wakeup for Starlette's in-process client. The run used a temporary Windows selector test driver that polls its ready queue and leaves application, assertions, signature verification and networking restrictions intact. |
| Backend and ML, excluding the long risk-compute shard | 704 passed, zero failed, and two Auth/Firestore emulator tests skipped. Ran `pytest -q -rs backend --ignore=backend/tests/test_compute_risk.py` using the same selector driver. |
| First broad backend run | 528 passed, two failed, and two Auth/Firestore emulator tests skipped. The failures checked the pre-change push copy and assumed the raw provider error was retained. Those assertions now verify the required notice and error redaction while preserving the existing classification and retry checks. |
| Push, weekly and dispatch with standard Python | 44 passed via `python -m pytest -q backend/tests/test_messaging.py backend/tests/test_push_disclaimer.py backend/tests/test_weekly_report.py backend/tests/test_dispatch_alerts.py`. These overlap the focused run and include the corrected assertions. |
| Backend CI lint | Passed via `python -m ruff check backend/app backend/ml backend/scripts backend/tests --select E9,F63,F7,F82`. |
| Flutter static analysis | Passed via `dart --suppress-analytics analyze --fatal-infos` using the Dart SDK shipped with local Flutter. |
| Runtime Flutter suites and Android build | Unavailable. Flutter could not open its SDK cache lockfile under the workspace sandbox. Automatic permission review timed out on the test retry. The flow, widget and local logout tests are included for a runnable environment. |
| Firestore and Module 8 Auth/Firestore emulators | Java could not establish a sandboxed loopback connection. Automatic permission review timed out. The runner contains 90 named checks. Zero of those checks were verified by the emulator on this host. `node --check test_rules/firestore_rules.test.mjs` passed and validates JavaScript syntax only. |
| Platform settings and patch integrity | Android and iOS config parsed and the explicit release cleartext flags matched expectations. A standalone Dart program using the real HTTPS validator and session client with `MockClient` passed URL, bearer and redirect checks. `git diff --check` passed. iOS compilation requires macOS. |
| Production and hashing evidence | The CLI could not access its local credential configuration inside the sandbox and the read-only Cloud Run permission review timed out. No deployed IAM, Firebase project algorithm, service-region, deployed rules, or MFA rollout evidence was established in this session. |

The 108-test focused run selected these files:

```text
backend/tests/test_inference_auth.py
backend/tests/test_admin_api.py
backend/tests/test_api.py
backend/tests/test_api_validation_boundary.py
backend/tests/test_predict.py
backend/tests/test_messaging.py
backend/tests/test_push_disclaimer.py
backend/tests/test_weekly_report.py
backend/tests/test_dispatch_alerts.py
```

## Change inventory

| File | Purpose |
| --- | --- |
| `backend/app/inference_auth.py` | Verifies Google-signed service identity and denies unconfigured or untrusted callers. |
| `backend/app/config.py` | Reads the configured inference audience and service-account subject. |
| `backend/app/main.py` | Requires HTTPS and service identity on inference, preserves the prediction contract, and removes input logging and reflected input values from validation responses. |
| `backend/app/schemas.py` | Rejects fields outside the environmental inference contract. |
| `backend/app/admin_api.py` | Provides authenticated self-logout and checks the revocation cutoff on admin operations. |
| `backend/app/session_revocation.py` | Writes a monotonic Firestore session cutoff transactionally. |
| `backend/scripts/set_admin_claim.py` | Writes the session cutoff on admin removal and checks paired demo emulator configuration. |
| `backend/app/jobs/alerting/messaging.py` | Adds the compact notice to risk and shared FCM payloads and redacts provider exception details. |
| `backend/app/jobs/weekly_report.py` | Adds the same notice to weekly digest and inbox content. |
| `firestore.rules` | Enforces the cutoff, owner-only immutable consent, and existing settings/profile/medication/adherence document shapes. |
| `android/app/src/main/AndroidManifest.xml` | Rejects cleartext and disables app backup at manifest level. |
| `ios/Runner/Info.plist` | Sets ATS to disallow arbitrary loads. |
| `lib/core/network/https_api_url.dart` | Validates static HTTPS service origins and optional path prefixes. |
| `lib/core/routes/app_router.dart` | Applies the current disclaimer guard alongside authentication and profile completion. |
| `lib/features/admin/data/repositories/admin_api_client.dart` | Shares strict URL validation while preserving token and POST behavior. |
| `lib/features/alerts/data/services/local_notification_alert_presenter.dart` | Ensures foreground alert text includes the notice, including for older message payloads. |
| `lib/features/alerts/presentation/alert_inbox_screen.dart` | Shows the full disclaimer in the inbox. |
| `lib/features/alerts/presentation/notification_permission_screen.dart` | Routes standalone dismissal through the normal dashboard guard. |
| `lib/features/auth/data/repositories/firebase_auth_repository.dart` | Revokes remotely before local cleanup and reports unconfirmed results. |
| `lib/features/auth/data/repositories/session_api_client.dart` | Sends a bearer-authenticated, redirect-disabled HTTPS logout call. |
| `lib/features/auth/presentation/auth_notifier.dart` | Exposes unconfirmed logout to the root app UI. |
| `lib/features/auth/presentation/auth_providers.dart` | Wires the session client into the existing Firebase repository. |
| `lib/features/auth/presentation/auth_state.dart` | Carries the logout confirmation state. |
| `lib/main.dart` | Selects in-memory web authentication and displays logout failures across route changes. |
| `lib/features/health_profile/data/repositories/firestore_disclaimer_repository.dart` | Uses Firestore for account-bound, per-version acceptance and waits for the online transaction. |
| `lib/features/health_profile/data/repositories/firestore_health_profile_repository.dart` | Removes path, UID and profile values from onboarding logs. |
| `lib/features/health_profile/domain/repositories/disclaimer_repository.dart` | Defines the consent version and persistence contract. |
| `lib/features/health_profile/presentation/disclaimer_acceptance_screen.dart` | Presents the canonical disclaimer, explicit acceptance and retry feedback. |
| `lib/features/health_profile/presentation/disclaimer_providers.dart` | Resolves acceptance against the signed-in account and refreshes the gate after it saves. |
| `lib/features/health_profile/presentation/health_profile_providers.dart` | Wires the consent repository and redacts profile-existence logs. |
| `lib/features/resources/data/repositories/google_places_repository.dart` | Disables redirects on Places requests and avoids exposing provider response bodies. |
| `backend/tests/test_inference_auth.py` | Exercises actual signature and claim validation, transport and default-deny configuration using generated keys. |
| `backend/tests/test_admin_api.py` | Verifies the logout UID, denied credentials, uncertain outcomes and existing MFA protections. |
| `backend/tests/conftest.py` | Separates model contract fixtures from real signature tests. |
| `backend/tests/test_api.py` | Retains the promoted-model API contract using the isolated HTTPS fixture. |
| `backend/tests/test_api_validation_boundary.py` | Retains malformed request and boundary cases behind the HTTPS fixture. |
| `backend/tests/test_predict.py` | Retains the stub prediction contract behind the HTTPS fixture. |
| `backend/tests/test_messaging.py` | Keeps the exact push payload and retry checks aligned with mandatory disclaimer text and redacted provider errors. |
| `backend/tests/test_push_disclaimer.py` | Covers risk bands, alert categories and shared FCM body enforcement. |
| `backend/tests/test_weekly_report.py` | Verifies the digest notice and preserves non-diagnostic recommendation checks. |
| `test/features/auth/firebase_auth_logout_test.dart` | Covers Firebase and Google cleanup after both confirmed and failed remote logout. |
| `test/features/auth/session_api_client_test.dart` | Covers missing or insecure endpoints, HTTPS bearer requests and rejected redirects. |
| `test/features/disease_explorer/disease_navigation_test.dart` | Updates the existing actual-router regression for a previously accepted user. |
| `test/features/health_profile/disclaimer_acceptance_test.dart` | Covers account/version persistence, direct navigation and failed writes. |
| `test_rules/firestore_rules.test.mjs` | Adds cross-user writes, minimization, consent and revocation coverage with explicit totals. |
| `docs/MODULE_9_PRIVACY_DATA_HANDLING_DRAFT.md` | Inventories data processing and records legal and organizational decisions. |
| `docs/MODULE_9_SECURITY_IMPLEMENTATION_REPORT.md` | Reconciles traceability and records implementation, checks and rollout dependencies. |
