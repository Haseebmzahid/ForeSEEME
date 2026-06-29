# Training Log — ForeSeeMe Candidate Random Forest

**Sprint 2, Prompt 11 — Model Training, Hyperparameter Tuning & Temporal Cross-Validation**

- Model version: `rf-candidate-0.1.0`
- Seed (forest + search + folds): `42`  → reproducible: same seed yields the same winner.
- Target label: `label_sampled` (transition-band sampled labels, Prompt 9).
- One Pipeline per disease: dengue, smog, influenza — bundled into `candidate_model.joblib`.
- Pipeline: `SimpleImputer(median)` → `StandardScaler` → `RandomForestClassifier(class_weight='balanced')` (preprocessing is inside the artifact, self-sufficient at serving).
- Search: **randomized** (30 candidates) scored by `f1_macro` over **TimeSeriesSplit(n_splits=5)** — temporal CV, never K-fold.
- Trained on `train.parquet` only; `test.parquet` untouched (held-out evaluation is Prompt 12).

## Class imbalance & `class_weight='balanced'`

High risk is a minority class for smog and influenza. `class_weight='balanced'` (inverse-frequency) is used **deliberately** so the minority risk classes are not washed out; this is a documented choice, not a silent default. Train-split distributions:

| Disease | Low | Medium | High |
|---------|-----|--------|------|
| dengue | 281 | 192 | 262 |
| smog | 477 | 172 | 86 |
| influenza | 452 | 166 | 117 |

## Search outcome (the winner)

| Disease | Best CV f1_macro | Chosen hyperparameters |
|---------|------------------|------------------------|
| dengue | 0.7566 | n_estimators=200, min_samples_split=10, min_samples_leaf=1, max_features=0.5, max_depth=6 |
| smog | 0.7833 | n_estimators=400, min_samples_split=2, min_samples_leaf=2, max_features=0.5, max_depth=10 |
| influenza | 0.6701 | n_estimators=200, min_samples_split=10, min_samples_leaf=1, max_features=log2, max_depth=None |

## Out-of-fold metrics (temporal CV on train)

Honest generalisation estimate from out-of-fold TimeSeriesSplit predictions — never the test set.

| Disease | n (covered) | Accuracy | F1-macro | F1-weighted | ROC-AUC (OvR) | Brier |
|---------|-------------|----------|----------|-------------|--------------|-------|
| dengue | 610/735 | 0.7885 | 0.7764 | 0.7890 | 0.9177 | 0.3042 |
| smog | 610/735 | 0.9016 | 0.8515 | 0.9058 | 0.9728 | 0.1698 |
| influenza | 610/735 | 0.8164 | 0.7642 | 0.8168 | 0.9327 | 0.2675 |

## Full search trace (all trials, best first)

### dengue — 30 trials

| Rank | Mean CV f1_macro | Std | Params |
|------|----------------|-----|--------|
| 1 | 0.7566 | 0.0767 | n_estimators=200, min_samples_split=10, min_samples_leaf=1, max_features=0.5, max_depth=6 |
| 2 | 0.7520 | 0.0518 | n_estimators=600, min_samples_split=5, min_samples_leaf=1, max_features=0.5, max_depth=24 |
| 3 | 0.7505 | 0.0654 | n_estimators=800, min_samples_split=10, min_samples_leaf=1, max_features=0.5, max_depth=24 |
| 4 | 0.7499 | 0.0657 | n_estimators=600, min_samples_split=5, min_samples_leaf=2, max_features=0.5, max_depth=16 |
| 5 | 0.7472 | 0.0689 | n_estimators=600, min_samples_split=10, min_samples_leaf=2, max_features=0.5, max_depth=None |
| 6 | 0.7453 | 0.0723 | n_estimators=400, min_samples_split=2, min_samples_leaf=2, max_features=0.5, max_depth=10 |
| 7 | 0.7429 | 0.1259 | n_estimators=200, min_samples_split=10, min_samples_leaf=4, max_features=log2, max_depth=6 |
| 8 | 0.7350 | 0.0999 | n_estimators=200, min_samples_split=10, min_samples_leaf=4, max_features=0.5, max_depth=24 |
| 9 | 0.7339 | 0.0866 | n_estimators=200, min_samples_split=10, min_samples_leaf=1, max_features=log2, max_depth=None |
| 10 | 0.7339 | 0.1065 | n_estimators=600, min_samples_split=10, min_samples_leaf=4, max_features=0.5, max_depth=24 |
| 11 | 0.7335 | 0.1047 | n_estimators=400, min_samples_split=2, min_samples_leaf=4, max_features=0.5, max_depth=6 |
| 12 | 0.7333 | 0.1117 | n_estimators=400, min_samples_split=2, min_samples_leaf=4, max_features=sqrt, max_depth=10 |
| 13 | 0.7325 | 0.1338 | n_estimators=200, min_samples_split=2, min_samples_leaf=4, max_features=log2, max_depth=16 |
| 14 | 0.7321 | 0.1004 | n_estimators=400, min_samples_split=2, min_samples_leaf=4, max_features=0.5, max_depth=24 |
| 15 | 0.7321 | 0.1201 | n_estimators=200, min_samples_split=10, min_samples_leaf=1, max_features=sqrt, max_depth=6 |
| 16 | 0.7315 | 0.0885 | n_estimators=800, min_samples_split=2, min_samples_leaf=1, max_features=sqrt, max_depth=10 |
| 17 | 0.7315 | 0.0619 | n_estimators=200, min_samples_split=2, min_samples_leaf=1, max_features=0.5, max_depth=None |
| 18 | 0.7312 | 0.1018 | n_estimators=300, min_samples_split=5, min_samples_leaf=4, max_features=0.5, max_depth=10 |
| 19 | 0.7298 | 0.1183 | n_estimators=400, min_samples_split=10, min_samples_leaf=1, max_features=log2, max_depth=6 |
| 20 | 0.7296 | 0.0896 | n_estimators=800, min_samples_split=5, min_samples_leaf=1, max_features=log2, max_depth=None |
| 21 | 0.7294 | 0.1102 | n_estimators=400, min_samples_split=10, min_samples_leaf=4, max_features=sqrt, max_depth=16 |
| 22 | 0.7288 | 0.1112 | n_estimators=800, min_samples_split=10, min_samples_leaf=2, max_features=sqrt, max_depth=6 |
| 23 | 0.7283 | 0.0886 | n_estimators=300, min_samples_split=5, min_samples_leaf=1, max_features=log2, max_depth=16 |
| 24 | 0.7276 | 0.1197 | n_estimators=800, min_samples_split=2, min_samples_leaf=4, max_features=sqrt, max_depth=10 |
| 25 | 0.7272 | 0.0919 | n_estimators=400, min_samples_split=5, min_samples_leaf=1, max_features=sqrt, max_depth=24 |
| 26 | 0.7271 | 0.0889 | n_estimators=300, min_samples_split=2, min_samples_leaf=1, max_features=sqrt, max_depth=24 |
| 27 | 0.7260 | 0.0907 | n_estimators=400, min_samples_split=5, min_samples_leaf=1, max_features=sqrt, max_depth=10 |
| 28 | 0.7225 | 0.1159 | n_estimators=800, min_samples_split=10, min_samples_leaf=4, max_features=sqrt, max_depth=10 |
| 29 | 0.7213 | 0.1102 | n_estimators=400, min_samples_split=10, min_samples_leaf=2, max_features=log2, max_depth=16 |
| 30 | 0.7180 | 0.1326 | n_estimators=400, min_samples_split=2, min_samples_leaf=4, max_features=log2, max_depth=None |

### smog — 30 trials

| Rank | Mean CV f1_macro | Std | Params |
|------|----------------|-----|--------|
| 1 | 0.7833 | 0.1047 | n_estimators=400, min_samples_split=2, min_samples_leaf=2, max_features=0.5, max_depth=10 |
| 2 | 0.7805 | 0.0918 | n_estimators=600, min_samples_split=10, min_samples_leaf=2, max_features=0.5, max_depth=None |
| 3 | 0.7773 | 0.1077 | n_estimators=600, min_samples_split=5, min_samples_leaf=2, max_features=0.5, max_depth=16 |
| 4 | 0.7745 | 0.1032 | n_estimators=600, min_samples_split=5, min_samples_leaf=1, max_features=0.5, max_depth=24 |
| 5 | 0.7737 | 0.0978 | n_estimators=800, min_samples_split=10, min_samples_leaf=1, max_features=0.5, max_depth=24 |
| 6 | 0.7670 | 0.0953 | n_estimators=200, min_samples_split=10, min_samples_leaf=1, max_features=0.5, max_depth=6 |
| 7 | 0.7582 | 0.1273 | n_estimators=200, min_samples_split=2, min_samples_leaf=1, max_features=0.5, max_depth=None |
| 8 | 0.7554 | 0.1228 | n_estimators=800, min_samples_split=10, min_samples_leaf=2, max_features=sqrt, max_depth=6 |
| 9 | 0.7532 | 0.1344 | n_estimators=400, min_samples_split=10, min_samples_leaf=2, max_features=log2, max_depth=16 |
| 10 | 0.7526 | 0.1223 | n_estimators=800, min_samples_split=5, min_samples_leaf=1, max_features=log2, max_depth=None |
| 11 | 0.7514 | 0.1165 | n_estimators=400, min_samples_split=5, min_samples_leaf=1, max_features=sqrt, max_depth=10 |
| 12 | 0.7480 | 0.1127 | n_estimators=400, min_samples_split=5, min_samples_leaf=1, max_features=sqrt, max_depth=24 |
| 13 | 0.7450 | 0.1216 | n_estimators=400, min_samples_split=10, min_samples_leaf=1, max_features=log2, max_depth=6 |
| 14 | 0.7361 | 0.1382 | n_estimators=200, min_samples_split=10, min_samples_leaf=1, max_features=log2, max_depth=None |
| 15 | 0.7345 | 0.1926 | n_estimators=400, min_samples_split=2, min_samples_leaf=4, max_features=0.5, max_depth=24 |
| 16 | 0.7329 | 0.1140 | n_estimators=200, min_samples_split=10, min_samples_leaf=1, max_features=sqrt, max_depth=6 |
| 17 | 0.7311 | 0.1939 | n_estimators=600, min_samples_split=10, min_samples_leaf=4, max_features=0.5, max_depth=24 |
| 18 | 0.7303 | 0.1880 | n_estimators=200, min_samples_split=10, min_samples_leaf=4, max_features=0.5, max_depth=24 |
| 19 | 0.7296 | 0.1397 | n_estimators=300, min_samples_split=5, min_samples_leaf=1, max_features=log2, max_depth=16 |
| 20 | 0.7281 | 0.1908 | n_estimators=300, min_samples_split=5, min_samples_leaf=4, max_features=0.5, max_depth=10 |
| 21 | 0.7245 | 0.1827 | n_estimators=400, min_samples_split=2, min_samples_leaf=4, max_features=0.5, max_depth=6 |
| 22 | 0.7223 | 0.1484 | n_estimators=300, min_samples_split=2, min_samples_leaf=1, max_features=sqrt, max_depth=24 |
| 23 | 0.7213 | 0.1473 | n_estimators=800, min_samples_split=2, min_samples_leaf=1, max_features=sqrt, max_depth=10 |
| 24 | 0.6867 | 0.2145 | n_estimators=400, min_samples_split=2, min_samples_leaf=4, max_features=sqrt, max_depth=10 |
| 25 | 0.6792 | 0.2103 | n_estimators=200, min_samples_split=2, min_samples_leaf=4, max_features=log2, max_depth=16 |
| 26 | 0.6776 | 0.2116 | n_estimators=400, min_samples_split=10, min_samples_leaf=4, max_features=sqrt, max_depth=16 |
| 27 | 0.6759 | 0.2116 | n_estimators=800, min_samples_split=10, min_samples_leaf=4, max_features=sqrt, max_depth=10 |
| 28 | 0.6752 | 0.2142 | n_estimators=200, min_samples_split=10, min_samples_leaf=4, max_features=log2, max_depth=6 |
| 29 | 0.6748 | 0.2078 | n_estimators=800, min_samples_split=2, min_samples_leaf=4, max_features=sqrt, max_depth=10 |
| 30 | 0.6743 | 0.2155 | n_estimators=400, min_samples_split=2, min_samples_leaf=4, max_features=log2, max_depth=None |

### influenza — 30 trials

| Rank | Mean CV f1_macro | Std | Params |
|------|----------------|-----|--------|
| 1 | 0.6701 | 0.1826 | n_estimators=200, min_samples_split=10, min_samples_leaf=1, max_features=log2, max_depth=None |
| 2 | 0.6654 | 0.1754 | n_estimators=400, min_samples_split=2, min_samples_leaf=4, max_features=log2, max_depth=None |
| 3 | 0.6568 | 0.1830 | n_estimators=800, min_samples_split=2, min_samples_leaf=4, max_features=sqrt, max_depth=10 |
| 4 | 0.6541 | 0.1985 | n_estimators=400, min_samples_split=5, min_samples_leaf=1, max_features=sqrt, max_depth=10 |
| 5 | 0.6522 | 0.1809 | n_estimators=400, min_samples_split=2, min_samples_leaf=4, max_features=sqrt, max_depth=10 |
| 6 | 0.6508 | 0.1766 | n_estimators=800, min_samples_split=10, min_samples_leaf=4, max_features=sqrt, max_depth=10 |
| 7 | 0.6496 | 0.1771 | n_estimators=800, min_samples_split=10, min_samples_leaf=2, max_features=sqrt, max_depth=6 |
| 8 | 0.6493 | 0.1914 | n_estimators=400, min_samples_split=5, min_samples_leaf=1, max_features=sqrt, max_depth=24 |
| 9 | 0.6490 | 0.1796 | n_estimators=200, min_samples_split=2, min_samples_leaf=4, max_features=log2, max_depth=16 |
| 10 | 0.6484 | 0.1746 | n_estimators=400, min_samples_split=10, min_samples_leaf=4, max_features=sqrt, max_depth=16 |
| 11 | 0.6472 | 0.1705 | n_estimators=400, min_samples_split=10, min_samples_leaf=1, max_features=log2, max_depth=6 |
| 12 | 0.6464 | 0.1838 | n_estimators=800, min_samples_split=2, min_samples_leaf=1, max_features=sqrt, max_depth=10 |
| 13 | 0.6462 | 0.2671 | n_estimators=300, min_samples_split=5, min_samples_leaf=4, max_features=0.5, max_depth=10 |
| 14 | 0.6461 | 0.1761 | n_estimators=200, min_samples_split=10, min_samples_leaf=1, max_features=sqrt, max_depth=6 |
| 15 | 0.6461 | 0.1702 | n_estimators=400, min_samples_split=10, min_samples_leaf=2, max_features=log2, max_depth=16 |
| 16 | 0.6444 | 0.1735 | n_estimators=200, min_samples_split=10, min_samples_leaf=4, max_features=log2, max_depth=6 |
| 17 | 0.6427 | 0.2569 | n_estimators=600, min_samples_split=10, min_samples_leaf=4, max_features=0.5, max_depth=24 |
| 18 | 0.6426 | 0.1885 | n_estimators=300, min_samples_split=2, min_samples_leaf=1, max_features=sqrt, max_depth=24 |
| 19 | 0.6402 | 0.1937 | n_estimators=300, min_samples_split=5, min_samples_leaf=1, max_features=log2, max_depth=16 |
| 20 | 0.6399 | 0.2455 | n_estimators=200, min_samples_split=10, min_samples_leaf=4, max_features=0.5, max_depth=24 |
| 21 | 0.6371 | 0.1896 | n_estimators=800, min_samples_split=5, min_samples_leaf=1, max_features=log2, max_depth=None |
| 22 | 0.6358 | 0.2691 | n_estimators=600, min_samples_split=5, min_samples_leaf=2, max_features=0.5, max_depth=16 |
| 23 | 0.6356 | 0.2723 | n_estimators=400, min_samples_split=2, min_samples_leaf=4, max_features=0.5, max_depth=24 |
| 24 | 0.6351 | 0.2692 | n_estimators=600, min_samples_split=10, min_samples_leaf=2, max_features=0.5, max_depth=None |
| 25 | 0.6351 | 0.2682 | n_estimators=200, min_samples_split=10, min_samples_leaf=1, max_features=0.5, max_depth=6 |
| 26 | 0.6344 | 0.2726 | n_estimators=600, min_samples_split=5, min_samples_leaf=1, max_features=0.5, max_depth=24 |
| 27 | 0.6325 | 0.2703 | n_estimators=400, min_samples_split=2, min_samples_leaf=4, max_features=0.5, max_depth=6 |
| 28 | 0.6317 | 0.2641 | n_estimators=800, min_samples_split=10, min_samples_leaf=1, max_features=0.5, max_depth=24 |
| 29 | 0.6283 | 0.2759 | n_estimators=200, min_samples_split=2, min_samples_leaf=1, max_features=0.5, max_depth=None |
| 30 | 0.6267 | 0.2747 | n_estimators=400, min_samples_split=2, min_samples_leaf=2, max_features=0.5, max_depth=10 |

## Artifacts

- `artifacts/candidate_model.joblib` — bundle of the three fitted Pipelines + feature list + reproducibility record.
- `artifacts/metrics.json` — per-disease CV winner + OOF metric suite.
- `artifacts/feature_importance.csv` — ranked Gini importances (permutation importance is Prompt 12).
- `artifacts/plots/` — confusion matrix, feature importance, and calibration (reliability) plot per disease.

> Scope: this prompt trains and tunes the candidate only. Held-out test evaluation, calibration tuning, robustness, permutation importance, and seasonality validation are Prompt 12. FastAPI, the Sprint 1 stub, and serving are untouched (Prompt 14).
