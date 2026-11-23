"""API validation must reject malformed input before invoking inference.

Synthetic city-level inputs only; no network or Firestore dependencies.
Stable FSM-B IDs identify parameterized cases in JUnit and the SDS.
"""
import pytest

from app.main import create_app
from app.models.risk_model import StubRiskModel


VALID = dict(city="Lahore", temperature=34.5, humidity=62.0,
             rainfall=12.0, aqi=180.0, weekOfYear=26)


class RecordingModel:
    model_version = "test-validation"

    def __init__(self):
        self.requests = []

    def predict(self, request):
        self.requests.append(request)
        return StubRiskModel(self.model_version).predict(request)


@pytest.fixture
def boundary_client(prediction_client):
    model = RecordingModel()
    with prediction_client(create_app(model=model)) as client:
        yield client, model


@pytest.mark.parametrize("field,value,error_type", [
    pytest.param("aqi", None, "float_type", id="FSM-B01-null-aqi"),
    pytest.param("temperature", "warm", "float_parsing", id="FSM-B02-text-temperature"),
    pytest.param("weekOfYear", 26.5, "int_from_float", id="FSM-B03-fractional-week"),
    pytest.param("city", [], "string_type", id="FSM-B04-array-city"),
])
def test_invalid_field_never_reaches_inference(boundary_client, field, value, error_type):
    client, model = boundary_client
    response = client.post("/predict", json={**VALID, field: value})
    assert response.status_code == 422
    assert any(error["loc"] == ["body", field] and error["type"] == error_type
               for error in response.json()["detail"])
    assert model.requests == []


@pytest.mark.parametrize("field", [
    pytest.param("city", id="FSM-B05-missing-city"),
    pytest.param("rainfall", id="FSM-B06-missing-rainfall"),
    pytest.param("weekOfYear", id="FSM-B07-missing-week"),
])
def test_required_field_missing_never_reaches_inference(boundary_client, field):
    client, model = boundary_client
    response = client.post("/predict", json={k: v for k, v in VALID.items() if k != field})
    assert response.status_code == 422
    assert any(e["loc"] == ["body", field] and e["type"] == "missing"
               for e in response.json()["detail"])
    assert model.requests == []


def test_FSM_B08_malformed_json_never_reaches_inference(boundary_client):
    client, model = boundary_client
    response = client.post("/predict", content='{"city":',
                           headers={"Content-Type": "application/json"})
    assert response.status_code == 422
    assert response.json()["detail"][0]["type"] == "json_invalid"
    assert model.requests == []


def test_unexpected_clinical_fields_are_rejected_without_echo(boundary_client):
    client, model = boundary_client
    response = client.post("/predict", json={**VALID, "clinical_test": "private-value"})
    assert response.status_code == 422
    assert response.json()["detail"][0]["type"] == "extra_forbidden"
    assert "clinical_test" not in response.text
    assert "private-value" not in response.text
    assert model.requests == []


@pytest.mark.parametrize("week", [
    pytest.param(1, id="FSM-B09-first-iso-week"),
    pytest.param(53, id="FSM-B10-last-iso-week"),
])
def test_inclusive_boundaries_reach_model_unchanged(boundary_client, week):
    client, model = boundary_client
    response = client.post("/predict", json={**VALID, "weekOfYear": week,
                                            "temperature": 80.0, "aqi": 0.0})
    assert response.status_code == 200
    assert len(model.requests) == 1
    request = model.requests[0]
    assert (request.week_of_year, request.temperature, request.aqi) == (week, 80.0, 0.0)
    body = response.json()
    assert body["modelVersion"] == model.model_version
    assert (body["temperature"], body["aqi"]) == (80.0, 0.0)
    assert body["riskLevel"] in {"Low", "Medium", "High"}
    assert 0 <= body["confidence"] <= 1
