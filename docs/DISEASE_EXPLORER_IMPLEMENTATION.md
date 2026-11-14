# Disease Explorer implementation and verification

## Audit and scope

The resumed working tree already contained the Disease Explorer implementation,
its additive backend payload, route, Risk Map entry point, schema documentation,
and focused tests. These were audited and reused rather than duplicated.
Unrelated pre-existing changes were preserved, including the raw-data manifest,
deleted `claude.md`, authentication and medication tests, and `evaluation_60/`.

The audit covered the existing palette, tokens, theme, surface and motion helpers;
router and shell; Dashboard, Risk Map, Compare and Risk Details; risk model,
repository, providers and comparison service; supported cities; compute job,
serving classification, schemas and explanations; training/evaluation code,
model configuration, metrics and risk-schema documentation.

The local serving artifact is `model_1.0.0.joblib`, version `rf-1.0.0`. All three
disease pipelines contain imputation, scaling and a Random Forest. Their actual
class order is `[High, Low, Medium]`. The artifact has no threshold metadata and
uses the existing 0.55 fallback. Influenza sigmoid recalibration in the evaluation
report is an experiment, not a component of this serving bundle.

## Result

- `/disease-explorer` presents independent Dengue, Smog and Influenza estimates
  for the five existing supported cities. One Risk Map action opens the route
  and carries its selected city. Compare remains a separate route.
- The screen uses existing ForeSeeMe colours, typography, glass surfaces and
  motion. It has an atmospheric painted sphere, differentiated disease accents,
  responsive cards, city selection and a scrollable detail sheet.
- Details expose validated model class probabilities, independent model
  contributors, cited existing guidance and genuine independent history.
- Missing predictions never become Low. Loading, empty, errors, offline/cache,
  stale and low-confidence states are explicit. Confidence is distinguished
  from infection probability throughout.
- The backend independently evaluates the existing models using the same feature
  row, maps probabilities through `classes_`, and adds `diseaseEstimates` to the
  existing daily Firestore document. Dominant summary selection is unchanged.
- Flutter composes existing repository-backed Riverpod providers; there is no
  second Firestore query implementation or prediction API call from the app.

## Completion changes in this resumed session

- Keep errors visible and Retry actionable while Riverpod retries automatically.
- Correct probability-progress semantics to use a valid numeric percentage.
- Grow history cells with text scaling instead of clipping them to a fixed height.
- Label cached independent history inside the detail sheet.
- Repair the navigation test's asynchronous initialization using synchronous
  authenticated fixtures; the real application router is still exercised.
- Test the actual five navigation callbacks using their icons, since the existing
  bar intentionally displays text only for its selected item.
- Separate deterministic manual-retry testing from default automatic-retry
  testing; both retain explicit error-state assertions.
- Add history text-scaling, cached-history and automatic-retry regression tests.
- Move optional PNG rasterization into the real event loop to avoid a fake-clock
  deadlock. Font-dependent PNG capture remains limited as described below.

## Feature files (including work inherited from the previous session)

Backend:

- `backend/app/disease_estimates.py`
- `backend/app/jobs/compute_risk.py`

Flutter:

- `lib/features/disease_explorer/domain/models/disease_risk_estimate.dart`
- `lib/features/disease_explorer/domain/services/disease_explorer_service.dart`
- `lib/features/disease_explorer/presentation/disease_explorer_providers.dart`
- `lib/features/disease_explorer/presentation/disease_explorer_screen.dart`
- `lib/features/disease_explorer/presentation/widgets/disease_hero.dart`
- `lib/features/disease_explorer/presentation/widgets/disease_risk_card.dart`
- `lib/features/disease_explorer/presentation/widgets/disease_detail_panel.dart`
- `lib/features/disease_explorer/presentation/widgets/disease_trend_chart.dart`
- `lib/features/risk/domain/models/risk_estimate_model.dart`
- `lib/features/risk/data/repositories/firestore_risk_repository.dart`
- `lib/core/routes/app_router.dart`
- `lib/features/risk/presentation/screens/risk_map_screen.dart`

Tests:

- `backend/tests/test_disease_estimates.py` (inherited; executed)
- `test/features/disease_explorer/fixtures.dart` (inherited)
- `test/features/disease_explorer/disease_data_test.dart` (inherited; executed)
- `test/features/disease_explorer/disease_navigation_test.dart` (repaired)
- `test/features/disease_explorer/disease_screen_test.dart` (extended and repaired)

Documentation:

- `docs/RISK_SCHEMA.md` (inherited additive contract)
- `docs/DISEASE_EXPLORER_IMPLEMENTATION.md` (this report)

## Focused verification commands

From `backend/`:

```powershell
python -m pytest tests/test_disease_estimates.py tests/test_compute_risk.py -q
```

Result: **34 passed, 0 failed**, 291.95 seconds. This includes real-artifact
independent outputs and explanations for all five cities, permuted class ordering,
invalid/missing outputs, dominant-summary parity, legacy response compatibility,
consistent computation metadata, document-size checks and daily/backfill
idempotency using fake repositories. No live Firestore writes occur.

From the repository root:

```powershell
flutter test --no-pub test/features/disease_explorer/
flutter test --no-pub test/features/risk/risk_estimate_model_test.dart test/features/risk/risk_comparison_service_test.dart test/features/risk/comparison_screen_test.dart
dart analyze lib/features/disease_explorer lib/features/risk/domain/models/risk_estimate_model.dart lib/features/risk/data/repositories/firestore_risk_repository.dart lib/core/routes/app_router.dart lib/features/risk/presentation/screens/risk_map_screen.dart test/features/disease_explorer
python -m ruff check backend/app/disease_estimates.py backend/app/jobs/compute_risk.py backend/tests/test_disease_estimates.py --select E9,F63,F7,F82
git diff --check
```

The model/Compare regression command passed **20 tests, 0 failed**. Targeted
analysis reported no issues; selected fatal Python lint checks and diff whitespace
checks passed. Full repository suites were not run.

An earlier Explorer run passed **31 tests, 0 failed** before the additional
automatic-retry regression was added. The final run passed **32 Explorer tests,
0 failed**, in 16 seconds. Together with the 34 backend and 20 existing risk/Compare
tests, the final focused verification passed **86 distinct tests, 0 failed**.

Initial executions exposed error-state visibility, invalid progress semantics and
test-fixture problems; these were investigated and corrected. One intermediate
run had a Dart inference compilation error, corrected with an explicit
`AsyncValue<RiskEstimateModel?>` type. SDK cache restrictions required elevated
test/analyzer access. One automatic approval review timed out; its retry succeeded.

## Optional visual capture and verification limits

This additional command was attempted:

```powershell
$env:DISEASE_EXPLORER_CAPTURE_DIR = 'D:\FYP ForeSeeMe\fyp_foreseeme\test_artifacts\disease_explorer'
flutter test --no-pub test/features/disease_explorer/disease_screen_test.dart
```

It produced light/dark layout images, but **14 tests passed and 2 visual-capture
tests failed** because real-event-loop rasterization exposed Google Fonts HTTP
requests blocked by Flutter's widget-test HTTP client. The images use the test
placeholder font and do not establish production typography quality. Their
layout/surface structure was inspected, but real-device font, contrast,
screen-reader and Android performance review remain unverified. Standard layout,
motion, semantics and text-scaling assertions run independently of PNG capture.

No full integration suites, cloud end-to-end tests, live Firestore reads/writes,
physical-device performance tests, deployment, model training or promotion,
security-rule changes, infrastructure/billing changes, commits, pushes or PRs
were performed. Legacy documents intentionally remain unavailable in Explorer
until an authorized backend release produces the additive data. No history is
fabricated or manually backfilled.

Home, Dashboard, Compare, the five-item bottom navigation and unrelated features
were not redesigned. Existing canonical Firestore fields and their meanings,
service-account-only writes, document IDs and routing architecture are preserved.

Recommended remaining validation: inspect the screen on an Android device with
the application's actual fonts before any separately authorized release.
