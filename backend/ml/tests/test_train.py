"""Tests for the Prompt 11 training pipeline.

Covers the four behaviours the prompt calls out:
- the self-contained Pipeline fits on a tiny fixture and the reloaded artifact
  predicts contract-shaped output (RiskLevel / Confidence / ModelVersion);
- cross-validation uses a time-aware splitter — no fold trains on the future and
  tests on the past, and a non-temporal splitter is rejected;
- the same seed yields the same chosen hyperparameters;
- training reads train.parquet only and never opens test.parquet.
"""

from __future__ import annotations

import numpy as np
import pandas as pd
import pytest

from ml.training import train

CITIES = ["Lahore", "Karachi"]
DISEASES = ["dengue", "smog"]
CLASSES = ["Low", "Medium", "High"]


# --- Fixtures ---------------------------------------------------------------


def _tiny_df(n_weeks: int = 24) -> pd.DataFrame:
    """A small, time-ordered, leakage-free-shaped frame with all three classes."""
    rng = np.random.default_rng(0)
    rows: list[dict] = []
    cycle = ["Low", "Medium", "High"]
    for w in range(1, n_weeks + 1):
        for ci, city in enumerate(CITIES):
            temp = 10.0 + (w % 12) * 2.0 + ci
            row = {
                "city": city,
                "iso_year": 2024,
                "week_of_year": w,
                "month": ((w - 1) // 4) % 12 + 1,
                "days_in_week": 7,
                "temperature": temp,
                "humidity": 50.0 + (w % 7),
                "precipitation": float(w % 5),
                "pm2_5": 30.0 + (w % 10),
                "pm10": 50.0 + (w % 10),
                "us_aqi": 80.0 + (w % 20),
                "aqi_available": True,
                "temperature_lag1": temp - 1.0,
                "humidity_lag1": 49.0 + (w % 7),
                "temperature_roll3": temp - 0.5,
                "temperature_anom": float(w % 3) if w > 6 else np.nan,
                "week_sin": np.sin(2 * np.pi * w / 52),
                "week_cos": np.cos(2 * np.pi * w / 52),
                "has_climatology": w > 6,
                "insufficient_lag_history": False,
            }
            for c in CITIES:
                row[f"city_{c}"] = int(c == city)
            # Learnable labels keyed off the week cycle; every class appears.
            label = cycle[(w + ci) % 3]
            for d in ("dengue", "smog", "influenza"):
                row[f"{d}_label"] = label
                row[f"{d}_label_sampled"] = label
            rows.append(row)
    return pd.DataFrame(rows)


def _tiny_cfg() -> dict:
    """A fast config: tiny forests, a 2-candidate search, 2 temporal folds."""
    return {
        "model_version": "rf-test-0.0.1",
        "random_state": 7,
        "diseases": list(DISEASES),
        "classes": list(CLASSES),
        "target_label": "label_sampled",
        "features": {
            "raw": ["temperature", "humidity", "us_aqi", "aqi_available"],
            "cyclical": ["week_sin", "week_cos"],
            "city_onehot_prefix": "city_",
            "include_patterns": {"lag": r"_lag\d+$", "anom": r"_anom$"},
        },
        "preprocessing": {"numeric_impute_strategy": "median", "scale": True},
        "random_forest": {"class_weight": "balanced", "bootstrap": True, "n_jobs": 1},
        "search": {
            "method": "randomized",
            "n_iter": 3,
            "scoring": "f1_macro",
            "refit": True,
            "n_jobs": 1,
            "cv": {"splitter": "time_series", "n_splits": 2},
            "param_grid": {
                "n_estimators": [12, 24],
                "max_depth": [None, 3],
                "min_samples_leaf": [1, 2],
                "min_samples_split": [2],
                "max_features": ["sqrt"],
            },
        },
        "evaluation": {
            "low_confidence_threshold": 0.55,
            "calibration_bins": 5,
            "importance_top_n": 5,
        },
    }


# --- Feature selection ------------------------------------------------------


def test_feature_selection_excludes_keys_labels_and_flags() -> None:
    df = _tiny_df()
    feats = train.select_feature_columns(df, _tiny_cfg()["features"])
    # Picked up the documented families…
    assert "temperature" in feats
    assert "temperature_lag1" in feats
    assert "temperature_anom" in feats
    assert "week_sin" in feats and "city_Lahore" in feats
    # …and excluded keys, QA/helper columns, flags, and every label column.
    for banned in ("city", "iso_year", "week_of_year", "month", "days_in_week",
                   "has_climatology", "insufficient_lag_history",
                   "dengue_label", "dengue_label_sampled"):
        assert banned not in feats


# --- Time-aware CV ----------------------------------------------------------


def test_build_cv_rejects_non_temporal_splitter() -> None:
    cfg = _tiny_cfg()
    cfg["search"]["cv"]["splitter"] = "kfold"
    with pytest.raises(ValueError, match="time-aware"):
        train.build_cv(cfg["search"])


def test_cv_has_no_future_in_train_for_past_test() -> None:
    """Every fold's training rows must be no later than its test rows."""
    df = train.time_sort(_tiny_df())
    cv = train.build_cv(_tiny_cfg()["search"])
    t = (df["iso_year"] * 100 + df["week_of_year"]).to_numpy()
    n_folds = 0
    for tr_idx, te_idx in cv.split(df):
        assert t[tr_idx].max() <= t[te_idx].min()  # past trains, future tests
        assert tr_idx.max() < te_idx.min()         # contiguous, ordered blocks
        n_folds += 1
    assert n_folds == 2


# --- Fit, persist, reload, predict ------------------------------------------


def test_train_fits_persists_reloads_and_predicts(tmp_path) -> None:
    from joblib import load

    df = _tiny_df()
    cfg = _tiny_cfg()
    bundle, runs, feature_names = train.train_all(df, cfg)

    # Bundle shape + a Pipeline per disease.
    assert set(bundle["models"]) == set(DISEASES)
    assert bundle["feature_names"] == feature_names
    assert bundle["model_version"] == "rf-test-0.0.1"

    out = train.save_artifacts(bundle, runs, cfg, artifacts_dir=tmp_path)
    assert out["model"].exists() and out["metrics"].exists()
    assert out["importance"].exists()
    assert (tmp_path / "plots" / "confusion_matrix_dengue.png").exists()

    # Reload with a bare joblib.load (no training internals needed)…
    reloaded = load(out["model"])
    preds = train.predict_risk(reloaded, "dengue", df.head(3))
    assert len(preds) == 3
    for p in preds:
        assert p["risk_level"] in CLASSES
        assert 0.0 <= p["confidence"] <= 1.0
        assert p["model_version"] == "rf-test-0.0.1"
        assert isinstance(p["low_confidence"], bool)


def test_bundle_carries_the_configured_low_confidence_threshold() -> None:
    """Sprint M6.1: the artifact must carry `low_confidence_threshold` sourced
    from `cfg["evaluation"]["low_confidence_threshold"]` — the single source of
    truth every inference component reads instead of a hardcoded constant."""
    df = _tiny_df()
    cfg = _tiny_cfg()
    cfg["evaluation"]["low_confidence_threshold"] = 0.72
    bundle, _runs, _feats = train.train_all(df, cfg)
    assert bundle["low_confidence_threshold"] == 0.72


def test_predict_risk_uses_the_bundles_configured_threshold() -> None:
    """Changing `evaluation.low_confidence_threshold` and retraining changes the
    `low_confidence` flag `predict_risk` reports — proving it is artifact-driven,
    not the old hardcoded `0.55`."""
    df = _tiny_df()

    cfg_permissive = _tiny_cfg()
    cfg_permissive["evaluation"]["low_confidence_threshold"] = 0.0
    bundle_permissive, _runs, _feats = train.train_all(df, cfg_permissive)

    cfg_strict = _tiny_cfg()
    cfg_strict["evaluation"]["low_confidence_threshold"] = 1.0
    bundle_strict, _runs, _feats = train.train_all(df, cfg_strict)

    row = df.head(1)
    preds_permissive = train.predict_risk(bundle_permissive, "dengue", row)
    preds_strict = train.predict_risk(bundle_strict, "dengue", row)

    assert preds_permissive[0]["low_confidence"] is False
    assert preds_strict[0]["low_confidence"] is True


def test_predict_risk_falls_back_for_a_bundle_without_the_field() -> None:
    """A bundle built before Sprint M6.1 (no stored threshold) must reproduce the
    prior hardcoded behaviour (0.55), not raise or silently use 0."""
    df = _tiny_df()
    cfg = _tiny_cfg()
    bundle, _runs, _feats = train.train_all(df, cfg)
    del bundle["low_confidence_threshold"]  # simulate a pre-M6.1 artifact

    row = df.head(1)
    preds = train.predict_risk(bundle, "dengue", row)
    assert isinstance(preds[0]["low_confidence"], bool)
    expected = preds[0]["confidence"] < train._LEGACY_LOW_CONFIDENCE_THRESHOLD
    assert preds[0]["low_confidence"] == expected


def test_feature_importance_csv_is_ranked_per_disease(tmp_path) -> None:
    df = _tiny_df()
    cfg = _tiny_cfg()
    bundle, runs, _ = train.train_all(df, cfg)
    out = train.save_artifacts(bundle, runs, cfg, artifacts_dir=tmp_path)
    imp = pd.read_csv(out["importance"])
    assert set(imp["disease"]) == set(DISEASES)
    for d in DISEASES:
        ranks = imp[imp["disease"] == d]["rank"].tolist()
        assert ranks == sorted(ranks)              # ranked 1..n
        assert ranks[0] == 1


# --- Reproducibility --------------------------------------------------------


def test_same_seed_yields_same_chosen_params() -> None:
    df = train.time_sort(_tiny_df())
    cfg = _tiny_cfg()
    feats = train.select_feature_columns(df, cfg["features"])
    X = train.feature_frame(df, feats)
    y = df["dengue_label_sampled"].astype(str)

    s1 = train.run_search(train.build_estimator(cfg), X, y, cfg)
    s2 = train.run_search(train.build_estimator(cfg), X, y, cfg)
    assert s1.best_params_ == s2.best_params_


# --- Scope guard: never read the test set -----------------------------------


def test_training_never_reads_test_parquet(tmp_path, monkeypatch) -> None:
    seen: list[str] = []
    real = pd.read_parquet

    def spy(path, *args, **kwargs):
        seen.append(str(path))
        return real(path, *args, **kwargs)

    monkeypatch.setattr(train.pd, "read_parquet", spy)

    train_path = tmp_path / "train.parquet"
    _tiny_df().to_parquet(train_path, index=False)
    train.load_train(train_path)

    assert seen == [str(train_path)]
    assert not any(s.replace("\\", "/").endswith("test.parquet") for s in seen)
