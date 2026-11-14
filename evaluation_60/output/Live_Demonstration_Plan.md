# Live demonstration plan
Evaluation: 23 October 2026. Haseeb owns the application walkthrough; Saim owns executable testing and requirement traceability.

## Preparation before entering the room

1. Keep the repository, PowerPoint, supplied report §5.5.5, model card and test source open. Keep a local copy of evidence/ available offline.
2. Use a dedicated demo account and synthetic medication/profile records. Sign in ahead of time, retain a known supported city and note the timestamps on stored risk estimates.
3. Install/launch the app on the chosen device. Check internet, Firebase access, map configuration and permissions. A configured emulator is not proof of a booted working device.
4. Use Flutter 3.44.4 with resolved dependencies. CI backend baseline is Python 3.12 with backend/requirements.txt. Recorded local tests used Python 3.13.7 / pytest 9.0.3. Use the tested local environment for the rehearsal or separately verify a clean pinned environment before evaluation.
5. Run `flutter pub get` and install Python dependencies in an isolated environment before the event, not during the presentation. Retain ML model/data fixtures for the full backend suite.
6. Rehearse `Run-Demo-Tests.ps1`. It writes timestamped logs without changing assertions or historical reports. The selected tests do not need live production Firebase credentials.
7. Do not promise hardware FCM or native medication alarms unless the team has verified them before the evaluation. Billing, cloud execution and real delivery remain documented release gates.

## Suggested sequence, approximately 8–10 minutes

| Presenter | Step | Observable result | If it fails |
|---|---|---|---|
| Haseeb | Show sign-in and saved profile/city | User-scoped profile and navigation | Explain the affected authentication/network boundary; show report-captured screen and source. Do not call that a live pass |
| Haseeb | Open medication and daily check-in | Saved schedule, time slots and dose state | Show state engine and real boundary tests. Do not claim persistence if the write failed |
| Haseeb | Open risk map/details | Supported city, risk level, confidence, timestamp, explanation | Disclose stored/seeded/stale data. Explain Firestore risk path and show report screen |
| Haseeb | Open resources and profile preferences | Controlled content and application navigation | Explain repository versus external place-service boundary |
| Saim | Run Flutter dose and recovery files | 20 selected tests should pass in the rehearsed checkout | Keep failed output, identify assertion/environment issue, show retained evidence with date |
| Saim | Run backend API validation file | 10 named cases should pass | Disclose failure, retain report and explain schema/inference seam |
| Saim | Trace FR1.7 or FR6.6 | Official clause, exact test name, assertion and result | State any unmatched clause rather than borrowing an unrelated pass |
| Both | Explain pending release gate | Clear boundary between local code and deployed/device behavior | Use the limitations slide and answer directly |

The 21 October rehearsal completed 20 Flutter cases and 10 API cases, zero failures. Flutter took about 58 seconds of reporter elapsed time; backend pytest reported 4.21 seconds. Times are observations, not latency requirements or guarantees.

## Commands

From repository root:

```powershell
flutter test --no-pub test/features/medication/dose_state_boundaries_test.dart test/features/auth/forgot_password_screen_test.dart --reporter expanded
```

From backend:

```powershell
python -m pytest tests/test_api_validation_boundary.py -q
```

For the provided runner from repository root:

```powershell
& ./evaluation_60/output/Run-Demo-Tests.ps1
```

The runner accepts `-RepositoryRoot` if moved. It executes the existing test files and stores output under evaluation_60/demo_runs. It does not provision cloud resources.

Optional backend control-logic demonstration, only after separately rehearsing:

```powershell
python -m pytest tests/test_e2e_pipeline.py::test_repeated_runs_produce_no_spam -q
```

That test uses controlled dependencies. It is not a live FCM device test, and no new execution of it is claimed in this presentation task.

## Full regression before evaluation

Run `flutter test --no-pub --reporter json` from root and `python -m pytest -q` from backend. Capture exit codes, tool versions, timestamp and new reports. Use a new writable pytest temporary directory. Full backend tests require retained datasets/artifacts. Do not add targeted results to full-suite counts.

## Failure explanation

State what failed, where the boundary lies and what the retained evidence does prove. Never replace a failure with a hard-coded success response or imply that a report screenshot is live. The first restricted API attempt in this preparation stalled without final output and was interrupted. The subsequent normal-local-IPC run passed all ten cases. The cause of every earlier historical interruption is not established. Preserve this distinction if asked about environment behavior.
