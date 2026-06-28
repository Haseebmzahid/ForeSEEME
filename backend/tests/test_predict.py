"""API tests for the risk service, using the FastAPI TestClient.

Covers the contract acceptance cases:
- ``POST /predict`` with valid input -> 200 + a contract-valid body.
- ``POST /predict`` with ``aqi = -5`` -> 422 (Pydantic validation).
- ``GET /health`` -> 200.
"""

from fastapi.testclient import TestClient

from app.main import create_app

client = TestClient(create_app())


def _valid_payload() -> dict:
    return {
        "city": "Lahore",
        "temperature": 34.5,
        "humidity": 62.0,
        "rainfall": 12.0,
        "aqi": 180.0,
        "weekOfYear": 26,
    }


def test_health_returns_ok() -> None:
    response = client.get("/health")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert "modelVersion" in body


def test_predict_valid_returns_contract_body() -> None:
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


def test_predict_is_deterministic() -> None:
    first = client.post("/predict", json=_valid_payload()).json()
    second = client.post("/predict", json=_valid_payload()).json()
    # Classification is deterministic (generatedAt is the only varying field).
    assert first["riskLevel"] == second["riskLevel"]
    assert first["confidence"] == second["confidence"]
    assert first["disease"] == second["disease"]


def test_predict_negative_aqi_returns_422() -> None:
    payload = {**_valid_payload(), "aqi": -5}
    response = client.post("/predict", json=payload)
    assert response.status_code == 422


def test_predict_temperature_above_80_returns_422() -> None:
    payload = {**_valid_payload(), "temperature": 99.0}
    response = client.post("/predict", json=payload)
    assert response.status_code == 422
