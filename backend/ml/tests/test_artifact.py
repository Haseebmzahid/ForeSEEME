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
import pytest
from joblib import load

from ml.pipelines import paths
from ml.training import persist
from ml.training import train as T

ARTIFACTS = paths.ARTIFACTS_DIR
CLASSES = {"Low", "Medium", "High"}


def _model_path() -> Path:
    found = sorted(ARTIFACTS.glob("model_*.joblib"))
    assert found, "no model_<version>.joblib present — run `python -m ml.training.persist`"
    return found[-1]


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


# --- Loads & predicts contract-shaped output --------------------------------


def test_artifact_loads_and_predicts_contract_shape() -> None:
    bundle = load(_model_path())                 # bare load, no custom class
    assert set(bundle["models"]) == set(bundle["diseases"])
    test_df = pd.read_parquet(paths.TEST_PATH).head(4)
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
