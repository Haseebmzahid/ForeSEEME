# Module 1 final acceptance report

Reviewed on November 24, 2026 from the Module 9 baseline
`bb1cc4ac1904b5caf2c00873710cf3985f6028a2`.

The source release covers email/password and Google authentication, account
verification, recovery, health-profile onboarding and editing. Full SRS
acceptance remains open for phone-plus-password sign-in. Native and staging
evidence is required before a production deployment.

## Audit findings

The previous change inventory matched the checkout. The audit found that
resume-triggered FCM registration used the Firebase user record, which can
show a verified email before the cached ID token carries the claim. The
registration endpoint also accepted a valid session without that claim.
Registration now waits for the token-confirmed account and the API checks the
claim independently. Resume sync also leaves an in-progress logout alone so
pending-account cleanup can finish. The authenticated unregister path,
Firestore revocation cutoff, server-owned registry and logout receipts retain
their existing controls.

Profile saves are UID-scoped and merge the parent document without replacing
notification preferences. Firestore independently restricts ownership, city,
allowed fields, protected fields and custom label shape, length and count.
The form handles case-insensitive deduplication and whitespace normalization.
Legacy profiles with no custom field load with an empty list. Dispatch receives
custom labels separately from predefined conditions and reads city from the
current profile. Eligibility, disease-risk calculations and category
semantics are unchanged.

The shared router and Firestore rules enforce activation for the dashboard
and private user data. The auth screens reuse the existing emergency dial
action, and the full Resource Center retains its own access requirements.
The backend change to dispatch is limited to profile input. The registration
endpoint is the only Admin API production-code change. Admin authorization
and Module 9 storage and revocation logic retain their existing controls.

## Requirement matrix

| ID | Requirement | Implementation | Evidence | Status and acceptance gate |
| --- | --- | --- | --- | --- |
| FR1.1 | Register a named account with an email and password | `register_screen.dart`, `auth_notifier.dart`, `firebase_auth_repository.dart`. Require name, email, password and confirmation. Display the eight-character minimum and use Firebase uniqueness. | Registration widget tests, repository tests and SDK registration journey. | Implemented and tested locally. |
| FR1.2 | Verify email before activating a registered account | `firebase_auth_repository.dart`, `verify_email_screen.dart`, `app_router.dart`, `firestore.rules`. Send, resend with cooldown, reload, refresh the claim, then allow onboarding. | Auth tests, pending-route tests, SDK verification and rule denials. | Implemented and tested locally. Requires physical-device verification of real email and browser return. |
| FR1.3 | Enter and save health details with a supported location | `health_profile_screen.dart`, `health_profile_providers.dart`, `firestore_health_profile_repository.dart`. Require a supported city. Accept multiple or zero conditions. | Profile widget and repository tests and SDK profile persistence. | Implemented and tested locally. |
| FR1.4 | Update the profile and include custom condition values in alerting | `health_profile_screen.dart`, `health_profile_model.dart`, `firestore.rules`, `dispatch_alerts.py`, `targeting.py`. Save, normalize and remove custom labels. Pass them separately to dispatch. | Profile and rule tests, targeting and notification registration regressions. | Partially implemented. Capture, persistence and availability in targeting input are tested. Automatic classification and eligibility require approved medical vocabulary and mapping. |
| FR1.5 | Sign in with email or phone and a password | `login_screen.dart`, `auth_notifier.dart`, `firebase_auth_repository.dart`, `app_router.dart`. Email/password login, neutral errors, and account-state routing. | Auth and routing suites and SDK sign-in journey. | Partially implemented. Phone plus password is not implemented and requires supervisor approval. |
| FR1.6 | Show or hide the password | `register_screen.dart`, `login_screen.dart`. Mask by default and allow visibility changes. | Both auth form widget tests. | Implemented and tested locally. |
| FR1.7 | Recover a forgotten password by email | `forgot_password_screen.dart`, `password_reset_controller.dart`, `firebase_auth_repository.dart`. Submit through Firebase and give neutral feedback. | Recovery tests and SDK valid, invalid and reused-code journey. Expired-code and refresh-token behavior reviewed against Firebase documentation. | Implemented and tested locally. Requires staging verification for hosted expiry, templates, handler and session propagation. |
| FR1.8 | Sign in through Google and retain account-linked profile data | `firebase_auth_repository.dart`, `app_router.dart`, `firestore_health_profile_repository.dart`. Use Firebase Google credentials, the same verification gate, and UID-scoped persistence. | Verified mock Google onboarding and re-login, profile repository tests. | Implemented and tested locally. Requires physical-device Google OAuth and restart verification. |
| FR1.9 | Navigate between registration and sign-in | `register_screen.dart`, `login_screen.dart`, `app_router.dart`. Both entry screens link to the other. | Auth form suite and route review. | Implemented and tested locally. |
| FE-2 | Store the user's current supported location and use it in alert input | `health_profile_screen.dart`, `firestore_health_profile_repository.dart`, `dispatch_alerts.py`. Read the latest saved city. | SDK city-edit journey and backend targeting-directory test. | Implemented and tested locally. |
| FE-3 | Store optional vulnerability information and support profile updates | `health_profile_screen.dart`, `health_profile_model.dart`, `firestore.rules`. Toggle predefined conditions, persist custom values, and reload saved data. | Profile UI, repository, and Firestore ownership tests. | Implemented and tested locally. Medical interpretation remains open under FR1.4. |

## External acceptance gates

- Obtain a written supervisor decision for FR1.5. The alternatives and approval
  language are in the [phone-login decision](MODULE_1_PHONE_LOGIN_DECISION.md).
- Approve a medical vocabulary and category mapping before using arbitrary
  custom labels for eligibility.
- Verify native Google OAuth, Firebase email delivery and browser return,
  process restart, the system dialer, and real FCM registration and cleanup
  in staging. Verify the release project's email templates, hosted action
  handler and password-reset lifetime. Firebase documents its error and
  revocation behavior. [Auth REST API](https://firebase.google.com/docs/reference/rest/auth#section-confirm-password-reset) · [Session management](https://firebase.google.com/docs/auth/admin/manage-sessions)

The original SRS and SDS, Module 2 scheduling and dose logic, and Modules 5 and
6 source, configuration and artifacts are outside the release diff.

## Test commands and evidence

The focused Flutter run passed 218 tests. The FCM-only rerun after the
logout/resume fix passed 9 tests. The final full Flutter run passed 968 tests
and skipped four opt-in golden suites. The release-source analyzer reported
no issues. The focused backend run passed 74 tests.
The full backend run passed 757 tests and skipped 4 emulator-only tests,
which then passed with both demo emulators. The rules runner passed 118
checks and the Auth/Firestore runner passed all four journeys. The Python
runs reported a Starlette test-client dependency deprecation warning.

```text
flutter test --reporter expanded test/features/auth test/core/routes test/features/health_profile test/features/alerts test/features/disease_explorer/disease_navigation_test.dart test/integration
flutter test --no-pub --reporter expanded test/features/alerts/alerts_test.dart
flutter analyze
flutter test --reporter expanded

# From backend, using joblib's sequential backend for local execution
pytest tests/test_targeting.py tests/test_dispatch_alerts.py tests/test_notification_registrations.py tests/test_session_revocation.py tests/test_admin_api.py -q -rs
pytest -q -rs

# From the repository root, using demo-foreseeme and spare loopback ports
firebase emulators:exec --config .module1-acceptance-emulators.json --only auth,firestore --project demo-foreseeme "node test_rules/firestore_rules.test.mjs && node test_rules/module1_journey.test.mjs && python -m pytest backend/tests/test_admin_emulator.py -q -rs"
```

The temporary emulator configuration copied the checked-in settings and changed
only loopback ports. The workspace-wide analyzer encountered an ignored archived
test under `evaluation_60/`. The release analysis uses an isolated copy of the
tracked Flutter project and the intended new Flutter files.

## Changed files

+- `assets/branding/logo/google-sign-in-g.png`
- `backend/app/admin_api.py`
- `backend/app/jobs/alerting/targeting.py`
- `backend/app/jobs/dispatch_alerts.py`
- `backend/tests/test_admin_emulator.py`
- `backend/tests/test_notification_registrations.py`
- `backend/tests/test_session_revocation.py`
- `docs/MODULE_1_FINAL_ACCEPTANCE_REPORT.md`
- `docs/MODULE_1_PHONE_LOGIN_DECISION.md`
- `docs/auth-flow.md`
- `firestore.rules`
- `lib/core/routes/app_router.dart`
- `lib/features/alerts/presentation/alerts_controller.dart`
- `lib/features/alerts/presentation/alerts_providers.dart`
- `lib/features/auth/data/repositories/firebase_auth_repository.dart`
- `lib/features/auth/domain/models/user_model.dart`
- `lib/features/auth/domain/repositories/auth_repository.dart`
- `lib/features/auth/presentation/auth_notifier.dart`
- `lib/features/auth/presentation/auth_state.dart`
- `lib/features/auth/presentation/forgot_password_screen.dart`
- `lib/features/auth/presentation/login_screen.dart`
- `lib/features/auth/presentation/password_reset_controller.dart`
- `lib/features/auth/presentation/register_screen.dart`
- `lib/features/auth/presentation/verify_email_screen.dart`
- `lib/features/auth/presentation/widgets/emergency_help_button.dart`
- `lib/features/auth/presentation/widgets/google_auth_button.dart`
- `lib/features/health_profile/data/repositories/firestore_health_profile_repository.dart`
- `lib/features/health_profile/domain/constants/conditions_constants.dart`
- `lib/features/health_profile/domain/models/health_profile_model.dart`
- `lib/features/health_profile/domain/repositories/health_profile_repository.dart`
- `lib/features/health_profile/presentation/disclaimer_providers.dart`
- `lib/features/health_profile/presentation/health_profile_notifier.dart`
- `lib/features/health_profile/presentation/health_profile_providers.dart`
- `lib/features/health_profile/presentation/health_profile_screen.dart`
- `test/features/alerts/alerts_test.dart`
- `test/features/auth/auth_notifier_test.dart`
- `test/features/auth/firebase_email_verification_test.dart`
- `test/features/auth/forgot_password_screen_test.dart`
- `test/features/auth/password_reset_controller_test.dart`
- `test/features/disease_explorer/disease_navigation_test.dart`
- `test/features/health_profile/disclaimer_acceptance_test.dart`
- `test/features/health_profile/firestore_health_profile_repository_test.dart`
- `test/features/health_profile/health_profile_notifier_test.dart`
- `test/features/health_profile/health_profile_providers_test.dart`
- `test/features/health_profile/health_profile_screen_test.dart`
- `test/features/profile/profile_hub_golden_test.dart`
- `test/features/profile/profile_hub_test.dart`
- `test_rules/firestore_rules.test.mjs`
- `test_rules/module1_journey.test.mjs`
