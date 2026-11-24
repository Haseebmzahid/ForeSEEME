# ForeSeeMe Module 9 verification and closure

## Release requirement matrix

The security controls below were reviewed against the supplied SRS wording and the checked-in [SDS transcription](<ForeSeeMe SDS final(SP23-BSE-034 & 040).docx.md>). FR9.4 HTTPS enforcement and the production pinning commitment in Table 4.8 are separate acceptance decisions. This work establishes local code and emulator evidence. It does not establish production compliance.

| Requirement and source | Existing implementation | Final change and local evidence | Status | Outstanding acceptance |
| --- | --- | --- | --- | --- |
| FR9.1, SRS and SDS Table 2.21 | Firestore stores user profile, medication and adherence data. | No storage or project configuration change. Owner access and data shape were retested. | Requires staging verification. | Confirm encryption, backups, exports, region and authorized access in the deployed project. |
| FR9.2, SRS and SDS Table 2.21 | Owner and MFA rules, server-only fields and default-deny. | Demo checks cover the registry, private inbox and profile, logout receipts, stale access and current sign-ins. Admin suspension and deletion now advance the cutoff. | Implemented and tested locally. | Validate deployed rule and IAM parity. |
| FR9.3, SRS and SDS Table 2.21 | Profile categories and inference schemas restrict clinical inputs. | The FCM payload uses only neutral copy and recipient and inbox identifiers. Rule and inference validation regressions passed. | Implemented and tested locally. | Review legacy records, medication free text, processors and any future explicit-consent collection. |
| FR9.4, SRS and SDS Table 2.21 | HTTPS-only first-party URL parsing, redirect refusal, FastAPI scope checks, Android cleartext restriction and iOS ATS. | Added invalid port rejection and tests for malformed configuration, HTTPS redirects and cleartext session and registry routes. The inference liveness exemption was unchanged. | Requires staging verification. | Verify signed APK and iOS release, ingress/proxy trust and Firebase SDK network behaviour. |
| FR9.5, SRS and SDS Table 2.21 | Native Firebase persistence and API logout with a Firestore cutoff. | Firestore cutoff and receipt before Firebase mutation, monotonic confirmation, bounded client retry and fault-injection/emulator coverage. | Requires supervisor/client approval. | Approve Android native persistence disposition. Rehearse two-device and offline behaviour and operational recovery for pending receipts. |
| FR9.6, SRS and SDS Table 2.21 | Current-version, server-timestamped acceptance and authenticated dashboard route. | Tested version separation, route denial, FCM recipient checks and exact risk/weekly disclaimer copy. | Requires physical-device verification. | Verify restart, next-version rollout and lock-screen rendering in foreground, background and terminated states. |
| NFR-S1, SDS §2.7.4 | Firebase manages password hashing and the app uses Firebase Auth over TLS. | No password architecture or hashing change. Source contains no app-owned password store. | Requires supervisor/client approval. | Verify only the deployed hashing algorithm label and import history. Approve the discrepancy with original bcrypt wording. |
| NFR-S2, SDS §2.7.4 | Inference requires Google's signed service identity with expected audience and numeric subject. | Local inference tests cover missing configuration, unauthenticated callers and invalid identity. The frozen inference implementation was unchanged. | Requires staging verification. | Confirm Cloud Run IAM, identity and ingress. |
| NFR-S3, SDS §2.7.4 | Refreshed admin claim, MFA, recent authentication and live role verification. | Added cutoff-first role removal and account-state changes. Demo and fault tests cover password-only denial, MFA, stale privileged access and removed role. | Requires staging verification. | Rehearse TOTP or SMS enrollment, recovery and out-of-band role changes. |
| NFR-S4, SDS §2.7.4 | Restricted application data and role-scoped access. | Updated the privacy draft for registry, retention, neutral push, receipts and cached data. | Requires supervisor/client approval. | Approve privacy policy, processors, retention, deletion, incident ownership and applicable legal review. |
| SDS §4.3.3, native data storage | Android Firebase Auth uses app-private preferences. Apple persistence is SDK-managed. | No duplicate token storage or SDK redesign. The previous local Android storage finding remains open. | Requires supervisor/client approval. | Resolve secure-storage wording, validate signed mobile artifacts and review cache and backup handling. |
| SDS §4.3.4 / Table 4.8, production pinning | Standard HTTPS and platform trust. | Production pinning is unimplemented. HTTPS regressions were exercised independently. | Requires supervisor/client approval. | Approve first-party host, key owner, backup keys, rotation and recovery, or formally disposition the design commitment. |

### Remaining release checks

Staging must confirm registry re-enrollment before cutover, disable legacy senders, and test safe rollback by pausing push. Run signed Android and iOS two-device logout, permission, token rotation, account switch and real FCM/APNs display tests. Confirm staging Cloud Run service identity and trusted ingress configuration. No production deploy, production data operation, live FCM delivery or physical-device run occurred during this work.

Module 2 remains a separate follow-up. Previously scheduled local medication notifications can show medication names after account switching. This work changes neither medication reminder scheduling nor dose tracking.

### Final executed validation

| Command and context | Observed result |
| --- | --- |
| `flutter test --no-pub --reporter expanded test/features/auth test/features/alerts test/features/health_profile/disclaimer_acceptance_test.dart test/features/core/medical_disclaimer_test.dart` | 155 passed. |
| `flutter test --no-pub --reporter expanded` | 947 passed, four configured golden-suite skips, zero failed. |
| `flutter analyze --no-pub` | No issues. |
| `python -B -m pytest -q -rs tests/test_session_revocation.py tests/test_admin_api.py tests/test_notification_registrations.py tests/test_inference_auth.py tests/test_push_disclaimer.py`, from `backend` | 65 passed in the first focused run. The full backend run includes the subsequent role-removal and transport assertions. |
| `python -m ruff check app ml scripts tests --select E9,F63,F7,F82`, from `backend` | Passed. |
| `python -B -m pytest -q -rs`, from `backend` | 755 passed, four paired-emulator tests skipped, zero failed. The installed Starlette TestClient emitted a deprecation warning. |
| `node test_rules/firestore_rules.test.mjs` under demo Auth and Firestore | 103 rule checks passed. |
| `python -B -m pytest -q -rs backend/tests/test_admin_emulator.py` under demo Auth and Firestore | All four emulator tests passed, including logout replay after a later sign-in. |
| `python -B backend/scripts/verify_dispatch_pipeline.py` under demo Auth and Firestore | Passed using a recording sender. |

The three demo commands ran under `firebase.cmd --config <temporary-config> emulators:exec --only auth,firestore --project demo-foreseeme`, with Firestore on loopback port 18380 and Auth on port 19299. The temporary configuration was removed. The full Flutter test command compiled the changed Dart modules. This pass did not run a signed release build or physical-device tests.

## FCM ownership verification

The server-owned FCM lifecycle was implemented on clean `main` at `3ff200c529624b9355e23efa4e96b95b123bb428`. See the [implementation report](MODULE_9_SECURITY_IMPLEMENTATION_REPORT.md#server-owned-push-registration) for API and storage details. The following results are from this FCM change. The later sections retain the earlier Module 9 evidence.

| Check | Observed result |
| --- | --- |
| Flutter alerts, auth, disclaimer, medication and host integration regressions | 350 passed, two golden suites skipped by `dart_test.yaml`, zero failed. |
| Final focused Flutter registration, push handling and logout rerun | 22 passed, zero failed or skipped. |
| Flutter analyzer | No issues on the final run. |
| Backend registry, admin API, inference auth, dispatch, dispatch deployment, weekly, pipeline, targeting, messaging, disclaimer and observability suites | 219 passed, zero failed or skipped. The installed Starlette TestClient emitted an HTTPX deprecation warning. |
| Ruff error-class check on backend app, tests and scripts | Passed. |
| Firestore rules on `demo-foreseeme` | 101 passed, zero failed. Includes direct registry denial, owner-only inbox lookup, existing revocation checks, and mark-read on both old and new inbox records. |
| Paired Auth and Firestore emulator API suite | Three passed, including reassignment, stale registration rejection, delayed unregister and stale pruning with synthetic registration values. |
| Emulator dispatch smoke | Passed with a recording sender. Verified neutral copy, durable inbox linkage and rerun idempotency. No live FCM message was sent. |

Earlier validation attempts exposed inactive Flutter test subscriptions, an incorrect observability fixture, and an inbox schema check that needed the new server-owned reference. The first analyzer run flagged two missing brace blocks. Those issues were corrected. The rules suite also exposed a mark-read regression when the server reference was present. The updated rule requires the field and its presence to stay equal to the stored document. A default emulator port conflict was resolved with temporary loopback ports. No emulator configuration change is included.

### Remaining staging and device evidence

- Verify authentication and registration on signed Android and iOS builds using the intended staging API and rule set. Cover install, upgrade, app resume, denied permission, refresh, and two devices per user.
- Exercise A to B switching, offline logout, delayed unregister and provider delivery after the switch. Check lock-screen, foreground, background and terminated displays and taps for both risk and weekly notifications. A queued notification must show the approved neutral text. An old tap must not access a different account's content.
- Confirm both job images are registry-only before cutover, measure re-enrollment, verify Firebase IAM and ingress, and agree a rollback that pauses push if necessary. No legacy records were migrated or deleted by this task.
- Test medication reminder lock-screen content and outstanding schedules separately under Module 2. This FCM change does not close native Auth storage, certificate pinning, or release privacy sign-off.

## A. Verification summary

**Ready for staging verification.** The baseline was `main` at `3ac3b5dfa007b494424ca2d60efaf7ac4b0d06ec` with the previous Module 9 implementation still uncommitted. Final consolidation preserved the implementation and specification and corrected the Flutter test dependency and fixtures. Android secure storage, production pinning, and staging and production verification remain open.

The specified [SDS transcription](<ForeSeeMe SDS final(SP23-BSE-034 & 040).docx.md>) defines encryption, medication ownership and minimization in the Module 9 feature overview (line 471). Table 2.21 and §2.7.4 add HTTPS, session security, disclaimer acceptance, password hashing, backend-only inference, MFA and privacy (lines 1014–1063). §4.3 and Table 4.8 specify native secure storage and production certificate pinning (lines 1585–1626). SDK-managed Android persistence and ordinary HTTPS leave those two design commitments open.

The two targeted backend runs verified **83 distinct passing cases** after removing overlap. The 725-pass backend and ML result is prior evidence from the [implementation report](MODULE_9_SECURITY_IMPLEMENTATION_REPORT.md). This pass changed no application source, so another full run was unnecessary.

### Final consolidation

The final release review retained the previous 83 backend cases and the transport and platform evidence for the unchanged implementation. The first sandboxed Flutter and emulator attempts reproduced the lockfile and loopback failures. With permission to run the local emulator, `firebase.cmd emulators:exec --only firestore --project demo-foreseeme 'node test_rules/firestore_rules.test.mjs'` reached the test runner and **all 90 rule checks passed**, with no failures or skips. The demo results cover owner isolation, protected writes, acceptance ownership, and cutoff enforcement for users and MFA administrators. They do not establish deployed-rule parity. Backend Module 8 claim, MFA, recent-authentication, live-role and stale-session evidence remains valid.

The two paired Auth and Firestore tests passed on the demo project after an initial port conflict. The existing Firebase configuration was copied temporarily with Firestore on 18180 and Auth on 19099. The target was `python -m pytest -q backend/tests/test_admin_emulator.py` under `firebase.cmd --config $config emulators:exec --only auth,firestore --project demo-foreseeme`. This covered `test_admin_workflow` and `test_invitation_uses_firebase_password_reset_and_can_retry`. No configuration from the retry is included in the release.

The authorized Flutter run exposed an incompatible `fake_cloud_firestore 4.1.1` batch signature against `cloud_firestore 6.10.2`. Raising the dev dependency minimum to `^4.2.0` and running `flutter.bat pub upgrade --offline fake_cloud_firestore` resolved the cached 4.4.0 and allowed the target suites to compile. The next run passed 11 cases and identified three disclaimer fixture timeouts. The fixtures now use committed auth/profile overrides or keep the switching stream subscribed. The six-case disclaimer suite passed after that correction. The evidence covers **14 distinct Flutter tests** across consent, logout, session transport, notification UI and router navigation. Three of the six disclaimer cases also passed in the earlier run.

```powershell
flutter.bat test --no-pub --reporter expanded test/features/health_profile/disclaimer_acceptance_test.dart test/features/auth/firebase_auth_logout_test.dart test/features/auth/session_api_client_test.dart test/features/alerts/alerts_test.dart test/features/disease_explorer/disease_navigation_test.dart --name 'dashboard|acceptance|local cleanup|session service|bearer|NotificationPermissionScreen|actual router'
flutter.bat test --no-pub --reporter expanded test/features/health_profile/disclaimer_acceptance_test.dart
flutter.bat build apk --debug --no-pub
```

The Android debug APK build succeeded after Gradle's Kotlin compiler fallback for the cross-drive incremental cache. The APK is a local build artifact. The iOS build and on-device staging rehearsals remain open.

The final consolidation updates the Module 9 implementation report, this evidence report, the privacy draft, and the [Module 8 traceability record](MODULE_8_FINALIZATION.md#verification-and-traceability). The [historical RTM extract](../evaluation_60/output/evidence/Report_RTM_Extract.txt) is retained as an earlier evaluation snapshot. Use the matrix below for current Module 9 evidence and the Module 8 traceability record for current Module 8 evidence.

## B. Focused test results

### Backend

Python 3.13.7 and pytest 9.0.3 on Windows. The in-process Starlette tests used the temporary selector driver below because the sandbox denies the default asyncio loopback wakeup. The driver left security assertions, JWT verification, and networking restrictions intact.

| Run | Selected groups | Passed | Failed | Skipped |
| --- | --- | ---: | ---: | ---: |
| B1 | Existing inference (11), validation boundaries (11), stub models (5), risk and weekly messaging (29), and admin/session API (19) | 75 | 0 | 0 |
| B2 | Inference including the new authorized clinical-field case (12), admin/session API including cutoff and current-role cases (24), and scheduled model parity (2) | 38 | 0 | 0 |

```powershell
$driver | python - -vv -rs backend/tests/test_inference_auth.py backend/tests/test_api_validation_boundary.py backend/tests/test_predict.py backend/tests/test_messaging.py backend/tests/test_push_disclaimer.py backend/tests/test_weekly_report.py backend/tests/test_admin_api.py
$driver | python - -vv -rs backend/tests/test_inference_auth.py backend/tests/test_admin_api.py backend/tests/test_compute_risk.py::test_batch_job_uses_the_same_classify_dominant_function_as_serving backend/tests/test_compute_risk.py::test_serving_and_batch_paths_agree_given_equivalent_single_point_input
```

| Exact test name or parameter ID | Result |
| --- | --- |
| `test_credentials_required[headers0]`, `[headers1]` | Missing and malformed credentials each returned 401. |
| `test_inference_identity[changes0-401]` through `[changes4-401]` | Expired, forged, wrong-audience, wrong-issuer, and synthetic ordinary Firebase identities were rejected in order. |
| `test_inference_identity[changes5-403]`, `[changes6-200]` | Untrusted subject denied. Authorized subject received a valid prediction. Rejected identities returned generic bodies without reflecting credentials or input. |
| `test_authorized_inference_rejects_clinical_fields_without_echo`, `test_unexpected_clinical_fields_are_rejected_without_echo` | Unexpected clinical input returned 422 without exposing its name or value. |
| `test_cleartext_is_denied_even_with_valid_token`, `test_missing_configuration_fails_closed` | Cleartext rejected and missing identity configuration failed closed. |
| `test_predict_valid_returns_contract_body`, `test_batch_job_uses_the_same_classify_dominant_function_as_serving`, `test_serving_and_batch_paths_agree_given_equivalent_single_point_input` | Prediction contract and in-process batch parity passed. |
| `test_risk_push_preserves_content_and_includes_disclaimer`, `test_common_fcm_payload_carries_disclaimer_without_platform_overrides`, `test_compose_weekly_is_cited_and_non_diagnostic` | Risk, changed recommendation, and weekly push content preserved the disclaimer. Delivery used synthetic FCM responses. |
| `test_send_generic_failure_exhausts_retries_and_redacts_provider_error` | Existing retry behavior passed and raw provider errors stayed out of returned errors and logs. |
| `test_session_logout_derives_uid_from_verified_token`, `test_session_logout_fails_when_cutoff_is_unconfirmed`, `test_session_logout_rejects_missing_or_revoked_credentials` | Verified UID controls refresh-token revocation and cutoff even when the body supplies another UID. Commit uncertainty returned 503. Missing and revoked credentials were denied. |
| `test_admin_authorize_enforces_cutoff_and_live_role[active-totp-session]`, `[new-phone-session]`, `[at-cutoff]`, `[before-cutoff]`, `[live-role-removed]` | Active and newer sessions passed. At-cutoff, stale and removed-role sessions were denied. |

Flutter's `FirestoreRiskRepository` reads `riskEstimates`. Inspection found no direct Flutter inference request or embedded service-account private key in the client source and packaged asset paths searched.

### Earlier Flutter runtime and build attempts

```powershell
flutter.bat test --no-pub test/features/health_profile/disclaimer_acceptance_test.dart test/features/auth/firebase_auth_logout_test.dart test/features/auth/session_api_client_test.dart test/features/alerts/alerts_test.dart test/features/disease_explorer/disease_navigation_test.dart --name 'dashboard|acceptance|logout|session service|bearer|NotificationPermissionScreen|actual router'
```

The Windows batch launcher did not complete. Direct invocation of the installed Flutter snapshot with the same arguments exited 1 before collection with `Flutter failed to open a file at "C:\flutter\bin\cache\lockfile".` Automatic permission review timed out. The post-edit snapshot attempt with `test --no-pub test/features/health_profile/disclaimer_acceptance_test.dart --name 'acceptance|dashboard'` hit the same lockfile error. **Zero Flutter tests executed.** There are zero test-level passes, failures, or skips.

The test source covers first-time dashboard denial, current-version acceptance, owner isolation, fresh-container reads, account switching, pending or failed writes, direct navigation, and the notification permission dismissal. A fresh container over fake Firestore is a test of provider restoration, while physical restart and production Firebase behavior remain unverified. Source inspection confirms local Firebase and Google cleanup is attempted even if the remote call fails, with an unconfirmed logout message. The selected runtime logout, navigation, and notification tests did not run.

The installed snapshot's `build apk --debug --no-pub` returned the same lockfile error. No APK was built. iOS compilation requires a macOS and Xcode runner.

Static analysis of the changed Flutter test passed via `dart --suppress-analytics analyze --fatal-infos test/features/health_profile/disclaimer_acceptance_test.dart`. Targeted Python lint passed via `python -m ruff check backend/tests/test_inference_auth.py backend/tests/test_admin_api.py --select E9,F63,F7,F82`. `git diff --check` passed. These checks do not contribute to runtime test counts.

### HTTPS

| Command and selection | Passed | Failed | Skipped | Result |
| --- | ---: | ---: | ---: | --- |
| `dart.exe --enable-asserts "--packages=$packages" $probe` with `.dart_tool/package_config.json` | 5 | 0 | 0 | The standalone Dart probe reused the existing session-client test contract with MockClient. It rejected missing URL, HTTP, URL credentials and redirect downgrade, and verified the expected HTTPS bearer POST. |
| `python -` using `xml.etree.ElementTree` and `plistlib` | 2 | 0 | 0 | Android manifest variants have cleartext disabled in main with no debug or profile override. iOS ATS contains only `NSAllowsArbitraryLoads=false`. |

These are application and source checks. The debug APK was built during final consolidation. Production ingress and release artifacts remain unverified. The approved production host list, backup SPKIs, and rotation and recovery plan are still required for pinning.

## C. FR/NFR status matrix

| Requirement | Previous status | New verification result | Remaining blocker |
| --- | --- | --- | --- |
| FR9.1 | Partially verified | Source confirms Firestore is the system of record for profiles, medications and adherence. Default server encryption is prior platform evidence. | Verify the live database, encryption mode, backups, exports and device caches. |
| FR9.2 | Emulator unverified | All 90 demo rule checks passed, including ownership, protected writes, consent, session and MFA. | Verify deployed rule parity. |
| FR9.3 | Partially verified | Authorized inference rejects clinical fields without echo. Demo rules enforce permitted profile fields and categories. | Review legacy data. Future clinical collection still requires specific informed consent. |
| FR9.4 | Application checks passed | Client transport, protected inference HTTP rejection, manifest and ATS checks, and the Android debug build passed. | Release artifact verification, deployed ingress and pinning inputs. |
| FR9.5 | Partial | Backend revocation, cutoff and live-role checks passed. Flutter cleanup tests passed, and demo rules denied stale user and administrator sessions. Native storage gap confirmed. | Approved Android storage resolution and two-device staging. |
| FR9.6 | Partially verified | Risk and weekly push tests passed. Flutter consent, persistence, pending-write, account-switch and navigation cases passed. | Device staging for restart, version upgrade and push display. |
| NFR-S1 | Partially verified | Firebase Authentication integration inspected. The SDS names bcrypt. Prior official evidence documents modified SCRYPT as the default. | Verify the project algorithm label and migration history, then approve any wording change. |
| NFR-S2 | Backend tests passed | Signed inference tests and in-process scheduled parity passed. Flutter reads Firestore risk estimates. | Verify live Cloud Run IAM and configured service identity if inference is deployed. |
| NFR-S3 | Locally implemented | API claim, MFA, recent authentication, live-role removal and cutoff passed. Demo rules and paired Auth/Firestore integration passed. | Staged MFA enrollment and recovery rehearsal and deployed rule parity. |
| NFR-S4 | Privacy draft available | Reviewed the existing data inventory and processor handling decisions against the SDS. | Organizational sign-off and qualified Pakistani legal review. |

## D. Android token storage

`pubspec.lock` resolves `firebase_auth 6.7.1` and `firebase_auth_platform_interface 9.1.0`. Inspection of the cached `firebase-auth-24.1.0.aar` shows the Android SDK uses private-mode `SharedPreferences` and `getString` and `putString` for its token records. The serializer writes JSON fields named `refresh_token` and `access_token`. The inspection used SDK bytecode and did not read device credentials. Android app-private storage restricts ordinary cross-app access. Section 4.3.3 and Table 4.8 require stronger application storage than the observed SDK persistence.

The installed FlutterFire method channel throws `UnimplementedError` for native `setPersistence`. The app uses `Persistence.NONE` on web, and no second application-owned token store was found. Copying tokens to encrypted storage would leave the native SDK copy in place. No approved amendment was identified in the repository. The proposed alternative is to accept SDK-managed private persistence through a written SRS/SDS amendment approved by the supervisor or instructor. Until that decision is recorded, the current requirement wording stands and FR9.5 remains partial. Meeting the existing text requires a supported native persistence design and architecture approval. [Firebase Auth persistence](https://firebase.google.com/docs/auth/flutter/start)

Refresh-token revocation uses Firebase Auth. The separate monotonic `sessionRevocations` cutoff protects paths whose rule or API checks compare `auth_time`. The backend denies claims at or before the cutoff and accepts a later valid authentication time. Device caches and managed endpoints without a cutoff check do not gain immediate invalidation from this mechanism. No authorized two-device staging run was available. [Firebase session revocation](https://firebase.google.com/docs/auth/admin/manage-sessions)

## E. Firestore emulator

Node 24.20.0, Firebase CLI 14.25.1, JDK 21.0.2 and cached Firestore emulator 1.19.8 were present. The local config uses ports 8080 and 9099. No conflicting listener was observed on the inspected ports. A loopback bind succeeded and the connection failed with `WinError 10013`. Direct startup of the existing JAR failed with `Unable to establish loopback connection` and `Permission denied: connect`. Automatic permission review timed out on the controlled CLI attempt.

```powershell
& 'C:/Program Files/Java/jdk-21/bin/java.exe' -jar 'C:/Users/HP/.cache/firebase/emulators/cloud-firestore-emulator-v1.19.8.jar' --host 127.0.0.1 --port 8080 --project_id demo-foreseeme
$env:CI = 'true'
$env:JAVA_HOME = 'C:/Program Files/Java/jdk-21'
firebase.cmd emulators:exec --only firestore --project demo-foreseeme 'node test_rules/firestore_rules.test.mjs'
```

The earlier closure pass executed **0 of 90** checks. The final consolidation used the same demo project and runner after obtaining local loopback access. It executed **90 of 90 checks, all passing**. Expected permission-denied responses are part of the negative tests. The script covers owner, medication, adherence, risk write, consent, cutoff and MFA cases.

## F. Module 8 regression assurance

| Existing control | Result |
| --- | --- |
| Custom claim validation | Backend denied a missing or removed role. |
| Admin MFA | Backend denied single-factor claims. |
| Phone and TOTP | Both factor claims passed backend tests. Flutter handling was present on inspection. |
| Role and recent authentication | Recent authentication bounds and the live role lookup passed. |
| Firestore admin restrictions | Demo rules accepted intended MFA reads and denied missing MFA, stale tokens, and client-forged privileged writes. |
| Role removal and stale tokens | Backend denied stale sessions and removed roles. The existing operator script records the cutoff. Production role removal remains unexercised. |

## G. Files changed during this pass

| File | Change |
| --- | --- |
| `backend/tests/test_inference_auth.py` | Checks generic authentication error bodies and rejects clinical fields with an authorized signed request. |
| `backend/tests/test_admin_api.py` | Exercises the actual authorization dependency across cutoff, valid factor and current-role boundaries. |
| `test/features/health_profile/disclaimer_acceptance_test.dart` | Adds fresh-container recovery, account switching and pending-write assertions. Corrects the fixtures after reproducing timeouts. All six cases passed. |
| `docs/MODULE_9_VERIFICATION_AND_CLOSURE_REPORT.md` | Records SDS comparison, test results, and remaining work. |

Final consolidation also updated `pubspec.yaml` for the compatible test fake and refreshed the implementation, Module 8 traceability, and privacy draft documents. The local lockfile follows the repository's existing ignore policy. Application security source and rules were unchanged from the focused verification baseline.

## H. Remaining closure tasks

- **Repository** — Resolve the Android native storage requirement and production pinning design before claiming both requirements are satisfied.
- **Local environment** — Build iOS on macOS. The targeted Flutter tests, Android debug build, Firestore rules and paired demo smoke tests were completed during final consolidation.
- **Staging** — Verify acceptance, restart, account change, version change and push display. Rehearse two-device logout, fresh sign-in, and admin MFA enrollment and recovery with authorized test accounts.
- **Production verification** — Confirm Firebase encryption, backups, rule parity and password algorithm label. Verify Cloud Run IAM, identity and HTTPS ingress. Obtain approved pins and rotation and recovery details.
- **Human and legal approval** — Decide whether the SDS may accept SDK-managed Android persistence, resolve hashing wording, and review processor sharing, retention and deletion.

## I. Readiness verdict

**Ready for staging verification.** Targeted Flutter and backend checks and the Firebase demo suites support the local security implementation. The Android storage and production pinning commitments remain open under the current SDS. The debug APK and emulator evidence do not establish production readiness.

### Windows selector driver

Define this temporary PowerShell variable before running the backend commands in §B:

```powershell
$driver = @'
import asyncio, selectors, time, pytest, sys
class LocalSelector(selectors.SelectSelector):
    def select(self, timeout=None):
        if self.get_map():
            return super().select(timeout)
        if timeout:
            time.sleep(min(timeout, .01))
        return []
class LocalLoop(asyncio.SelectorEventLoop):
    def __init__(self):
        super().__init__(LocalSelector())
    def _make_self_pipe(self):
        self._ssock = self._csock = None
    def _close_self_pipe(self):
        pass
    def _write_to_self(self):
        pass
    def _run_once(self):
        self.call_later(.01, lambda: None)
        super()._run_once()
class LocalPolicy(asyncio.WindowsSelectorEventLoopPolicy):
    _loop_factory = LocalLoop
asyncio.set_event_loop_policy(LocalPolicy())
raise SystemExit(pytest.main(sys.argv[1:]))
'@
```
