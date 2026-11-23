"""API tests for the STUB risk model, using the FastAPI TestClient.

These pin the deterministic Sprint 1 stub behaviour (the graceful-degradation
fallback). The app is built with an explicit :class:`StubRiskModel` so these tests
stay independent of whether a real model artifact is present on disk; real-model
integration is covered in ``test_api.py``.

Covers the contract acceptance cases:
- ``POST /predict`` with valid input -> 200 + a contract-valid body.
- ``POST /predict`` with ``aqi = -5`` -> 422 (Pydantic validation).
- ``GET /health`` -> 200.
"""

import pytest

from app.main import create_app
from app.models.risk_model import StubRiskModel

@pytest.fixture(scope="module")
def client(prediction_client):
    return prediction_client(create_app(model=StubRiskModel("stub-0.0.0")))


def _valid_payload() -> dict:
    return {
        "city": "Lahore",
        "temperature": 34.5,
        "humidity": 62.0,
        "rainfall": 12.0,
        "aqi": 180.0,
        "weekOfYear": 26,
    }


def test_health_returns_ok(client) -> None:
    response = client.get("/health")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert "modelVersion" in body


def test_predict_valid_returns_contract_body(client) -> None:
    response = client.post("/predict", json=_valid_payload())
    assert response.status_code == 200

    body = response.json()
    # Contract field presence + camelCase aliases.
    assert body["city"] == "Lahore"
    assert body["riskLevel"] in ("Low", "Medium", "High")
    assert isinstance(body["disease"], str) and body["disease"]
    assert 0.0 <= body["confidence"] <= 1.0
    assert body["aqi"] == 180.0
    assert isinstance(body["generatedAt"], str)
    assert body["modelVersion"] == "stub-0.0.0"
    assert isinstance(body["lowConfidence"], bool)


def test_predict_is_deterministic(client) -> None:
    first = client.post("/predict", json=_valid_payload()).json()
    second = client.post("/predict", json=_valid_payload()).json()
    # Classification is deterministic (generatedAt is the only varying field).
    assert first["riskLevel"] == second["riskLevel"]
    assert first["confidence"] == second["confidence"]
    assert first["disease"] == second["disease"]


def test_predict_negative_aqi_returns_422(client) -> None:
    payload = {**_valid_payload(), "aqi": -5}
    response = client.post("/predict", json=payload)
    assert response.status_code == 422


def test_predict_temperature_above_80_returns_422(client) -> None:
    payload = {**_valid_payload(), "temperature": 99.0}
    response = client.post("/predict", json=payload)
    assert response.status_code == 422
