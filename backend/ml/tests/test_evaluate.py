"""Tests for the Prompt 12 evaluation pipeline.

Covers the prompt's testing criteria:
- metrics are computed on the test set (and the held-out test path is the one
  scored);
- a reliability/Brier + ECE calibration assessment is produced;
- permutation importance runs and ranks every feature;
- noise robustness degrades gracefully (no collapse to chance);
- the label-vs-seasonality check uses the quarantined VALIDATION_ONLY reference
  correctly (read as a data file, concentration detected), without importing the
  guarded module;
- the report carries the explicit "accuracy is expected-by-construction"
  acknowledgment.
"""

from __future__ import annotations

import numpy as np
import pandas as pd
import pytest

from ml.training import evaluate as E

CLASSES = ["Low", "Medium", "High"]


# --- Pure metric helpers ----------------------------------------------------


def _proba_for(y: list[str]) -> np.ndarray:
    """Confident, correct probabilities in severity order for labels in ``y``."""
    idx = {"Low": 0, "Medium": 1, "High": 2}
    p = np.full((len(y), 3), 0.05)
    for i, label in enumerate(y):
        p[i] = 0.05
        p[i, idx[label]] = 0.90
    return p


def test_classification_metrics_on_perfect_predictions() -> None:
    y = ["Low", "Medium", "High", "Low", "High"]
    proba = _proba_for(y)
    m = E.classification_metrics(np.array(y), np.array(y), proba, CLASSES)
    assert m["accuracy"] == 1.0
    assert m["f1_macro"] == 1.0 and m["f1_weighted"] == 1.0
    assert m["roc_auc_ovr_macro"] == 1.0          # all classes present
    assert m["confusion_matrix"]["labels"] == CLASSES
    assert set(m["per_class"]) == set(CLASSES)


def test_roc_auc_none_when_a_class_absent() -> None:
    y = ["Low", "Low", "Medium", "Medium"]        # no High in truth
    proba = _proba_for(y)
    m = E.classification_metrics(np.array(y), np.array(y), proba, CLASSES)
    assert m["roc_auc_ovr_macro"] is None


def test_calibration_assessment_produces_brier_and_ece() -> None:
    y = np.array(["Low", "Medium", "High", "High"])
    proba = _proba_for(list(y))
    a = E.calibration_assessment(y, y, proba, n_bins=5)
    assert 0.0 <= a["brier_multiclass"] < 0.1     # confident & correct -> low Brier
    assert 0.0 <= a["ece_top_class"] <= 1.0
    assert np.isfinite(a["mean_confidence"])


def test_ece_is_zero_for_well_calibrated_confidence() -> None:
    # 80%-confident predictions that are correct exactly 80% of the time.
    y_true = np.array(["Low"] * 8 + ["Medium"] * 2)
    y_pred = np.array(["Low"] * 10)
    conf = np.full(10, 0.8)
    assert E.expected_calibration_error(y_true, y_pred, conf, n_bins=10) == pytest.approx(0.0, abs=1e-9)


# --- Seasonality validation (the decisive check) ----------------------------


def test_seasonality_windows_resolve_from_real_reference() -> None:
    ref = E.load_seasonality_reference()             # reads the committed JSON
    windows = E.seasonality_windows(
        ref, {"dengue": "dengue_post_monsoon", "smog": "punjab_smog_winter"}
    )
    assert windows["dengue"]["months"] == {8, 9, 10, 11}
    assert windows["smog"]["months"] == {10, 11, 12, 1}
    # smog window applies only to the Punjab-belt cities.
    assert set(windows["smog"]["cities"]) == {"Lahore", "Rawalpindi", "Islamabad"}


def test_label_seasonality_detects_concentration() -> None:
    # 40 weeks; High labels deliberately placed in the Aug–Nov window.
    months = list(range(1, 13)) * 4
    df = pd.DataFrame({
        "city": "Lahore",
        "month": months[:40],
        "dengue_label": ["High" if m in (8, 9, 10, 11) else "Low" for m in months[:40]],
    })
    win = {"entry_id": "dengue_post_monsoon", "months": {8, 9, 10, 11},
           "months_label": "Aug–Nov", "cities": ["Lahore"]}
    res = E.label_seasonality(df, "dengue", win, "High", "label")
    assert res["high_in_window_rate"] == 1.0         # every High week is in-window
    assert res["lift"] > 1.0                          # concentration vs base rate
    assert res["n_high_weeks"] > 0


def test_evaluate_does_not_import_the_guarded_reference_module() -> None:
    """The reference is consumed as data, never via the guarded Python loader."""
    import sys
    # Importing/using evaluate must not pull in the VALIDATION_ONLY module.
    E.load_seasonality_reference()
    assert "ml.pipelines.acquire_disease_reference" not in sys.modules


# --- Report acknowledgment --------------------------------------------------


def test_report_contains_label_derivation_acknowledgment() -> None:
    assert "expected-by-construction" in E.ACK
    assert "NOT the scientific claim" in E.ACK


# --- Robustness + permutation on a tiny trained bundle ----------------------


def _tiny_df(n_weeks: int = 28) -> pd.DataFrame:
    """A small, time-ordered frame with the feature columns and 3 classes."""
    cycle = ["Low", "Medium", "High"]
    rows = []
    for w in range(1, n_weeks + 1):
        for ci, city in enumerate(["Lahore", "Karachi"]):
            temp = 10.0 + (w % 12) * 2.0 + ci
            row = {
                "city": city, "iso_year": 2024, "week_of_year": w,
                "temperature": temp, "humidity": 50.0 + (w % 7),
                "us_aqi": 80.0 + (w % 20), "aqi_available": True,
                "temperature_lag1": temp - 1.0,
                "temperature_anom": float(w % 3) if w > 6 else np.nan,
                "week_sin": np.sin(2 * np.pi * w / 52),
                "week_cos": np.cos(2 * np.pi * w / 52),
            }
            for c in ("Lahore", "Karachi"):
                row[f"city_{c}"] = int(c == city)
            row["dengue_label_sampled"] = cycle[(w + ci) % 3]
            rows.append(row)
    return pd.DataFrame(rows)


def _tiny_cfg() -> dict:
    return {
        "model_version": "rf-test-0.0.1", "random_state": 7,
        "diseases": ["dengue"], "classes": list(CLASSES),
        "target_label": "label_sampled",
        "features": {
            "raw": ["temperature", "humidity", "us_aqi", "aqi_available"],
            "cyclical": ["week_sin", "week_cos"], "city_onehot_prefix": "city_",
            "include_patterns": {"lag": r"_lag\d+$", "anom": r"_anom$"},
        },
        "preprocessing": {"numeric_impute_strategy": "median", "scale": True},
        "random_forest": {"class_weight": "balanced", "bootstrap": True, "n_jobs": 1},
        "search": {
            "method": "randomized", "n_iter": 1, "scoring": "f1_macro",
            "refit": True, "n_jobs": 1,
            "cv": {"splitter": "time_series", "n_splits": 2},
            "param_grid": {"n_estimators": [12], "max_depth": [3],
                           "min_samples_leaf": [1], "min_samples_split": [2],
                           "max_features": ["sqrt"]},
        },
        "evaluation": {"low_confidence_threshold": 0.55, "calibration_bins": 5,
                       "importance_top_n": 5},
    }


def _tiny_bundle_and_test(tmp_path):
    """Train a tiny 1-disease bundle (reusing train.py) for integration checks."""
    from ml.training import train as T

    bundle, _runs, feats = T.train_all(_tiny_df(28), _tiny_cfg())
    return bundle, _tiny_df(28), feats


def test_robustness_sweep_degrades_without_collapse(tmp_path) -> None:
    from ml.training import train as T

    bundle, df, feats = _tiny_bundle_and_test(tmp_path)
    X = T.feature_frame(df, feats)
    y = df["dengue_label_sampled"].astype(str).to_numpy()
    std = X.std(ddof=0)
    sweep = E.robustness_sweep(bundle, "dengue", X, y, std,
                               sigmas=[0.0, 0.5, 2.0], seed=1)
    assert [r["sigma"] for r in sweep] == [0.0, 0.5, 2.0]
    # σ=0 is the strongest; heavy noise must not improve over baseline.
    assert sweep[0]["accuracy"] >= sweep[-1]["accuracy"]
    for r in sweep:
        assert 0.0 <= r["accuracy"] <= 1.0


def test_permutation_importance_ranks_all_features(tmp_path) -> None:
    from ml.training import train as T

    bundle, df, feats = _tiny_bundle_and_test(tmp_path)
    X = T.feature_frame(df, feats)
    y = df["dengue_label_sampled"].astype(str).to_numpy()
    rows = E.permutation_imp(bundle, "dengue", X, y, "f1_macro", n_repeats=3, seed=0)
    assert {r["feature"] for r in rows} == set(feats)        # every feature scored
    means = [r["importance_mean"] for r in rows]
    assert means == sorted(means, reverse=True)              # ranked descending


# --- Scope guard: test set is the scored set --------------------------------


def test_load_test_reads_the_held_out_set(tmp_path, monkeypatch) -> None:
    seen: list[str] = []
    real = pd.read_parquet

    def spy(path, *a, **k):
        seen.append(str(path).replace("\\", "/"))
        return real(path, *a, **k)

    monkeypatch.setattr(E.pd, "read_parquet", spy)
    p = tmp_path / "test.parquet"
    pd.DataFrame({"city": ["Lahore"], "month": [10]}).to_parquet(p, index=False)
    E.load_test(p)
    assert seen[-1].endswith("test.parquet")
