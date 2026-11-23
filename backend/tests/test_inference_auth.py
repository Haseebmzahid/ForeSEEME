import json
import time
from types import SimpleNamespace

import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi.testclient import TestClient
from google.auth import crypt, jwt

from app import inference_auth
from app.config import Settings
from app.main import create_app
from app.models.risk_model import StubRiskModel

AUDIENCE = "https://inference.example.org"
SUBJECT = "1234567890"
VALID = dict(city="Lahore", temperature=34.5, humidity=62, rainfall=12, aqi=180, weekOfYear=26)


@pytest.fixture(scope="module")
def keys():
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    other = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    cert = key.public_key().public_bytes(
        serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo,
    ).decode()
    return cert, crypt.RSASigner(key, "test"), crypt.RSASigner(other, "test")


@pytest.fixture
def caller(monkeypatch, keys):
    cert, signer, wrong_signer = keys
    monkeypatch.setattr(inference_auth, "GoogleRequest", lambda: lambda *_, **__: SimpleNamespace(
        status=200, data=json.dumps({"test": cert}).encode(),
    ))
    now = int(time.time())

    def headers(*, invalid_signature=False, **changes):
        claims = dict(iss="https://accounts.google.com", sub=SUBJECT, aud=AUDIENCE,
                      iat=now - 60, exp=now + 120)
        encoded = jwt.encode(wrong_signer if invalid_signature else signer, claims | changes)
        return {"Authorization": f"Bearer {encoded.decode()}"}

    return headers


@pytest.fixture
def client():
    settings = Settings("stub-0.0.0", "WARNING", inference_audience=AUDIENCE,
                        inference_service_account_subject=SUBJECT)
    model = StubRiskModel("stub-0.0.0")
    return TestClient(create_app(settings, model), base_url="https://testserver")


@pytest.mark.parametrize("headers", [{}, {"Authorization": "Bearer malformed"}])
def test_credentials_required(client, headers):
    assert client.post("/predict", json=VALID, headers=headers).status_code == 401


@pytest.mark.parametrize(("changes", "expected"), [
    ({"exp": 1}, 401),
    ({"invalid_signature": True}, 401),
    ({"aud": "https://different.example.org"}, 401),
    ({"iss": "https://untrusted.example.org"}, 401),
    ({"iss": "https://securetoken.google.com/demo-foreseeme",
      "sub": "firebase-user", "aud": "demo-foreseeme"}, 401),
    ({"sub": "9876543210"}, 403),
    ({}, 200),
])
def test_inference_identity(client, caller, changes, expected):
    response = client.post("/predict", json=VALID, headers=caller(**changes))
    assert response.status_code == expected
    if expected == 200:
        assert response.json()["city"] == "Lahore"
    else:
        assert response.json() == {
            "detail": "Invalid service credential" if expected == 401
            else "Inference caller not authorized",
        }


def test_authorized_inference_rejects_clinical_fields_without_echo(client, caller):
    response = client.post("/predict", json={**VALID, "clinical_test": "private-value"},
                           headers=caller())
    assert response.status_code == 422
    assert response.json()["detail"][0]["type"] == "extra_forbidden"
    assert all(value not in response.text for value in ("clinical_test", "private-value"))


def test_cleartext_is_denied_even_with_valid_token(client, caller):
    response = client.post("http://testserver/predict", json=VALID, headers={
        **caller(), "X-Forwarded-Proto": "https",
    })
    assert response.status_code == 400


def test_missing_configuration_fails_closed(caller):
    configured = create_app(Settings("stub-0.0.0", "WARNING"), StubRiskModel("stub-0.0.0"))
    client = TestClient(configured, base_url="https://testserver")
    assert client.post("/predict", json=VALID, headers=caller()).status_code == 503
