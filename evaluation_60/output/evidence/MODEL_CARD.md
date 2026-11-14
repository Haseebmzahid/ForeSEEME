# Model Card — ForeSeeMe Environmental Disease-Risk Model `1.0.0`

**Artifact:** `artifacts/model_1.0.0.joblib` · **Prediction `modelVersion`:** `rf-1.0.0` · **Status:** 🔒 released candidate (Sprint 2, Prompt 13)

> **ForeSeeMe estimates ENVIRONMENTAL DISEASE-RISK SUITABILITY — not incidence, not outbreaks.** It scores how favourable a city-week's environment is for each disease family, from a transparent, literature-grounded index. It is **not** an outbreak predictor and **not** a clinical or diagnostic tool.

## Intended use

- Produce a Low / Medium / High **environmental risk level** per (city, week) for dengue, smog/respiratory, and influenza, with a confidence, to drive the ForeSeeMe awareness dashboard and alerts.
- Consumed only by the backend batch job, which writes `riskEstimates` to Firestore (ADR-001); the app reads Firestore, never the model directly.

## Out of scope (explicit)

- ❌ **Not outbreak prediction / forecasting.** It does not predict case counts, epidemic timing, or transmission.
- ❌ **Not clinical or diagnostic.** It says nothing about any individual's health and must not inform diagnosis or treatment.
- ❌ **Not a surveillance substitute.** It complements, never replaces, official public-health surveillance.
- ❌ Outside the five modelled cities or the trained environmental ranges, outputs are unsupported.

## Model details

- **Architecture:** one self-contained scikit-learn `Pipeline` per disease (dengue, smog, influenza) — `SimpleImputer(median)` → `StandardScaler` → `RandomForestClassifier(class_weight='balanced')` — bundled in a single artifact behind one predict interface.
- **Inputs:** 36 leakage-free engineered features (raw weather/AQI, 1–4 wk lags, 3–4 wk rolling means, seasonal anomalies, cyclical week, city one-hots). See `reports/feature_dictionary.md`.
- **Output:** `riskLevel` ∈ {Low, Medium, High}, `confidence` ∈ [0,1], `modelVersion` — matching the frozen Sprint 1 contract (`docs/RISK_SCHEMA.md`).
- **Selected hyperparameters (tuned via TimeSeriesSplit, Prompt 11):**
  - dengue: n_estimators=200, min_samples_split=10, min_samples_leaf=1, max_features=0.5, max_depth=6
  - smog: n_estimators=400, min_samples_split=2, min_samples_leaf=2, max_features=0.5, max_depth=10
  - influenza: n_estimators=200, min_samples_split=10, min_samples_leaf=1, max_features=log2, max_depth=None

## Training data & provenance

- **Sources:** Open-Meteo ERA5 (temperature, humidity, precipitation) and CAMS air quality (PM2.5, PM10, US-AQI), for Islamabad, Rawalpindi, Lahore, Karachi, Peshawar.
- **Window:** 2022-08-05 → 2026-06-28 (weekly; bounded by real AQI coverage — see `reports/data_availability.md`). No fabricated or back-filled records.
- **Temporal split (no shuffling):** train **735** rows / test **260** rows; test is the most recent block (`reports/validation_report.md`, GREEN gate).
- **Data hashes:** train `5079011c7d0349f2569a0f2711df156e6aeef12de6621f4aa8986a69f04a34c5` · test `1d18b5ae78c74fa89912990746312fb0e3c96e03d7295c915c2c551cffd98b46`.

## Label methodology & limitations

- Labels are a transparent, weighted **environmental-suitability index** per disease, mapped to Low/Med/High with a soft transition band; every threshold/weight is cited to literature in **`reports/label_methodology.md`** (Prompt 9).
- **Suitability, not incidence.** No human immunity, mobility, vaccination, vector control, or reporting effects are modelled.
- The index weights and cutoffs are documented **design choices** an examiner can challenge; the data window is short (2022-08 onward).

## Metrics & calibration (held-out test set)

> **Accuracy is expected-by-construction and is NOT the scientific claim:** labels are derived from the same features the model reads, so a faithful surrogate necessarily scores high. The evidence is calibration, robustness, importance alignment, and seasonality (`reports/evaluation_report.md`, Prompt 12).

| Disease | Accuracy | F1 (macro/wt) | ROC-AUC | Brier | ECE | Seasonality lift |
|---------|----------|---------------|---------|-------|-----|------------------|
| dengue | 0.854 | 0.833/0.861 | 0.970 | 0.191 | 0.053 | 1.60 |
| smog | 0.954 | 0.926/0.954 | 0.995 | 0.074 | 0.053 | 2.91 |
| influenza | 0.908 | 0.839/0.909 | 0.984 | 0.158 | 0.102 | 3.92 |

- **Calibration:** reliability + Brier + ECE assessed per disease; where ECE was poor it was improved with a temporal sigmoid calibrator (details in `evaluation.json` / evaluation report).
- **Robustness:** graceful degradation under Gaussian input noise (stays above chance) — not collapse.
- **Seasonality validation (decisive):** High-risk weeks concentrate in documented windows (smog Oct–Jan, influenza Dec–Feb strongly; dengue post-monsoon more broadly, consistent with thermal suitability).

## Ethical & operational caveats

- Communicate outputs as **environmental awareness**, never as a personal medical warning; avoid fatalism or false reassurance.
- Low confidence / out-of-range inputs should degrade gracefully (the serving layer flags `lowConfidence`).
- Risk is only as fresh as the batch schedule (ADR-002); stale or missing upstream data must be surfaced, not hidden.
- Not for resource allocation or clinical triage decisions.

## Reproducibility record

- **Seed:** `42` (everywhere) · **Target label:** `label_sampled` · **Promoted:** `rf-candidate-0.1.0` (candidate) → `rf-1.0.0` (released).
- **Config hash** (`model.yaml`): `10be21dc311fd36a1b7ecc42d4de34f079e09ff196be6da6312e459abfafd028`
- **Candidate hash:** `f6752b701dcc44f9fae1b86849da5f77fd01698d6c700ac7278cfc64402da747`
- **Library versions:** python 3.13.7, scikit-learn 1.7.2, numpy 2.3.5, pandas 2.3.3, scipy 1.16.3, joblib 1.5.2
- **Reproducibility:** the candidate (training + tuning) is byte-for-byte reproducible — same seed → identical candidate (`reports/training_log.md`). This artifact is promoted from that candidate (`candidate_sha256` above) and loads to an identical model with identical predictions; `metrics.json` is regenerated deterministically from the held-out evaluation.

## Explainability (Sprint 5)

Each served estimate carries an additive `attributions` object — genuine, model-derived top
contributors (feature, direction, magnitude) plus a confidence rationale (margin/agreement
from the class distribution), method `tree_path_contributions`. These are computed in the
backend and stored on the `riskEstimate`; the app renders them via a **deterministic
templater** (no generated text). This extends the model card's transparency story into the
product surface — see `docs/SPRINT_5_EVALUATION.md` §4 and `docs/e2e.md`.

## Linked documents

- `reports/label_methodology.md` — labels, determinants, citations (Prompt 9)
- `reports/feature_dictionary.md` — features & leakage guarantees (Prompt 8)
- `reports/validation_report.md` — dataset freeze & GREEN gate (Prompt 10)
- `reports/training_log.md` — search trace & winner (Prompt 11)
- `reports/evaluation_report.md` — held-out evaluation & seasonality (Prompt 12)
- `docs/RISK_SCHEMA.md` — frozen Sprint 1 serving contract

