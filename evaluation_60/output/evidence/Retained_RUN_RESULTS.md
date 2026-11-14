# ForeSeeMe executable testing evidence

Evaluation date: 15 October 2026 (America/Los_Angeles client date).
Repository: `D:\FYP ForeSeeMe\fyp_foreseeme`; branch `main`.
Starting working tree: clean. No branch change, commit, push, stash, reset or clean.

## Final results

| Suite | Passed | Failed | Errors | Skipped | Exit code |
|---|---:|---:|---:|---:|---:|
| Flutter complete | 882 | 0 | 0 | 4 golden-suite placeholders | 0 |
| Backend complete | 666 | 0 | 0 | 0 | 0 |
| Targeted Flutter (overlaps full suite) | 20 | 0 | 0 | 0 | 0 |
| Targeted new backend (overlaps full suite) | 10 | 0 | 0 | 0 | 0 |

1,548 actual tests executed and passed across the complete suites. Flutter additionally emitted four skipped `(suite)` records for golden files: these are not a verified count of individual golden tests. 1,552 is the combined count of reported entries, including those four placeholders. Loading events are excluded. Targeted runs are not added to totals.

## New or extended test files

- `test/features/medication/dose_state_boundaries_test.dart`: nine new unit tests, FSM-U01 through FSM-U09. Exact action/grace boundaries, completed/skip interpretation, leap-day history, midnight future-day guard.
- `test/features/auth/forgot_password_screen_test.dart`: three new widget cases (FSM-W01-light, FSM-W01-dark, FSM-W02); original eight cases retained. Controlled Completer in fake repository; validation correction, trimming, themes, in-flight keyboard resubmission and network error recovery.
- `backend/tests/test_api_validation_boundary.py`: ten new cases, FSM-B01 through FSM-B10. Parameter IDs identify most cases; FSM-B08 appears as test_FSM_B08_malformed_json_never_reaches_inference. Checks HTTP errors AND zero inference calls; positive boundaries prove one unchanged call through the route.

No production file or dependency configuration changed.

## Exact final test commands (PowerShell)

Working directory: repository root.

```powershell
flutter test --no-pub --reporter json *> test_artifacts/chapter5/flutter-final.jsonl
```

Working directory: repository `backend` directory.

```powershell
python -m pytest -q --basetemp=../test_artifacts/chapter5/pytest-verified-temp --junitxml=../test_artifacts/chapter5/backend-verified.xml *> ../test_artifacts/chapter5/backend-verified.log
```

The shell captured `$LASTEXITCODE`: both were 0. The backend console summary was `666 passed, 1 warning in 223.26s (0:03:43)`; JUnit records 223.173 seconds. The warning is FastAPI/Starlette's TestClient deprecation concerning httpx. No requirement latency benchmark was performed.

Exact targeted commands:

```powershell
# repository root
flutter test --no-pub test/features/medication/dose_state_boundaries_test.dart test/features/auth/forgot_password_screen_test.dart --reporter json *> test_artifacts/chapter5/flutter-added.jsonl
# backend directory
python -m pytest tests/test_api_validation_boundary.py -q --basetemp=../test_artifacts/chapter5/pytest-added-unrestricted --junitxml=../test_artifacts/chapter5/backend-added-verified.xml *> ../test_artifacts/chapter5/backend-added-verified.log
```

Both exited 0. Targeted backend: `10 passed, 1 warning in 9.05s`.

## Earlier diagnostic attempts

- Root: `flutter test --no-pub --reporter json *> test_artifacts/chapter5/flutter-baseline.jsonl`: exit 0. Intermediate run (873 passed entries, 4 skipped suite entries); it overlapped authoring and is not used to calculate a before/after contribution count.
- Backend: `python -m pytest -q --junitxml=../test_artifacts/chapter5/backend-baseline.xml *> ../test_artifacts/chapter5/backend-baseline.log`: sandboxed attempt interrupted; shell exit 1, incomplete progress showed E and F indicators, no completed JUnit report. No reliable final test counts.
- Backend: `python -m pytest tests/test_api_validation_boundary.py -q --junitxml=../test_artifacts/chapter5/backend-added.xml *> ../test_artifacts/chapter5/backend-added.log`: interrupted after stalling; exit 1, no completed result.
- Backend: `python -m pytest tests/test_api.py::test_health_reports_model_loaded -x -q --tb=short *> ../test_artifacts/chapter5/backend-diagnostic.log`: interrupted after stalling; exit 1, no completed result.
- Root: `python -m pytest backend/tests/test_api_validation_boundary.py -q --basetemp=test_artifacts/chapter5/pytest-added-temp --junitxml=test_artifacts/chapter5/backend-added.xml *> test_artifacts/chapter5/backend-added.log`, with TMP/TEMP redirected to task evidence folder: interrupted after stalling; exit 1. No completed result. This superseded the previous incomplete targeted log at the same path.
- Backend: `python -m pytest -q --basetemp=../test_artifacts/chapter5/pytest-final-temp --junitxml=../test_artifacts/chapter5/backend-final.xml *> ../test_artifacts/chapter5/backend-final.log`, with TMP/TEMP redirected: interrupted to avoid duplicate full runs; exit 1; no completed result.
- Backend: `python -m pytest --collect-only -q *> ../test_artifacts/chapter5/backend-collection.log`: exit 0; 666 collected. Collection does not count as execution.

The first Flutter SDK attempts could not access `C:\flutter\bin\cache\lockfile` under the workspace sandbox. The completed Flutter runs used normal SDK cache access. The final backend used normal filesystem permissions. The failure cause of every interrupted backend attempt was not independently established; they are environment-affected incomplete runs, not resolved production defects. No assertion was weakened in response.

## Environment and prerequisites

Observed: Windows 11 build 26300.9711; Flutter 3.44.4 stable; Dart 3.12.2; Python 3.13.7; pytest 9.0.3; FastAPI 0.138.1; Pydantic 2.13.4; pandas 2.3.3; NumPy 2.3.5; scikit-learn 1.7.2. Flutter app version 1.0.0+1. Project CI uses Python 3.12 and requirements pin pytest 8.3.4: local version drift is disclosed rather than represented as a CI run.

Discovery commands actually executed: `flutter --version`, direct bundled Dart `--version`, `python -m pytest --version`, `flutter devices --machine`, `flutter emulators`, `flutter doctor -v`. Device and doctor output retained. Windows/Chrome/Edge are visible; Android emulator definition Medium_Phone_API_36.1 exists but is not running. Android licences incomplete, Visual Studio C++ missing; no integration_test dependency configured. Device end-to-end suite not implemented or executed. Existing test/integration files run as host widget/provider integration tests and pass.

A fresh evaluator should use the CI toolchain, run `flutter pub get`, create an isolated Python environment and install `backend/requirements.txt`, then run the suites. These installation commands are reproducibility instructions, not claimed executions in this task. Retained backend ML datasets/model artifact are required. For an exact repetition, choose a fresh writable basetemp directory to avoid pytest clearing a previous evidence folder. Ordinary tests do not require production Firebase credentials or live user accounts.

## Documentation QA

The separate SDS changes only Chapter 5 and necessary Chapter 5 TOC labels/field update metadata. Chapters outside the allowed replacement range and all other package parts are verified unchanged. Source hashes are in source_hashes.json; structural results in document-verification.json. TOC field caches need refresh in Word for current pagination and new subsection entries; updateFields is set. Do not infer refreshed cached TOC numbers from the preserved source cache.

The official template has a pre-existing CRC error in word/media/image62.jpeg. Its XML chapter structure was readable; no template image was reused. The source SDS ZIP is intact. The packaged render_docx.py was attempted and failed because the dependency runtime contains no LibreOffice. Installed Word read-only PDF export is used as a fallback for layout QA. The source SDS was not saved through Word. Render intermediates are QA files, not deliverables or test execution screenshots.

The report uses original project-specific prose. No external explanatory text was copied and no plagiarism-detector result is claimed. No new manual application checks, Firestore security-rule emulator run, live email/push delivery, load benchmark or scientific disease-forecast validation is claimed.

Final visual review: Word exported 125 pages; revised Chapter 5 spans PDF pages 112-123 (printed pages 111-122). All 12 affected page PNGs were inspected at native size; no clipping, overlap or broken table layout observed. Unchanged chapters were verified structurally, not re-edited. See visual-qa.json for final-file hash and exact review scope.
