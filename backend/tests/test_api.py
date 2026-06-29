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
import pandas as pd
import pytest
from fastapi.testclient import TestClient
from joblib import load

from app.config import Settings
from app.main import create_app
from app.schemas import PredictRequest
from app import feature_builder, predict
from ml.pipelines import paths as mlpaths

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
    assert body["lowConfidence"] == (body["confidence"] < 0.55)


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


def test_serving_features_match_training_for_fixed_input() -> None:
    """Serving builds the SAME feature vector as training for a fixed city/week."""
    base = pd.read_parquet(mlpaths.INTERIM_DIR / "weekly_base.parquet")
    train = pd.read_parquet(mlpaths.TRAIN_PATH)
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
