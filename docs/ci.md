# Continuous Integration (Sprint 5, Prompt 14)

*"CI-quality code" becomes an enforced control: no PR merges with failing analyze
or tests, on either stack.*

The pipeline is defined in [`.github/workflows/ci.yml`](../.github/workflows/ci.yml)
and runs on every **pull request** and on **pushes to `main`**. It is two
independent, parallel jobs.

## What runs

### `flutter` job (Ubuntu)
| Step | Command | Gate |
|---|---|---|
| Setup | `subosito/flutter-action@v2` → Flutter **3.44.4** stable (cached) | — |
| Deps | `flutter pub get` | — |
| Analyze | `flutter analyze` | fails on any analyzer issue |
| Test | `flutter test` | fails on any failing test |

### `backend` job (Ubuntu, `working-directory: backend`)
| Step | Command | Gate |
|---|---|---|
| Setup | `actions/setup-python@v5` → Python **3.12** (matches the Dockerfile), pip cached | — |
| Deps | `pip install -r requirements.txt` + `pip install ruff==0.15.20` | — |
| Lint | `ruff check app ml scripts tests --select E9,F63,F7,F82` | fails on real defects |
| Test | `pytest -q` | fails on any failing test |

## Design choices

- **Error-level lint, not style churn.** Ruff runs the pyflakes/pycodestyle
  *error* classes only (`E9` syntax/runtime, `F63` broken comparisons/asserts,
  `F7` misplaced statements, `F82` undefined names) — the classic "does it have
  real bugs" gate. This keeps the gate **green on the current clean code** while
  catching genuine regressions; broader style rules can be layered in later
  without changing the contract. Ruff is a CI-only tool (pinned in the workflow),
  **not** a project/runtime dependency, so `requirements.txt` is untouched.
- **Pinned toolchains.** Flutter `3.44.4` and Python `3.12` match local dev and
  the runtime image, so CI reproduces developer results.
- **No secrets.** The workflow references no secrets, tokens, or credentials —
  every check runs on public toolchains against the checked-in source and the
  committed model artifact (`backend/ml/artifacts/`). `permissions: contents: read`
  is least-privilege.
- **Parallel + cancel-in-progress.** The two jobs run concurrently; a newer commit
  on the same ref cancels superseded runs.

## Reproduce locally

```bash
# Flutter
flutter pub get
flutter analyze
flutter test

# Backend
cd backend
pip install -r requirements.txt
pip install ruff==0.15.20
ruff check app ml scripts tests --select E9,F63,F7,F82
pytest -q
```

## Verification (green on clean, red on regression)

The gate was validated with the exact commands it runs:

- **Green:** `flutter analyze` → *No issues found*; `flutter test` → all pass;
  `ruff check … --select E9,F63,F7,F82` → *All checks passed*; `pytest` → all pass.
- **Red:** an undefined name makes ruff exit non-zero (`F821`), and a failing
  assertion makes `pytest` exit non-zero — either fails its job, blocking the PR.

To enforce "no merge with a red pipeline," enable branch protection on `main`
requiring the **`Flutter — analyze + test`** and **`Backend — lint + pytest`**
status checks (Settings → Branches → Branch protection rules). The workflow
provides the checks; branch protection is the merge gate.

## Not in this gate (deliberately)

- **Firestore rules tests** (`test_rules/`, emulator + Node) run separately — they
  need the Firebase emulator + Java and are kept out of the merge gate to avoid
  flakiness (audit note: *stabilize before gating*). Run them manually with
  `npm --prefix test_rules test`.
- **Builds/deploys** (APK, Docker image) are out of scope for this analyze+test
  gate.
