from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from app import admin_api
from app.jobs.account_metrics import account_metrics, account_projection

client = TestClient(admin_api.app, base_url="https://testserver")
NOW = 1_800_000_000
ADMIN = {"uid": "operator", "admin": True, "auth_time": NOW,
         "firebase": {"sign_in_second_factor": "totp"}}


@pytest.mark.parametrize(("changes", "status", "code"), [
    ({"admin": False}, 403, "admin_required"),
    ({"firebase": {}}, 403, "mfa_required"),
    ({"auth_time": NOW - 301}, 403, "recent_sign_in_required"),
    ({"auth_time": NOW + 31}, 403, "recent_sign_in_required"),
])
def test_claims(changes, status, code, monkeypatch):
    monkeypatch.setattr(admin_api.auth, "verify_id_token", lambda *a, **k: {**ADMIN, **changes})
    with pytest.raises(admin_api.HTTPException) as failure:
        admin_api.verify_admin("test-token", now=NOW)
    assert failure.value.status_code == status
    assert failure.value.detail == {"code": code}


@pytest.mark.parametrize("error", [admin_api.auth.InvalidIdTokenError, admin_api.auth.RevokedIdTokenError])
def test_invalid_or_revoked(error, monkeypatch):
    def verify(_token, *, check_revoked):
        assert check_revoked
        raise error("invalid")
    monkeypatch.setattr(admin_api.auth, "verify_id_token", verify)
    with pytest.raises(admin_api.HTTPException) as failure:
        admin_api.verify_admin("test-token", now=NOW)
    assert failure.value.status_code == 401


def test_verified_admin(monkeypatch):
    def verify(token, *, check_revoked):
        assert token == "test-token" and check_revoked
        return ADMIN
    monkeypatch.setattr(admin_api.auth, "verify_id_token", verify)
    assert admin_api.verify_admin("test-token", now=NOW) == ADMIN


def test_missing_bearer_and_cleartext():
    assert client.post("/v1/users/example").json()["detail"]["code"] == "token_required"
    assert TestClient(admin_api.app).post("/v1/users/example").json()["detail"]["code"] == "https_required"


def test_validation_hides_raw_input(monkeypatch):
    monkeypatch.setitem(admin_api.app.dependency_overrides, admin_api.authorize, lambda: (None, ADMIN))
    response = client.post("/v1/users/example", json={"action": "delete", "actorUid": "spoofed"})
    assert response.status_code == 422
    assert response.json() == {"detail": {"code": "invalid_input"}}


@pytest.mark.parametrize("url", ["http://example.org", "https://me@example.org", "https://"])
def test_article_rejects_invalid_source(url):
    with pytest.raises(ValueError):
        admin_api.Article(title="Title", summary="Summary", sourceName="Source", sourceUrl=url,
                          topic="heat", categories=["heat"],
                          content=[{"kind": "paragraph", "text": "Body"}], create=True)


def test_activity_deduplicates_and_excludes_disabled_or_stale():
    now = datetime(2026, 11, 22, tzinfo=timezone.utc)
    def account(uid, *, age, disabled=False, refresh=False):
        activity = int((now - timedelta(days=age)).timestamp() * 1000)
        return SimpleNamespace(
            uid=uid, disabled=disabled, email="test@example.org", display_name="Sample",
            user_metadata=SimpleNamespace(creation_timestamp=activity,
                                          last_refresh_timestamp=activity if refresh else None,
                                          last_sign_in_timestamp=None if refresh else activity),
        )
    active = account("1", age=30, refresh=True)
    output = account_metrics([active, active, account("2", age=1, disabled=True),
                              account("3", age=31), account("4", age=-1)], now, 30)
    assert output == {
        "totalUsers": 4, "activeUsers": 1, "measurementWindowDays": 30,
        "generatedAt": now, "source": "firebase_auth_sign_in_or_token_refresh",
        "aggregationStatus": "ok",
    }
    assert set(account_projection(active)) == {"email", "name", "createdAt", "authDisabled"}



@pytest.mark.parametrize('invalid', ['invalid', 'someone..else@example.org', 'name@-.org'])
def test_invitation_address_is_validated(invalid):
    with pytest.raises(ValueError):
        admin_api.Invitation(email=invalid)
