# Fresh targeted rehearsal
Client date: 21 October 2026, America/Los_Angeles. These results overlap the retained full suites and are not added to their totals.

| Run | Passed | Failed | Skipped | Exit |
|---|---:|---:|---:|---:|
| Flutter dose boundaries + recovery widget files | 20 | 0 | 0 | 0 |
| Backend API validation file | 10 | 0 | 0 | 0 |

Flutter command from root: `flutter test --no-pub test/features/medication/dose_state_boundaries_test.dart test/features/auth/forgot_password_screen_test.dart --reporter json > evaluation_60/build/flutter-demo.jsonl`

Backend command from backend: `python -m pytest tests/test_api_validation_boundary.py -q --basetemp=../evaluation_60/build/pytest-demo-normal --junitxml=../evaluation_60/build/backend-demo.xml`

Backend pytest reported 10 passed, 1 TestClient/httpx deprecation warning in 4.21s. Flutter JSON reporter ended with success=true and 20 non-loading successful test records, about 58 seconds reporter elapsed time. Both exit codes were zero. There was no fresh full-suite run, native app test, live Firebase call or fresh model training.

An initial restricted backend attempt produced no completed report and was interrupted. Its failure cause was not independently established. The completed run used normal local IPC/filesystem access. Flutter used normal SDK cache access. No production code, test assertion or dependency configuration was changed to obtain these passes.
