"""Integration tests for the real-model API (Sprint 2, Prompt 14).

Covers the prompt's acceptance criteria:
- the default app loads the promoted artifact and ``/predict`` returns real,
  contract-valid predictions; ``/health`` reports ``modelLoaded: true``;
- out-of-range input is still rejected with 422 (frozen contract unchanged);
- a missing or corrupt artifact degrades gracefully to the Sprint 1 stub
  (``modelLoaded: false``), still serving contract-valid output;
- the serving feature vector equals the training feature vector for a fixed
  input (train/serve parity — guards against divergent feature logic).
"""

from __future__ import annotations

import numpy as np
import pytest
from fastapi.testclient import TestClient
from joblib import load

from app.config import Settings
from app.main import create_app
from app.schemas import PredictRequest
from app import feature_builder, predict

VALID = {
    "city": "Lahore", "temperature": 34.5, "humidity": 62.0,
    "rainfall": 12.0, "aqi": 180.0, "weekOfYear": 26,
}
RISK_LEVELS = {"Low", "Medium", "High"}
DISEASES = {"Dengue", "Smog", "Influenza"}


@pytest.fixture(scope="module")
def real_client() -> TestClient:
    """Default app — loads the promoted model_<version>.joblib from artifacts/."""
    return TestClient(create_app())


# --- Real model serves the unchanged contract -------------------------------


def test_health_reports_model_loaded(real_client: TestClient) -> None:
    body = real_client.get("/health").json()
    assert body["status"] == "ok"
    assert body["modelLoaded"] is True
    assert body["modelVersion"] == "rf-1.0.0"


def test_predict_returns_real_contract_body(real_client: TestClient) -> None:
    response = real_client.post("/predict", json=VALID)
    assert response.status_code == 200
    body = response.json()
    assert body["city"] == "Lahore"
    assert body["riskLevel"] in RISK_LEVELS
    assert body["disease"] in DISEASES
    assert 0.0 <= body["confidence"] <= 1.0
    assert body["aqi"] == 180.0
    assert body["temperature"] == 34.5
    assert body["modelVersion"] == "rf-1.0.0"
    assert isinstance(body["lowConfidence"], bool)
    # lowConfidence is derived from the ARTIFACT's own threshold (Sprint M6.1),
    # not a hardcoded literal — see the "Artifact-driven configuration" section
    # below for the regression tests that prove this.
    bundle = load(predict.resolve_artifact_path())
    threshold = predict.resolve_low_confidence_threshold(bundle)
    assert body["lowConfidence"] == (body["confidence"] < threshold)


def test_predict_classification_is_deterministic(real_client: TestClient) -> None:
    a = real_client.post("/predict", json=VALID).json()
    b = real_client.post("/predict", json=VALID).json()
    assert (a["riskLevel"], a["disease"], a["confidence"]) == \
           (b["riskLevel"], b["disease"], b["confidence"])


def test_out_of_range_inputs_still_422(real_client: TestClient) -> None:
    assert real_client.post("/predict", json={**VALID, "aqi": -5}).status_code == 422
    assert real_client.post("/predict", json={**VALID, "temperature": 99.0}).status_code == 422
    assert real_client.post("/predict", json={**VALID, "weekOfYear": 60}).status_code == 422


# --- Graceful degradation (Sprint 1 behaviour preserved) --------------------


def _settings(path: str | None) -> Settings:
    return Settings(model_version="stub-0.0.0", log_level="WARNING",
                    model_artifact_path=path)


def test_missing_artifact_falls_back_to_stub(tmp_path) -> None:
    settings = _settings(str(tmp_path / "does_not_exist.joblib"))
    model, loaded, version = predict.load_risk_model(settings)
    assert loaded is False and version == "stub-0.0.0"

    client = TestClient(create_app(settings=settings))
    health = client.get("/health").json()
    assert health["modelLoaded"] is False
    assert health["modelVersion"] == "stub-0.0.0"
    # Still serves a contract-valid prediction (service stays up).
    body = client.post("/predict", json=VALID).json()
    assert body["riskLevel"] in RISK_LEVELS
    assert body["modelVersion"] == "stub-0.0.0"


def test_corrupt_artifact_falls_back_to_stub(tmp_path) -> None:
    bad = tmp_path / "model_9.9.9.joblib"
    bad.write_bytes(b"this is not a joblib artifact")
    model, loaded, version = predict.load_risk_model(_settings(str(bad)))
    assert loaded is False and version == "stub-0.0.0"


# --- Train/serve feature parity (the key correctness guard) -----------------


def test_serving_features_match_training_for_fixed_input(frozen_weekly_base, frozen_ml_split) -> None:
    """Serving builds the SAME feature vector as training for a fixed city/week."""
    base = frozen_weekly_base
    train = frozen_ml_split("train")
    feature_names = load(predict.resolve_artifact_path())["feature_names"]

    engineered = feature_builder.engineer_serving_features(base, feature_names)
    fixed = train.iloc[len(train) // 2]
    key = (fixed["city"], fixed["iso_year"], fixed["week_of_year"])

    em = (engineered["city"] == key[0]) & (engineered["iso_year"] == key[1]) \
        & (engineered["week_of_year"] == key[2])
    serving_vec = engineered.loc[em, feature_names].astype(float).to_numpy()[0]

    tm = (train["city"] == key[0]) & (train["iso_year"] == key[1]) \
        & (train["week_of_year"] == key[2])
    training_vec = train.loc[tm, feature_names].astype(float).to_numpy()[0]

    assert serving_vec.shape == training_vec.shape
    assert np.allclose(serving_vec, training_vec, equal_nan=True), \
        "serving feature vector diverged from the training feature vector"


def test_request_feature_frame_shape_and_order() -> None:
    feature_names = load(predict.resolve_artifact_path())["feature_names"]
    req = PredictRequest(city="Lahore", temperature=34.5, humidity=62.0,
                         rainfall=12.0, aqi=180.0, week_of_year=26)
    X = feature_builder.build_request_features(req, feature_names)
    assert list(X.columns) == feature_names          # exact model column order
    assert len(X) == 1
    # Raw same-week features are present; city one-hot is set for the request city.
    assert not np.isnan(X["temperature"].iloc[0])
    assert X["city_Lahore"].iloc[0] == 1.0


# --- Semver-aware artifact resolution (Sprint M6.2) --------------------------
#
# The audit's deployment risk: `resolve_artifact_path()` used to pick "latest"
# by sorting filenames as plain strings, so `model_10.0.0.joblib` would lose to
# `model_2.0.0.joblib`. These prove the fix end-to-end through the real
# `app.predict` entry point (the unit-level primitives are covered in
# `backend/ml/tests/test_paths.py`).


def test_resolve_artifact_path_picks_highest_semver_not_lexicographic_last(
    tmp_path, monkeypatch,
) -> None:
    """The exact scenario the audit flagged: a two-digit major version must be
    selected even though it sorts first as a plain string."""
    for name in ("model_1.0.0.joblib", "model_2.0.0.joblib", "model_10.0.0.joblib"):
        (tmp_path / name).write_bytes(b"")
    monkeypatch.setattr(predict, "ARTIFACTS_DIR", tmp_path)

    assert predict.resolve_artifact_path() == tmp_path / "model_10.0.0.joblib"


def test_resolve_artifact_path_explicit_override_still_takes_precedence(
    tmp_path,
) -> None:
    """Backward compatibility: an explicit override (a pinned deployment, or a
    test pointing at a missing/corrupt artifact — see `test_missing_artifact_
    falls_back_to_stub` / `test_corrupt_artifact_falls_back_to_stub` above) is
    unaffected by semver-aware discovery — it is never consulted when given."""
    pinned = tmp_path / "model_1.0.0.joblib"
    pinned.write_bytes(b"")
    assert predict.resolve_artifact_path(str(pinned)) == pinned


def test_resolve_artifact_path_returns_none_when_directory_has_no_artifact(
    tmp_path, monkeypatch,
) -> None:
    monkeypatch.setattr(predict, "ARTIFACTS_DIR", tmp_path)
    assert predict.resolve_artifact_path() is None


def test_resolve_artifact_path_ignores_the_unversioned_candidate_artifact(
    tmp_path, monkeypatch,
) -> None:
    """`candidate_model.joblib` (the pre-promotion training output — Prompt 11)
    must never be mistaken for a production artifact; only the promoted
    `model_<semver>.joblib` (Prompt 13) is eligible."""
    (tmp_path / "candidate_model.joblib").write_bytes(b"")
    released = tmp_path / "model_1.0.0.joblib"
    released.write_bytes(b"")
    monkeypatch.setattr(predict, "ARTIFACTS_DIR", tmp_path)

    assert predict.resolve_artifact_path() == released


def test_resolve_artifact_path_matches_the_shared_paths_helper() -> None:
    """Against the real artifacts directory: `app.predict`'s resolution must
    agree exactly with `ml.pipelines.paths.latest_model_artifact` — the single
    authoritative selection (Sprint M6.2 goal), not two implementations that
    only happen to agree today because one artifact exists."""
    from ml.pipelines import paths as mlpaths
    assert predict.resolve_artifact_path() == mlpaths.latest_model_artifact()


def test_real_client_still_loads_and_predicts_after_the_resolution_change(
    real_client: TestClient,
) -> None:
    """Prediction behaviour is unchanged end-to-end: the real, currently-shipped
    artifact still loads (`modelLoaded: true`) and serves the same contract."""
    health = real_client.get("/health").json()
    assert health["modelLoaded"] is True
    response = real_client.post("/predict", json=VALID)
    assert response.status_code == 200
    assert response.json()["riskLevel"] in RISK_LEVELS


# --- Artifact-driven low-confidence configuration (Sprint M6.1) -------------
#
# The `lowConfidence` threshold must come from ONE place: the trained bundle's
# `low_confidence_threshold` field (itself sourced from `config/model.yaml`),
# never a constant duplicated across predict.py / explain.py / the batch job.
# These tests prove that end-to-end, using the real promoted artifact.


def test_resolve_low_confidence_threshold_reads_the_configured_artifact_value() -> None:
    """An artifact carrying its own threshold is authoritative — no fallback used."""
    bundle = dict(load(predict.resolve_artifact_path()))
    bundle["low_confidence_threshold"] = 0.2
    assert predict.resolve_low_confidence_threshold(bundle) == 0.2


def test_resolve_low_confidence_threshold_falls_back_for_legacy_artifact() -> None:
    """An artifact predating Sprint M6.1 (no stored field) uses the documented
    default, reproducing pre-M6.1 behaviour rather than raising or drifting.
    ``pop(..., None)`` tolerates the field being absent either way: the
    currently-shipped artifact predates M6.1 and never had it in the first
    place, which *is* the legacy case this test exercises."""
    bundle = dict(load(predict.resolve_artifact_path()))
    bundle.pop("low_confidence_threshold", None)
    assert (predict.resolve_low_confidence_threshold(bundle)
            == predict.DEFAULT_LOW_CONFIDENCE_THRESHOLD)


def test_changing_the_artifact_threshold_changes_serving_behaviour() -> None:
    """Simulates "after retraining with a different config/model.yaml value":
    the ONLY thing that differs between the two bundles below is
    `low_confidence_threshold` (exactly what a retrain with a different
    `evaluation.low_confidence_threshold` would change) — same Pipelines, same
    request. Runtime `lowConfidence` must track the artifact, not a constant.
    """
    base_bundle = load(predict.resolve_artifact_path())
    req = PredictRequest(city="Lahore", temperature=34.5, humidity=62.0,
                         rainfall=12.0, aqi=180.0, week_of_year=26)

    permissive = dict(base_bundle)
    permissive["low_confidence_threshold"] = 0.0   # nothing is ever "low confidence"
    strict = dict(base_bundle)
    strict["low_confidence_threshold"] = 1.0        # everything short of certainty is

    result_permissive = predict.RealRiskModel(permissive).predict(req)
    result_strict = predict.RealRiskModel(strict).predict(req)

    assert result_permissive.low_confidence is False
    assert result_strict.low_confidence is True
    # Classification itself (unrelated to the threshold) is unaffected.
    assert result_permissive.risk_level == result_strict.risk_level
    assert result_permissive.confidence == result_strict.confidence


def test_unchanged_artifact_config_leaves_prediction_behaviour_unchanged() -> None:
    """A bundle round-tripped with no config change predicts identically to the
    original — confirming this refactor is behaviour-preserving by default."""
    bundle = load(predict.resolve_artifact_path())
    req = PredictRequest(city="Lahore", temperature=34.5, humidity=62.0,
                         rainfall=12.0, aqi=180.0, week_of_year=26)

    a = predict.RealRiskModel(bundle).predict(req)
    b = predict.RealRiskModel(dict(bundle)).predict(req)  # fresh copy, same config
    assert (a.risk_level, a.disease, a.confidence, a.low_confidence) == \
           (b.risk_level, b.disease, b.confidence, b.low_confidence)
