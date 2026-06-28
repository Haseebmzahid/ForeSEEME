ForeSeeMe — Sprint 2 Implementation Playbook
Sprint focus: the AI/ML pipeline — from raw public data to a trained, evaluated, documented, deployed Random Forest, fully aligned with the existing Feature-First Clean Architecture.

Sprint 1 baseline (preserved): risk contracts/schemas, FastAPI skeleton, stub model behind an abstract interface, Dockerised backend, env-based config, Flutter risk feature, repository layer (Firestore + fake), Riverpod providers, seed scripts, tests, docs.

Positioning decision (R1, accepted): ForeSeeMe is an AI-powered Environmental Disease Risk Estimation System, not an outbreak-prediction system. Labels represent environmental disease risk derived transparently from environmental determinants and epidemiological literature — not clinically confirmed incidence. This positioning is load-bearing; every prompt below honours it.


How to use this playbook
Run prompts in order. After each, review, test, and commit before starting the next. Prompts 3–5 may run in parallel once Prompt 2 is merged. Prompt 10 is a hard gate — modeling does not begin until dataset validation passes.

Each prompt ends with: "Stop after completing this task. Wait for review before continuing." Honour it.


Shared principles (every prompt inherits these — paste GOLDEN_RULES.md + this list into Claude Code each time)
No label leakage by pretence. Labels are derived from environmental features, so a model trained on those features will score high — that is expected and is not the scientific claim. The model is framed and evaluated as a calibrated surrogate of a literature-grounded risk index. The scientific validation is label-vs-seasonality alignment, not accuracy.
Data availability drives the time window. The usable date range is whatever the scarcest reliable source (air quality) actually supports, determined empirically in Prompt 1 — never an assumed range. Do not fabricate, back-fill, or synthesise records to hit a target row count.
Raw data is immutable and reproducible. Downloads land in backend/ml/data/raw/ (git-ignored), are never edited in place, and are accompanied by a hash manifest so any reader can reproduce the exact dataset from the acquisition scripts.
No hardcoded paths or secrets. All paths derive from a central config/paths module; all cities, sources, date ranges, and hyperparameters live in backend/ml/config/*.yaml. Secrets come from environment variables only.
Architecture is frozen. Flutter never calls /predict; it reads only Firestore riskEstimates. FastAPI stays internal. The trained artifact is consumed through the existing Sprint 1 predict abstraction — no redesign.
One concern per prompt. Small, reviewable, independently committable units.
Target ML structure (extends the repo; does not replace anything)
backend/ml/

 ├── config/        # cities.yaml, sources.yaml, pipeline.yaml, model.yaml

 ├── data/

 │    ├── raw/       # immutable downloads (git-ignored) + manifest.json

 │    ├── interim/   # cleaned, aligned, merged

 │    └── processed/ # final train.parquet / test.parquet (frozen)

 ├── pipelines/     # acquisition, cleaning, alignment, features, labels, validation

 ├── training/      # train, tune, evaluate

 ├── artifacts/     # model_<version>.joblib, metrics.json, plots/

 ├── reports/       # data_availability.md, label_methodology.md, MODEL_CARD.md

 └── tests/

Training-time code lives in backend/ml/. Serving-time loading stays in backend/app/predict.py (Sprint 1). Keep the two separated.


PHASE A — DATA ENGINEERING FOUNDATION
Prompt 1 — Data Source Discovery & Availability Report
Objective. Empirically identify and validate every public data source before any bulk acquisition, and produce a source registry plus a human-readable availability report that fixes the project's usable time window.

Context. Per Shared Principle 2, the dataset window is unknown until we measure what air-quality history actually exists for our cities. This prompt writes no bulk-download logic — it probes sources, confirms reachability and real coverage, and records findings. Cities are Islamabad, Rawalpindi, Lahore, Karachi, Peshawar.

Dependencies. Sprint 1 complete. No prior Sprint 2 prompts.

Constraints. Prefer free, keyless, reproducible reanalysis sources: Open-Meteo Historical Weather API (archive-api.open-meteo.com, ERA5) for temperature/humidity/precipitation, and Open-Meteo Air Quality API (air-quality-api.open-meteo.com, CAMS) for PM2.5/PM10/US-AQI. Probe each city/source with small sample requests to discover the earliest reliable date per variable. Do not assume 2010–2023. Disease sources (WHO EMRO, IHME GBD, Punjab dengue surveillance, documented seasonality) are catalogued as validation-only, never training labels. No secrets; if any source needs a key, record it as an env var, do not embed it.

Expected files. backend/ml/config/cities.yaml (name, lat, lon, province), backend/ml/config/sources.yaml (per-source: base URL, variables, discovered coverage window, license, access method), backend/ml/reports/data_availability.md, backend/ml/pipelines/discover_sources.py (the probing script).

Testing. backend/ml/tests/test_discover_sources.py: assert cities.yaml and sources.yaml parse and contain all five cities and the required variables; assert the probing script handles an unreachable endpoint without crashing (mocked failure → recorded as "unavailable", not an exception).

Acceptance criteria. data_availability.md states, per city and variable, the confirmed earliest/latest date and any gaps; it ends with a single recommended project-wide modeling window justified by the scarcest source. sources.yaml is complete enough that later prompts need no new source decisions.

Failure modes. Agent asserts coverage dates without probing (reject — must be measured); agent silently drops a city with poor coverage (must be recorded, not hidden); agent embeds an API key.

Expected output. A validated source registry and an availability report that fixes the modeling window. No bulk data downloaded yet.

Stop after completing this task. Wait for review before continuing.


Prompt 2 — Acquisition Framework & Configuration
Objective. Build the reusable, config-driven acquisition framework (paths, config loading, idempotent caching, hash manifest) that all source-specific pipelines will use.

Context. Establishes the spine for Prompts 3–5 so each becomes a thin, consistent adapter. Enforces Shared Principles 3 and 4 in code.

Dependencies. Prompt 1 (cities.yaml, sources.yaml).

Constraints. A central paths.py resolves all directories from config/env (no string literals elsewhere). Downloads are idempotent: if a raw file for a (city, source, window) already exists and its hash matches the manifest, skip the network call. Every raw file is recorded in backend/ml/data/raw/manifest.json with source, params, timestamp, and SHA-256. data/raw/, data/interim/, data/processed/ are git-ignored (add a .gitignore), but the manifest is committed. Use httpx or requests with retry/backoff; respect rate limits; log every request.

Expected files. backend/ml/pipelines/paths.py, backend/ml/pipelines/acquisition_base.py (base class/functions: fetch-with-cache, write-raw, update-manifest), backend/ml/config/pipeline.yaml (window, cache policy, retry settings), backend/ml/data/.gitignore, backend/ml/tests/test_acquisition_base.py.

Testing. Mock the HTTP layer: assert a first call writes a raw file + manifest entry; a second identical call is skipped (cache hit, no network); a hash mismatch triggers re-download; a transient 5xx retries then succeeds.

Acceptance criteria. No hardcoded paths anywhere; re-running acquisition twice produces identical manifests and zero duplicate network calls; manifest round-trips.

Failure modes. Paths sprinkled as literals (reject); manifest not updated atomically (risk of corruption on interrupt); committing raw data blobs.

Expected output. A tested acquisition framework with reproducible, idempotent, manifested downloads.

Stop after completing this task. Wait for review before continuing.


Prompt 3 — Weather Data Pipeline
Objective. Acquire historical daily weather (temperature, relative humidity, precipitation) for all five cities across the project window and store immutable raw files.

Context. First concrete source adapter on the Prompt 2 framework. Humidity is hourly-only on Open-Meteo, so hourly pulls are aggregated to daily where needed.

Dependencies. Prompt 2.

Constraints. Use the source and window from sources.yaml/pipeline.yaml. Fetch via the acquisition base (cache + manifest). Persist exactly what the API returns (raw); derive daily aggregates only in the cleaning phase, not here. Per-city files; no merging yet. Document each retained variable and its units in a short header/sidecar.

Expected files. backend/ml/pipelines/acquire_weather.py, raw outputs under backend/ml/data/raw/weather/<city>.*, manifest updated, backend/ml/tests/test_acquire_weather.py.

Testing. Mocked API: assert one raw file per city with expected variables; assert window matches config; assert manifest entries created; assert a missing variable in the response is logged and recorded, not silently dropped.

Acceptance criteria. Five raw weather files covering the configured window, each manifested; re-run is a no-op (cache).

Failure modes. Aggregating/transforming in the acquisition step (must stay raw); requesting a window the source can't serve (should clip to sources.yaml coverage and log).

Expected output. Immutable raw weather data for all cities.

Stop after completing this task. Wait for review before continuing.


Prompt 4 — Air Quality Data Pipeline
Objective. Acquire historical air-quality data (PM2.5, PM10, US-AQI) for all cities across the AQI-supported window, treating limited coverage as a first-class, documented reality.

Context. AQI is the scarcest source (Shared Principle 2). Its coverage, fixed in Prompt 1, governs the merged dataset's usable range.

Dependencies. Prompt 2; coordinate with Prompt 3 (parallel-safe).

Constraints. Same framework, cache, and manifest. Where AQI history is shorter than weather history, do not invent earlier values — fetch only the supported range; downstream phases will treat the pre-coverage period as missing-by-design. Record the exact AQI window in the raw sidecar.

Expected files. backend/ml/pipelines/acquire_aqi.py, raw outputs under backend/ml/data/raw/aqi/<city>.*, manifest updated, backend/ml/tests/test_acquire_aqi.py.

Testing. Mocked API: per-city raw files; window clipped to AQI coverage; partial-coverage city handled and logged; manifest updated.

Acceptance criteria. Raw AQI files present for every city that has coverage; coverage limits explicitly recorded; re-run is a no-op.

Failure modes. Back-filling AQI to match the weather window (forbidden); failing instead of clipping when a city lacks early coverage.

Expected output. Immutable raw AQI data with documented coverage limits.

Stop after completing this task. Wait for review before continuing.


Prompt 5 — Disease Reference Data Pipeline (validation-only)
Objective. Catalogue and acquire sparse public disease/seasonality reference signals used solely to validate label plausibility later — explicitly never as training labels.

Context. Directly enforces the R1 reframe. We need an external yardstick (known dengue/smog/influenza seasonality, any documented outbreak years) to test whether generated labels are epidemiologically sensible (Prompt 12).

Dependencies. Prompt 2.

Constraints. Acquire/encode only what is genuinely public and citable (e.g., documented seasonal windows: dengue post-monsoon Aug–Nov; Punjab smog Oct–Jan; influenza winter). Where only qualitative seasonality exists, encode it as a structured, sourced reference table — and label every entry with its citation. Mark this dataset VALIDATION_ONLY in code and docs; add a guard so it can never be imported by feature/label/training modules.

Expected files. backend/ml/data/raw/disease_reference/* (+ sidecar with citations), backend/ml/pipelines/acquire_disease_reference.py, backend/ml/reports/disease_reference_notes.md, backend/ml/tests/test_disease_reference_guard.py.

Testing. Assert reference data loads; assert the import guard raises if a training/feature/label module attempts to import it; assert every reference entry carries a citation field.

Acceptance criteria. A sourced, citation-bearing reference dataset exists and is structurally barred from the training path.

Failure modes. Reference data leaking into features/labels (the guard must prevent this); uncited "facts" (reject — no fabrication).

Expected output. A validation-only seasonality reference, quarantined from training.

Stop after completing this task. Wait for review before continuing.


PHASE B — DATASET CONSTRUCTION
Prompt 6 — Data Cleaning & Missing-Value Strategy
Objective. Convert raw per-source files into cleaned, daily, per-city interim tables with an explicit, documented missing-value strategy.

Context. First transformation step. Cleaning is deterministic and reproducible from raw; raw is never mutated.

Dependencies. Prompts 3, 4 (and 5 catalogued).

Constraints. Standardise city names and date formats; aggregate hourly→daily where needed (e.g., humidity mean, precipitation sum); enforce physical ranges (drop/flag impossible values, e.g., negative AQI, humidity >100). Missing-value policy must be explicit and justified per variable: short gaps → documented interpolation with a configurable max-gap; AQI pre-coverage period → retained as NaN and flagged aqi_available=False (never imputed across a multi-year absence). Emit a per-source data-quality summary (counts, % missing, flagged anomalies).

Expected files. backend/ml/pipelines/clean.py, interim outputs under backend/ml/data/interim/<source>/<city>.parquet, backend/ml/reports/data_quality.md, backend/ml/tests/test_clean.py.

Testing. Unit tests on synthetic dirty input: out-of-range values flagged/removed; short gap interpolated within max-gap; long AQI gap left NaN + flagged; hourly→daily aggregation correct; city-name normalisation correct.

Acceptance criteria. Cleaned interim tables are deterministic from raw; data_quality.md quantifies missingness per variable/city; no silent imputation of long gaps.

Failure modes. Imputing across the AQI coverage gap (forbidden); mutating raw; undocumented drops.

Expected output. Cleaned, daily, per-city interim tables with a transparent missing-value report.

Stop after completing this task. Wait for review before continuing.


Prompt 7 — Temporal Alignment & Dataset Merging
Objective. Align all cleaned sources to a common (city, ISO-week) grid and merge into a single interim weekly dataset.

Context. The model operates at weekly granularity (SDS). This prompt produces the unlabelled, unengineered weekly base table.

Dependencies. Prompt 6.

Constraints. Aggregate daily→weekly per city (temperature mean, humidity mean, rainfall sum, AQI mean), keying on (city, iso_year, week_of_year). Outer-join sources on the key; carry forward the aqi_available flag. No feature engineering and no labels here. Record final row count and per-column missingness post-merge.

Expected files. backend/ml/pipelines/merge.py, backend/ml/data/interim/weekly_base.parquet, backend/ml/reports/merge_summary.md, backend/ml/tests/test_merge.py.

Testing. Synthetic multi-source input merges to the expected (city, week) rows; weekly aggregation arithmetic verified; missing AQI weeks preserved as NaN + flag; no duplicate keys.

Acceptance criteria. A single weekly base table keyed uniquely on (city, iso_year, week_of_year); merge summary reports realistic, non-fabricated row counts.

Failure modes. Duplicate keys; inner-join silently dropping AQI-missing weeks; weekly aggregation mixing sum vs mean incorrectly.

Expected output. One clean weekly base dataset ready for feature engineering.

Stop after completing this task. Wait for review before continuing.


Prompt 8 — Feature Engineering
Objective. Derive temporal, lagged, and seasonal features that make the learning problem non-trivial and epidemiologically meaningful.

Context. Critical for defusing the circularity trap (Shared Principle 1). Raw same-week values alone make labels trivially invertible; lagged and anomaly features force the model to learn a function over time, mirroring real disease dynamics (e.g., dengue responds to rainfall 2–4 weeks prior).

Dependencies. Prompt 7.

Constraints. Engineer, at minimum: lagged rainfall/temperature/humidity (configurable lags, e.g., 1–4 weeks); rolling means (e.g., 3- and 4-week); seasonal/climatological anomaly features (value minus that week's multi-year city climatology); cyclical encoding of week_of_year (sin/cos); a categorical city encoding compatible with the serving pipeline. All feature definitions live in config/pipeline.yaml. Document the epidemiological rationale for each feature family. Beware lookahead: lags/rollings must use only past weeks; verify no future leakage.

Expected files. backend/ml/pipelines/features.py, backend/ml/data/interim/weekly_features.parquet, backend/ml/reports/feature_dictionary.md, backend/ml/tests/test_features.py.

Testing. Lag/rolling correctness on a known series; anomaly = value − climatology verified; cyclical encoding bounds; lookahead test — a feature at week t never uses data from t+1; rows with insufficient history handled (dropped or flagged, documented).

Acceptance criteria. A weekly feature table with documented, leakage-free, epidemiologically-justified features; feature dictionary complete.

Failure modes. Lookahead leakage (must be tested); features that are pure 1:1 copies of raw inputs only (defeats the purpose — lagged/anomaly features required); undocumented features.

Expected output. An engineered weekly feature set that makes the model a genuine function approximator, not a rule-memoriser.

Stop after completing this task. Wait for review before continuing.


Prompt 9 — Environmental Risk Label Generation
Objective. Generate transparent, reproducible, literature-grounded Low/Medium/High environmental risk labels with a soft transition band, plus a full methodology document.

Context. The heart of the R1 reframe and the circularity defence. Labels encode an environmental disease-risk index, not incidence. The transition band makes boundary cases probabilistic so the downstream model must learn calibrated uncertainty rather than a hard threshold.

Dependencies. Prompt 8.

Constraints. Build a documented, weighted environmental risk index per disease family from determinants in the cited literature — e.g., dengue: optimal vector temperature band + humidity + lagged rainfall; smog/respiratory: high PM2.5 + winter/low-temp inversion window + low rainfall; influenza: low temperature/humidity in winter. Combine into a continuous risk score, then map to Low/Medium/High via thresholds with a transition band: scores within ±δ of a boundary receive a probabilistic label (sampled or stored as class probabilities), so the boundary is genuinely learnable. Every threshold, weight, and band width is in config/pipeline.yaml and cited in the methodology doc — no uncited numbers, no fabricated citations (cite the literature you actually use). Labelling must be deterministic given a fixed random seed. Record final class distribution.

Expected files. backend/ml/pipelines/labels.py, backend/ml/data/interim/weekly_labelled.parquet, backend/ml/reports/label_methodology.md (determinants, equations, thresholds, band, citations, limitations), backend/ml/tests/test_labels.py.

Testing. Index computation matches worked examples; threshold mapping correct; transition-band cases produce probabilistic (non-degenerate) labels; fixed seed → identical labels; class distribution is non-degenerate (no class collapses to ~0%).

Acceptance criteria. Reproducible labels; a methodology doc an examiner could follow and challenge on its merits; documented limitations (states plainly: environmental risk, not incidence).

Failure modes. Hard deterministic thresholds that make the model trivial (transition band is mandatory); uncited/fabricated thresholds; a collapsed class distribution; non-reproducible (unseeded) labelling.

Expected output. Transparent, calibrated, defensible environmental risk labels with full provenance.

Stop after completing this task. Wait for review before continuing.


Prompt 10 — Dataset Validation & Temporal Train/Test Freeze  ⛔ HARD GATE
Objective. Validate the labelled feature set against an explicit schema and statistical contract, perform a temporal train/test split, and freeze the final processed datasets. Modeling must not begin unless this passes.

Context. The gate that keeps the model honest. Catches leakage, broken splits, and degenerate distributions before any training time is spent.

Dependencies. Prompt 9.

Constraints. Use pandera (or equivalent) for a schema contract: column types, physical ranges, allowed label values, key uniqueness, and a leakage assertion (no row uses future-dated inputs). Split temporally — earliest weeks → train, most recent block → test (no random shuffling; lagged features mean random splits leak). Ensure each class appears in both splits; document any city/period excluded for insufficient history. Freeze train.parquet/test.parquet and write a manifest hash so the exact split is reproducible.

Expected files. backend/ml/pipelines/validate.py, backend/ml/data/processed/train.parquet, backend/ml/data/processed/test.parquet, backend/ml/reports/validation_report.md, backend/ml/tests/test_validate.py.

Testing. Schema rejects an out-of-range/wrong-type/invalid-label row; temporal split has no time overlap between train and test; all classes present in both; manifest hash stable across re-runs.

Acceptance criteria. Validation report is green on every check; split is temporal and leakage-free; processed datasets frozen + hashed. If any check fails, stop and fix upstream — do not proceed to Phase C.

Failure modes. Random instead of temporal split (reject); a class absent from test; schema warnings downgraded to pass; proceeding despite a failed check.

Expected output. A frozen, validated, temporally-split training/test dataset and a passing validation report — the green light for modeling.

Stop after completing this task. Wait for review before continuing.


PHASE C — MODELING
Prompt 11 — Model Training, Hyperparameter Tuning & Temporal Cross-Validation
Objective. Train a Random Forest inside a self-contained sklearn Pipeline, tune it, and validate with time-aware cross-validation.

Context. Produces the candidate model. Preprocessing (encoding/scaling) must live inside the Pipeline so the saved artifact is self-sufficient at serving time (consistent with Sprint 1 loading).

Dependencies. Prompt 10 (frozen datasets).

Constraints. Single sklearn Pipeline (preprocessing + RandomForestClassifier). Hyperparameters and search space in config/model.yaml. Tune via grid/randomised search using TimeSeriesSplit (not plain K-fold — temporal data). class_weight='balanced'; fixed random_state. Train only on train.parquet; never touch test.parquet here. Log all trials and the chosen configuration.

Expected files. backend/ml/training/train.py, backend/ml/config/model.yaml, backend/ml/artifacts/candidate_model.joblib, backend/ml/reports/training_log.md, backend/ml/tests/test_train.py.

Testing. Pipeline fits on a tiny fixture; CV uses a time-aware splitter (assert no future→past fold); the artifact reloads and predicts; same seed → same chosen params.

Acceptance criteria. A reproducible, tuned Pipeline artifact trained only on train data; CV is temporal; training log records the search and the winner.

Failure modes. Plain K-fold on temporal data (reject); preprocessing outside the Pipeline (breaks serving); any peek at the test set during tuning.

Expected output. A tuned, reloadable candidate model produced under time-aware validation.

Stop after completing this task. Wait for review before continuing.


Prompt 12 — Evaluation, Feature Importance, Explainability & Label Validation
Objective. Evaluate the candidate as a surrogate (generalization, calibration, robustness), explain it, and — most importantly — validate the labels against external disease seasonality.

Context. This is where the project earns its scientific defensibility. Accuracy is reported but explicitly framed as expected-by-construction; the real evidence is calibration, noise-robustness, importance alignment, and seasonality validation.

Dependencies. Prompt 11; Prompt 5 (validation-only reference).

Constraints. On the held-out test set: classification report + confusion matrix; calibration (reliability curve + Brier score) — calibrate if poor; robustness (inject Gaussian noise into inputs, confirm graceful degradation, not collapse); permutation importance (preferred over Gini for correlated features) and optional SHAP. Then the decisive check: label-vs-seasonality validation — show High-dengue-risk weeks concentrate in the documented post-monsoon window, High-smog weeks in Oct–Jan, etc., using the Prompt 5 reference. The evaluation report must state in plain language that high accuracy reflects label derivation and is not the scientific claim.

Expected files. backend/ml/training/evaluate.py, backend/ml/reports/evaluation_report.md, backend/ml/artifacts/plots/* (confusion matrix, reliability curve, importances, seasonality alignment), backend/ml/tests/test_evaluate.py.

Testing. Metrics computed on test only; reliability/Brier produced; permutation importance runs; seasonality alignment uses the quarantined reference correctly; report contains the explicit label-derivation acknowledgment.

Acceptance criteria. Importances align with epidemiological expectation; model is calibrated and noise-robust; seasonality validation demonstrably holds; report is honest about what accuracy does and does not prove.

Failure modes. Presenting accuracy as the headline scientific result (reject); skipping calibration/robustness; seasonality check missing or contradicted without comment.

Expected output. A defensible evaluation that validates the labelling methodology and characterises the model as a calibrated surrogate.

Stop after completing this task. Wait for review before continuing.


Prompt 13 — Model Persistence & Model Card
Objective. Promote the validated candidate to a versioned production artifact and author a complete Model Card.

Context. Final modeling deliverable; the artifact and card are what the backend consumes and what the FYP report/viva references.

Dependencies. Prompt 12 (model passes evaluation).

Constraints. Persist as model_<semver>.joblib with a sidecar metrics.json and a reproducibility record (training data manifest hash, config hash, seed, library versions). Author MODEL_CARD.md covering: intended use; explicit out-of-scope (not outbreak prediction, not clinical/diagnostic); training data + provenance; label methodology + limitations (links Prompt 9 doc); metrics + calibration; ethical/operational caveats; version. The serving contract from Sprint 1 must remain unchanged.

Expected files. backend/ml/artifacts/model_<version>.joblib, backend/ml/artifacts/metrics.json, backend/ml/reports/MODEL_CARD.md, backend/ml/tests/test_artifact.py.

Testing. Artifact loads and predicts contract-shaped output; metrics.json matches the evaluation report; reproducibility record present and complete; version string parses as semver.

Acceptance criteria. A versioned, documented, reproducible artifact with a Model Card an examiner could audit end-to-end.

Failure modes. Missing reproducibility metadata; a Model Card that overclaims (e.g., "predicts outbreaks"); metrics drift between card and artifact.

Expected output. Production-ready model artifact + authoritative Model Card.

Stop after completing this task. Wait for review before continuing.


PHASE D — INTEGRATION
Prompt 14 — Backend Integration (swap stub → real model)
Objective. Replace the Sprint 1 stub with the real model behind the existing predict abstraction, leaving the contract and endpoints untouched.

Context. Closes the loop with Sprint 1's deployable service. Because the contract was frozen in Sprint 1, this is a clean substitution.

Dependencies. Prompt 13.

Constraints. Load model_<version>.joblib in the existing backend/app/predict.py load path; map the existing PredictRequest → engineered feature vector → Pipeline → PredictResponse (set model_version, confidence, low_confidence per the contract's <0.55 rule). Do not modify schemas.py or the /predict route signature. /health must report model_loaded: true. The feature-construction logic used at serving must match training (reuse the Prompt 8 transforms — single source of truth, no divergence).

Expected files. updated backend/app/predict.py, backend/app/feature_builder.py (shared serving/training transforms, or an import of the Prompt 8 module), updated backend/tests/test_api.py.

Testing. /predict returns real, contract-valid predictions; /health shows model_loaded: true; out-of-range input still 422; a corrupt/missing artifact still yields the Sprint 1 stub/503 behaviour (graceful); serving feature vector equals training feature vector for a fixed input (parity test).

Acceptance criteria. Real predictions flow through the unchanged contract; train/serve feature parity proven; Sprint 1 failure behaviours preserved.

Failure modes. Divergent train vs serve feature logic (the parity test must catch this); touching the frozen contract; losing the graceful-degradation path.

Expected output. The FastAPI service now serves the real model behind the original Sprint 1 interface.

Stop after completing this task. Wait for review before continuing.


Prompt 15 — Batch Inference & Firestore Write Job
Objective. Implement the scheduled job that computes current per-city risk and writes riskEstimates to Firestore — the component that finally connects the ML engine to the app (per ADR-0001/0002).

Context. Resolves the original review's G1/G2: the app reads only Firestore, and this job is the sole writer of risk. It is the entrypoint for a Cloud Scheduler → Cloud Run job.

Dependencies. Prompt 14; Sprint 1 Firestore schema + seed/credential pattern.

Constraints. For each city: fetch a trailing window of recent weather/AQI (lagged/rolling features need history — not just today), build the same engineered features, run the model, construct a RiskEstimate matching the Sprint 1 Firestore schema ({city}_{YYYY-MM-DD} doc ID), and upsert to riskEstimates via firebase-admin using the service account (reuse the Sprint 1 seed-script credential pattern; secrets via env). Idempotent per (city, date). Runs as a standalone, container-friendly entrypoint; structured logging; never imports Flutter or the disease-reference module.

Expected files. backend/app/jobs/compute_risk.py, backend/app/jobs/__init__.py, updated backend/Dockerfile/compose with a job entrypoint, backend/tests/test_compute_risk.py.

Testing. Mock weather/AQI + mock Firestore: assert one upsert per city with a contract-valid document and correct doc ID; re-run upserts (no duplicates); a city missing live data is skipped + logged, others still processed; throttle/idempotency on (city, date) holds.

Acceptance criteria. Running the job populates riskEstimates for all cities with valid, schema-correct documents the Flutter app can already read; idempotent; service-account-only writes.

Failure modes. Computing features from a single week (breaks lagged features); divergent feature logic vs training/serving; client-side credentials; non-idempotent writes creating duplicates.

Expected output. A deployable scheduled job that closes the pipeline: model → Firestore → app.

Stop after completing this task. Wait for review before continuing.


Sprint 2 — Definition of Done
Reproducible data pipeline from public sources to a frozen, validated, temporally-split dataset (no fabricated data; window justified by real coverage).
Transparent, cited, transition-band environmental risk labels with a methodology document.
A tuned Random Forest evaluated as a calibrated surrogate, with importances aligned to epidemiology and labels validated against known seasonality.
Versioned artifact + auditable Model Card (explicitly not outbreak prediction).
Real model served behind the unchanged Sprint 1 contract, with train/serve feature parity.
A scheduled batch job writing riskEstimates to Firestore — the ML engine now feeds the app, ready for the Sprint 3 dashboard/heatmap.

Carried forward to Sprint 3: heatmap UI against live riskEstimates, then the personalised FCM alert engine (the novel contribution) on top of this risk feed.








