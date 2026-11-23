# Continuous Integration (Sprint 5, Prompt 14)

*"CI-quality code" becomes an enforced control: no PR merges with failing analyze
or tests, on either stack.*

The pipeline is defined in [`.github/workflows/ci.yml`](../.github/workflows/ci.yml)
and runs on every **pull request** and on **pushes to `main`**. It is three
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
| Test | `pytest -q -rs` | fails on any failing test and reports skip reasons |

### `admin-emulators` job (Ubuntu)

Runs `npm --prefix test_rules test` and the Auth/Firestore integration suite
against the local `demo-foreseeme` project via `firebase emulators:exec`.

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
- **Parallel + cancel-in-progress.** The three jobs run concurrently; a newer commit
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
pytest -q -rs
```

### Frozen ML data checks

The committed model, split manifest and test fixtures are enough for the
offline suite. The manifest records the frozen dataset hashes and lineage. The
original acquisition data and parquet snapshots are excluded from the checkout,
so CI does not try to rebuild them from a fresh external download. The
artifact contract, training fingerprint, and train/serve checks exercise the
existing small test fixtures on every run.

Five additional cases require either the original held-out split or the original
labelled precursor and split. Those cases report a skip when the required input
is absent. Any split they do read must match its SHA-256 in the split manifest.
The historical parity checks still compare feature values and bind the
train/test fingerprints to the promoted model. To require all of this evidence,
place the original files at the paths below (under `backend/ml/data/` by default,
or the configured `FORESEEME_ML_DATA_DIR`) and run
`python -m pytest -q -rs --require-frozen-ml-data` from `backend/`.

- `processed/train.parquet` and `processed/test.parquet`
- `processed/split_manifest.json` from that same freeze
- `interim/weekly_labelled.parquet` from that same dataset generation

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

- **Builds/deploys** (APK, Docker image) are out of scope for this analyze+test
  gate.
