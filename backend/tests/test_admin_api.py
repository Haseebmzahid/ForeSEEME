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


@pytest.mark.parametrize(("cutoff", "live_role", "factor", "error"), [
    pytest.param(None, True, "totp", None, id="active-totp-session"),
    pytest.param(NOW - 1, True, "phone", None, id="new-phone-session"),
    pytest.param(NOW, True, "totp", (401, "invalid_session"), id="at-cutoff"),
    pytest.param(NOW + 1, True, "totp", (401, "invalid_session"), id="before-cutoff"),
    pytest.param(None, False, "totp", (403, "admin_required"), id="live-role-removed"),
])
def test_admin_authorize_enforces_cutoff_and_live_role(
    cutoff, live_role, factor, error, monkeypatch,
):
    claims = {**ADMIN, "firebase": {"sign_in_second_factor": factor}}
    snapshot = SimpleNamespace(exists=cutoff is not None,
                               to_dict=lambda: {"throughAuthTime": cutoff})

    def document(uid):
        assert uid == claims["uid"]
        return SimpleNamespace(get=lambda *, timeout: snapshot)

    def collection(name):
        assert name == "sessionRevocations"
        return SimpleNamespace(document=document)

    db = SimpleNamespace(collection=collection)
    monkeypatch.setattr(admin_api, "db_client", lambda: db)
    monkeypatch.setattr(admin_api, "time", SimpleNamespace(time=lambda: NOW))

    def verify(token, *, check_revoked):
        assert token == "operator-token" and check_revoked is True
        return claims

    monkeypatch.setattr(admin_api.auth, "verify_id_token", verify)
    monkeypatch.setattr(admin_api.auth, "get_user",
                        lambda uid: SimpleNamespace(custom_claims={"admin": live_role}))
    rate_calls = []
    monkeypatch.setattr(admin_api, "rate_limit", lambda *args: rate_calls.append(args))
    request = SimpleNamespace(headers={"authorization": "Bearer operator-token"})

    if error is None:
        assert admin_api.authorize(request) == (db, claims)
        assert rate_calls == [(db, claims["uid"], NOW)]
    else:
        with pytest.raises(admin_api.HTTPException) as failure:
            admin_api.authorize(request)
        assert (failure.value.status_code, failure.value.detail["code"]) == error
        assert not rate_calls


def test_missing_bearer_and_cleartext():
    assert client.post("/v1/users/example").json()["detail"]["code"] == "token_required"
    assert TestClient(admin_api.app).post("/v1/users/example").json()["detail"]["code"] == "https_required"


def test_session_logout_derives_uid_from_verified_token(monkeypatch):
    calls = []
    db = object()
    monkeypatch.setattr(admin_api, "db_client", lambda: db)

    def verify(token, *, check_revoked):
        assert token == "ordinary-session" and check_revoked is True
        return {"uid": "caller", "auth_time": 90}

    monkeypatch.setattr(admin_api.auth, "verify_id_token", verify)
    monkeypatch.setattr(admin_api.auth, "revoke_refresh_tokens", lambda uid: calls.append(uid))
    monkeypatch.setattr(admin_api.auth, "get_user", lambda uid: SimpleNamespace(
        tokens_valid_after_timestamp=100_500,
    ))
    monkeypatch.setattr(admin_api, "record_revocation", lambda *args: calls.append(args))
    response = client.post("/v1/session/logout", json={"uid": "someone-else"},
                           headers={"Authorization": "Bearer ordinary-session"})
    assert response.status_code == 204
    assert response.content == b""
    assert calls == ["caller", (db, "caller", 100)]


def test_session_logout_fails_when_cutoff_is_unconfirmed(monkeypatch):
    monkeypatch.setattr(admin_api, "db_client", lambda: object())
    monkeypatch.setattr(admin_api.auth, "verify_id_token", lambda *a, **k: {
        "uid": "caller", "auth_time": 90,
    })
    monkeypatch.setattr(admin_api.auth, "revoke_refresh_tokens", lambda uid: None)
    monkeypatch.setattr(admin_api.auth, "get_user", lambda uid: SimpleNamespace(
        tokens_valid_after_timestamp=100_500,
    ))

    def unavailable(*_):
        raise RuntimeError("Firestore unavailable")

    monkeypatch.setattr(admin_api, "record_revocation", unavailable)
    response = client.post("/v1/session/logout", headers={"Authorization": "Bearer token"})
    assert response.status_code == 503
    assert response.json()["detail"] == {"code": "revocation_unconfirmed"}


def test_session_logout_rejects_missing_or_revoked_credentials(monkeypatch):
    monkeypatch.setattr(admin_api, "db_client", lambda: object())

    def revoked(*_, **__):
        raise admin_api.auth.RevokedIdTokenError("revoked")

    monkeypatch.setattr(admin_api.auth, "verify_id_token", revoked)
    assert client.post("/v1/session/logout").status_code == 401
    assert client.post("/v1/session/logout",
                       headers={"Authorization": "Bearer revoked"}).status_code == 401


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
