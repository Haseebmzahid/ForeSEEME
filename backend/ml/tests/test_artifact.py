"""Tests for the promoted production artifact & Model Card (Prompt 13).

Verifies the acceptance criteria:
- the versioned artifact loads with a bare joblib.load and predicts
  contract-shaped output (RiskLevel / Confidence / ModelVersion);
- metrics.json matches the Prompt 12 evaluation (no drift);
- the reproducibility record is present and complete;
- the version string parses as semver;
- the Model Card is honest (no outbreak/clinical overclaim) and links the
  label-methodology doc.
"""

from __future__ import annotations

import json
from pathlib import Path

import pandas as pd
from joblib import load

from ml.pipelines import paths
from ml.training import persist
from ml.training import train as T

ARTIFACTS = paths.ARTIFACTS_DIR
CLASSES = {"Low", "Medium", "High"}


def _model_path() -> Path:
    # Sprint M6.2: reuses the same semver-aware selection production uses
    # (previously this duplicated the old, non-semver-safe `sorted(glob)[-1]`
    # logic locally, so this test could silently drift from what
    # `app.predict.resolve_artifact_path` actually loads).
    found = paths.latest_model_artifact(ARTIFACTS)
    assert found, "no model_<version>.joblib present — run `python -m ml.training.persist`"
    return found


def _metrics() -> dict:
    return json.loads((ARTIFACTS / "metrics.json").read_text(encoding="utf-8"))


def _evaluation() -> dict:
    return json.loads((ARTIFACTS / "evaluation.json").read_text(encoding="utf-8"))


# --- Semver -----------------------------------------------------------------


def test_is_semver_accepts_and_rejects() -> None:
    assert persist.is_semver("1.0.0")
    assert persist.is_semver("2.3.4-rc.1")
    assert not persist.is_semver("1.0")
    assert not persist.is_semver("v1.0.0")
    assert not persist.is_semver("rf-1.0.0")


def test_artifact_version_is_semver() -> None:
    bundle = load(_model_path())
    assert persist.is_semver(bundle["version"])
    assert persist.is_semver(_metrics()["version"])


def test_persist_semver_is_the_same_definition_as_paths_not_a_copy() -> None:
    """Sprint M6.2: `persist.is_semver`/`persist.SEMVER_RE` are re-exports of
    `ml.pipelines.paths`, not a second, independently-maintained definition —
    the same rules validate a version on write (promote) and on read
    (resolve_artifact_path)."""
    assert persist.is_semver is paths.is_semver
    assert persist.SEMVER_RE is paths.SEMVER_RE


# --- Loads & predicts contract-shaped output --------------------------------


def test_artifact_loads_and_predicts_contract_shape() -> None:
    bundle = load(_model_path())
    # Use the existing small training fixture to exercise the artifact's imputer.
    sample = _tiny_train_df().head(4).reindex(columns=bundle["feature_names"])
    _assert_prediction_contract(bundle, sample)


def test_artifact_predicts_contract_shape_on_frozen_holdout(frozen_ml_split) -> None:
    sample = frozen_ml_split("test").head(4)
    bundle = load(_model_path())                 # bare load, no custom class
    _assert_prediction_contract(bundle, sample)


def _assert_prediction_contract(bundle, test_df):
    assert set(bundle["models"]) == set(bundle["diseases"])
    for disease in bundle["diseases"]:
        preds = T.predict_risk(bundle, disease, test_df)
        assert len(preds) == 4
        for p in preds:
            assert p["risk_level"] in CLASSES
            assert 0.0 <= p["confidence"] <= 1.0
            assert p["model_version"] == bundle["model_version"]
            assert isinstance(p["low_confidence"], bool)


def test_prediction_model_version_matches_release() -> None:
    bundle = load(_model_path())
    cfg = T.load_model_config()
    assert bundle["model_version"] == cfg["release"]["model_version"]
    assert f"model_{bundle['version']}.joblib" == _model_path().name


# --- metrics.json matches the evaluation report -----------------------------


def test_metrics_match_evaluation_no_drift() -> None:
    metrics = _metrics()
    evaluation = _evaluation()
    assert metrics["model_version"] == load(_model_path())["model_version"]
    for disease, ev in evaluation["per_disease"].items():
        t = metrics["per_disease"][disease]["test"]
        em = ev["metrics"]
        for key in ("accuracy", "f1_macro", "f1_weighted", "roc_auc_ovr_macro",
                    "brier_multiclass", "precision_macro", "recall_macro"):
            assert t[key] == em[key], f"{disease}.{key} drifted from evaluation.json"
        # Seasonality lift carried through unchanged.
        assert (metrics["per_disease"][disease]["label_seasonality"]["lift"]
                == ev["label_seasonality"]["lift"])


# --- Reproducibility record present and complete ----------------------------


def test_reproducibility_record_complete() -> None:
    repro = _metrics()["reproducibility"]
    for key in ("seed", "target_label", "config_sha256", "candidate_sha256",
                "train_sha256", "test_sha256", "feature_count", "library_versions"):
        assert repro.get(key) not in (None, ""), f"missing reproducibility field {key}"
    for lib in ("python", "scikit-learn", "numpy", "pandas", "scipy", "joblib"):
        assert repro["library_versions"].get(lib), f"missing library version {lib}"
    # Hashes look like sha256.
    assert len(repro["train_sha256"]) == 64
    assert len(repro["config_sha256"]) == 64
    # The bundle carries the same record.
    assert load(_model_path())["reproducibility"]["config_sha256"] == repro["config_sha256"]


# --- Reproducibility: inherited, not recomputed (Sprint M6.3) ---------------


def test_promotion_inherits_the_candidates_own_reproducibility_record(tmp_path) -> None:
    """Promotion must INHERIT the candidate's already-computed reproducibility
    record (`ml.training.train.build_reproducibility_record`, the one
    authoritative implementation) rather than recomputing an independent copy —
    proving there is one implementation, not two that merely happen to agree."""
    candidate = {
        "model_version": "rf-candidate-test",
        "random_state": 42,
        "target_label": "label_sampled",
        "feature_names": ["temperature", "humidity", "us_aqi"],
        "reproducibility": {
            "seed": 42,
            "target_label": "label_sampled",
            "feature_count": 3,
            "generated_at": "2026-01-01T00:00:00+00:00",
            "config_sha256": "c" * 64,
            "train_sha256": "a" * 64,
            "test_sha256": "b" * 64,
            "split_manifest": {"train_sha256": "a" * 64, "test_sha256": "b" * 64},
            "library_versions": {"python": "3.13.0", "scikit-learn": "1.5.0",
                                  "numpy": "2.0.0", "pandas": "2.2.0",
                                  "scipy": "1.14.0", "joblib": "1.4.0"},
        },
    }
    candidate_file = tmp_path / "candidate_model.joblib"
    candidate_file.write_bytes(b"fake artifact bytes")

    repro = persist.reproducibility_record(candidate, candidate_file)

    # Every field the candidate already computed survives unchanged...
    for key in ("seed", "target_label", "feature_count", "generated_at",
                "config_sha256", "train_sha256", "test_sha256",
                "split_manifest", "library_versions"):
        assert repro[key] == candidate["reproducibility"][key]
    # ...plus the two fields that can only exist once promotion happens.
    assert repro["candidate_sha256"] == T._sha256_file(candidate_file)
    assert "promoted_at" in repro


def test_promotion_backward_compatible_with_a_pre_m63_candidate(tmp_path) -> None:
    """A candidate built before Sprint M6.3 lacks `seed`/`target_label`/
    `feature_count`/`config_sha256`/`generated_at` inside its reproducibility
    dict (persist.py used to compute those independently at promotion time
    instead) and has three separate `*_version` keys rather than a unified
    `library_versions`. Promoting it must not crash — only what can be
    HONESTLY derived from fields the candidate has always carried is
    backfilled; nothing is fabricated."""
    old_candidate = {
        "model_version": "rf-candidate-legacy",
        "random_state": 7,
        "target_label": "label_sampled",
        "feature_names": ["temperature", "humidity"],
        "reproducibility": {
            "sklearn_version": "1.3.0",
            "numpy_version": "1.26.0",
            "pandas_version": "2.1.0",
            "train_sha256": "a" * 64,
            "split_manifest": {"train_sha256": "a" * 64, "test_sha256": "b" * 64},
        },
    }
    candidate_file = tmp_path / "candidate_model.joblib"
    candidate_file.write_bytes(b"legacy artifact bytes")

    repro = persist.reproducibility_record(old_candidate, candidate_file)

    assert repro["seed"] == 7                        # backfilled from random_state
    assert repro["target_label"] == "label_sampled"   # backfilled
    assert repro["feature_count"] == 2                # backfilled from feature_names
    assert repro["test_sha256"] == "b" * 64           # backfilled from split_manifest
    assert repro["library_versions"] == {
        "scikit-learn": "1.3.0", "numpy": "1.26.0", "pandas": "2.1.0",
    }
    assert "config_sha256" not in repro   # honestly absent — never fabricated
    assert repro["candidate_sha256"]      # always fresh, regardless of candidate age


def test_model_card_renders_honestly_for_legacy_reproducibility(tmp_path) -> None:
    """`render_model_card` must not crash on a promoted-from-legacy-candidate
    record that lacks `config_sha256` — it should say so plainly instead of
    KeyError-ing or fabricating a hash."""
    old_candidate = {
        "model_version": "rf-candidate-legacy",
        "random_state": 7,
        "target_label": "label_sampled",
        "feature_names": ["temperature", "humidity"],
        "diseases": ["dengue"],
        "best_params": {"dengue": {}},
        "reproducibility": {
            "sklearn_version": "1.3.0", "numpy_version": "1.26.0",
            "pandas_version": "2.1.0", "train_sha256": "a" * 64,
            "split_manifest": {"train_sha256": "a" * 64, "test_sha256": "b" * 64},
        },
    }
    candidate_file = tmp_path / "candidate_model.joblib"
    candidate_file.write_bytes(b"legacy artifact bytes")
    evaluation = {
        "evaluated_on": "test.parquet",
        "test_target_label": "label",
        "per_disease": {
            "dengue": {
                "metrics": {
                    "accuracy": 0.9, "f1_macro": 0.9, "roc_auc_ovr_macro": 0.9,
                    "brier_multiclass": 0.1, "precision_macro": 0.9,
                    "recall_macro": 0.9, "precision_weighted": 0.9,
                    "recall_weighted": 0.9, "f1_weighted": 0.9,
                    "n": 10, "per_class": {}, "confusion_matrix": {},
                },
                "calibration": {"ece_top_class": 0.05},
                "recalibration": None,
                "label_seasonality": {"window_label": "x", "high_in_window_rate": 0.9,
                                       "base_rate": 0.5, "lift": 1.8},
            }
        },
    }
    cfg = {"release": {"version": "9.9.9", "model_version": "rf-9.9.9"},
           "model_version": "rf-candidate-legacy", "classes": ["Low", "Medium", "High"]}

    repro = persist.reproducibility_record(old_candidate, candidate_file)
    metrics = persist.build_metrics(cfg, old_candidate, evaluation, repro)
    card = persist.render_model_card(metrics, cfg)  # must not raise

    assert "unavailable (pre-m6.3 candidate)" in card.lower()
    assert "candidate hash" in card.lower()


# --- Metrics lifecycle: unambiguous responsibilities (Sprint M6.3) ----------


def test_candidate_and_promoted_metrics_files_never_share_a_name(tmp_path) -> None:
    """The candidate stage's OOF metrics and the promoted stage's held-out
    metrics must never collide on `metrics.json` again (the audit finding: the
    old shared filename meant promoting silently overwrote the candidate's own
    numbers, and `training_log.md`'s description of the file went stale)."""
    df = _tiny_train_df()
    cfg = _tiny_train_cfg()
    bundle, runs, _feats = T.train_all(df, cfg)
    out = T.save_artifacts(bundle, runs, cfg, artifacts_dir=tmp_path)

    assert out["candidate_metrics"].name == "candidate_metrics.json"
    assert out["candidate_metrics"].name != "metrics.json"
    candidate_metrics = json.loads(out["candidate_metrics"].read_text(encoding="utf-8"))
    # The candidate file reports OOF metrics per disease (train.py's own shape) —
    # not the held-out `test`/`calibration`/`label_seasonality` shape persist.py
    # writes to metrics.json.
    assert "per_disease" in candidate_metrics
    for disease_metrics in candidate_metrics["per_disease"].values():
        assert "best_cv_score" in disease_metrics  # candidate-stage-only field


def _tiny_train_df() -> pd.DataFrame:
    import numpy as np

    rows = []
    cycle = ["Low", "Medium", "High"]
    for w in range(1, 25):
        for ci, city in enumerate(["Lahore", "Karachi"]):
            temp = 10.0 + (w % 12) * 2.0 + ci
            row = {
                "city": city, "iso_year": 2024, "week_of_year": w,
                "temperature": temp, "humidity": 50.0 + (w % 7),
                "us_aqi": 80.0 + (w % 20), "aqi_available": True,
                "week_sin": float(np.sin(2 * np.pi * w / 52)),
                "week_cos": float(np.cos(2 * np.pi * w / 52)),
                "city_Lahore": int(city == "Lahore"),
                "city_Karachi": int(city == "Karachi"),
            }
            row["dengue_label_sampled"] = cycle[(w + ci) % 3]
            rows.append(row)
    return pd.DataFrame(rows)


def _tiny_train_cfg() -> dict:
    return {
        "model_version": "rf-test-0.0.1", "random_state": 7,
        "diseases": ["dengue"], "classes": ["Low", "Medium", "High"],
        "target_label": "label_sampled",
        "features": {
            "raw": ["temperature", "humidity", "us_aqi", "aqi_available"],
            "cyclical": ["week_sin", "week_cos"], "city_onehot_prefix": "city_",
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


# --- Configuration propagation through promotion (Sprint M6.1) --------------


def test_promotion_preserves_the_configured_low_confidence_threshold() -> None:
    """`persist.promote()` must not drop the candidate's artifact-carried
    threshold — it is inherited via `dict(candidate)` in
    `build_production_bundle`, not re-derived or reset. A synthetic candidate is
    used so this is a fast, isolated check of that one propagation step."""
    candidate = {
        "model_version": "rf-candidate-test",
        "low_confidence_threshold": 0.42,
        "diseases": ["dengue"],
        "best_params": {"dengue": {}},
    }
    evaluation = {
        "model_version": "rf-candidate-test",
        "per_disease": {
            "dengue": {
                "metrics": {"accuracy": 0.9, "f1_macro": 0.9,
                            "roc_auc_ovr_macro": 0.9, "brier_multiclass": 0.1},
                "label_seasonality": {"lift": 2.0},
            }
        },
    }
    cfg = {"release": {"version": "9.9.9", "model_version": "rf-9.9.9"}}

    bundle = persist.build_production_bundle(cfg, candidate, evaluation, repro={})
    assert bundle["low_confidence_threshold"] == 0.42


def test_real_promoted_artifact_carries_the_threshold_field() -> None:
    """The currently-shipped artifact was promoted before Sprint M6.1 introduced
    this field, so it legitimately may be absent — but if present it must be a
    real, in-range float, never a stale/invalid leftover."""
    bundle = load(_model_path())
    if "low_confidence_threshold" in bundle:
        assert 0.0 <= bundle["low_confidence_threshold"] <= 1.0


# --- Model Card is honest and complete --------------------------------------


def test_model_card_has_no_overclaim_and_links_methodology() -> None:
    card = (paths.REPORTS_DIR / "MODEL_CARD.md").read_text(encoding="utf-8")
    low = card.lower()
    # Honest framing present.
    assert "not an outbreak predictor" in low or "not outbreak prediction" in low
    assert "not a clinical" in low or "not clinical" in low
    assert "expected-by-construction" in low
    # Required sections / links.
    assert "label_methodology.md" in card
    assert "intended use" in low and "out of scope" in low
    assert "reproducibility record" in low


def test_model_card_does_not_promise_outbreak_forecasts() -> None:
    """Guard the headline failure mode: the card must not claim it predicts outbreaks."""
    low = (paths.REPORTS_DIR / "MODEL_CARD.md").read_text(encoding="utf-8").lower()
    for forbidden in ("predicts outbreaks", "outbreak prediction system",
                      "forecasts outbreaks", "predicts cases"):
        assert forbidden not in low
