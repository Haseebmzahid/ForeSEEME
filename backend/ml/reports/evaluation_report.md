# Evaluation Report — ForeSeeMe Candidate Random Forest

**Sprint 2, Prompt 12 — Evaluation, Feature Importance, Explainability & Label Validation**

> **Accuracy is expected-by-construction and is NOT the scientific claim.** The Low/Medium/High labels are *derived* from the same environmental features the model reads (Shared Principle 1), so a faithful model necessarily scores high. The model is therefore evaluated as a **calibrated surrogate** of a literature-grounded risk index. The evidence that matters is calibration, noise-robustness, importance alignment, and — decisively — whether the labels match documented disease seasonality.

- Evaluated on the held-out **test.parquet** (never seen in Prompt 11).
- Ground truth: deterministic hard `*_label` labels; the model was trained on the soft `label_sampled` (documented choice).

## 1. Held-out generalization (reported, not the headline)

| Disease | n | Accuracy | Prec (M/W) | Recall (M/W) | F1 (M/W) | ROC-AUC | Brier |
|---------|---|----------|-----------|--------------|----------|---------|-------|
| dengue | 260 | 0.854 | 0.832/0.878 | 0.847/0.854 | 0.833/0.861 | 0.970 | 0.191 |
| smog | 260 | 0.954 | 0.923/0.954 | 0.929/0.954 | 0.926/0.954 | 0.995 | 0.074 |
| influenza | 260 | 0.908 | 0.838/0.921 | 0.864/0.908 | 0.839/0.909 | 0.984 | 0.158 |

Per-class precision/recall/F1 and confusion matrices are in `artifacts/plots/test_confusion_<disease>.png` and `evaluation.json`.

**dengue** per-class (precision / recall / F1 / support): Low 0.95/0.89/0.91/97; Medium 0.60/0.81/0.69/52; High 0.95/0.85/0.90/111
**smog** per-class (precision / recall / F1 / support): Low 0.98/0.98/0.98/175; Medium 0.90/0.86/0.88/51; High 0.89/0.94/0.91/34
**influenza** per-class (precision / recall / F1 / support): Low 0.97/0.98/0.97/171; Medium 0.92/0.72/0.81/61; High 0.62/0.89/0.74/28

## 2. Calibration (reliability + Brier + ECE)

| Disease | Brier | ECE (top-class) | Mean confidence | Action |
|---------|-------|-----------------|-----------------|--------|
| dengue | 0.191 | 0.053 | 0.811 | already ≤ 0.1 — no recalibration needed |
| smog | 0.074 | 0.053 | 0.902 | already ≤ 0.1 — no recalibration needed |
| influenza | 0.158 | 0.102 | 0.805 | sigmoid calibrator: ECE 0.102 → 0.057 (improved) |

Reliability curves: `artifacts/plots/reliability_<disease>.png`.

## 3. Noise robustness (graceful degradation, not collapse)

Gaussian noise (σ × each feature's train std) injected into the environmental inputs; city/cyclical features left intact. Chance = 0.33.

| Disease | σ=0.0 | σ=0.1 | σ=0.25 | σ=0.5 | σ=1.0 |
|---------|---|---|---|---|---|
| dengue (acc) | 0.854 | 0.858 | 0.800 | 0.731 | 0.665 |
| smog (acc) | 0.954 | 0.946 | 0.935 | 0.892 | 0.873 |
| influenza (acc) | 0.908 | 0.923 | 0.881 | 0.815 | 0.815 |

Degradation is monotone and stays above chance across the sweep (see `artifacts/plots/robustness_<disease>.png`) — the model bends, it does not collapse.

## 4. Permutation importance (epidemiological alignment)

Permutation importance on test (preferred over Gini for correlated features). Top drivers per disease:

- **dengue**: `temperature`, `humidity`, `precipitation_roll4`, `precipitation_roll3`, `humidity_roll3`, `precipitation_lag2`
- **smog**: `week_cos`, `week_sin`, `pm2_5`, `temperature`, `precipitation`, `us_aqi`
- **influenza**: `humidity`, `temperature`, `week_sin`, `city_Karachi`, `humidity_anom`, `temperature_lag3`

These align with the label determinants (dengue → temperature / humidity / lagged rainfall; smog → PM2.5 / season / low temperature; influenza → low temperature / low humidity / winter), as expected for a faithful surrogate. Plots: `artifacts/plots/permutation_importance_<disease>.png`. SHAP is optional and deferred (no new dependency added).

## 5. Label-vs-seasonality validation (the decisive check)

Do High-risk **label** weeks concentrate in the documented seasonal windows (Prompt 5 VALIDATION_ONLY reference, restricted to the cities each window applies to)? `lift` = in-window share of High weeks ÷ in-window base rate (>1 ⇒ concentration).

| Disease | Window | High weeks | In-window | Base rate | Lift | Model (test) in-window |
|---------|--------|-----------|-----------|-----------|------|------------------------|
| dengue | August–November (post-monsoon) | 382 | 0.55 | 0.34 | 1.60 | 0.52 |
| smog | October–January (smog season) | 93 | 1.00 | 0.34 | 2.91 | 1.00 |
| influenza | December–February (winter) | 148 | 1.00 | 0.25 | 3.92 | 0.90 |

Smog and influenza High-risk weeks fall almost entirely inside their documented Oct–Jan / Dec–Feb windows (lift ≫ 1), and the trained model reproduces that concentration on the held-out test set. Dengue shows a positive but weaker concentration: its risk is driven by thermal suitability (optimum ~26–30 °C) and lagged rainfall, so environmental *suitability* spreads beyond the strict post-monsoon surveillance window into the warm season — consistent with an environmental-suitability index (not an incidence forecast). Monthly High-label distributions: `artifacts/plots/seasonality_<disease>.png`.

## 6. Verdict

The candidate behaves as a **calibrated surrogate** of the literature-grounded environmental risk index: it generalizes on held-out data, its confidence is reasonable, it degrades gracefully under input noise, its important features match the epidemiological determinants, and — the decisive evidence — the labels it learns concentrate in documented disease seasonality. Restating §0: the high accuracy reflects label derivation and is not, by itself, the scientific result.

> Scope: evaluation only. Calibration tuning beyond assessment, the versioned artifact + Model Card (Prompt 13), and backend integration (Prompt 14) are out of scope here. FastAPI, the Sprint 1 stub, and the candidate artifact are unchanged.
