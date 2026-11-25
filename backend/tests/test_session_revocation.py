from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from app import admin_api, session_revocation
from app.notification_registrations import InactiveSession, RegistrationStore
from scripts import set_admin_claim
from test_notification_registrations import MemoryFirestore


@pytest.fixture
def logout(monkeypatch):
    db = MemoryFirestore()
    clock = SimpleNamespace(now=100.0)
    firebase = SimpleNamespace(valid_after=0, calls=0, fail_read=False, fail_revoke=False,
                               lose_provider_reply=False, fail_commit=None)
    clients = {
        "old": {"uid": "alice", "auth_time": 80, "iat": 80, "email_verified": True},
        "second": {"uid": "alice", "auth_time": 90, "iat": 90, "email_verified": True},
        "fresh": {"uid": "alice", "auth_time": 102, "iat": 102, "email_verified": True},
        "other": {"uid": "bob", "auth_time": 90, "iat": 90, "email_verified": True},
    }
    checks = []

    def transactional(fn):
        def apply(transaction, *args):
            result = fn(transaction, *args)
            if firebase.fail_commit and firebase.fail_commit(fn.__name__, args):
                raise RuntimeError("simulated write failure")
            for ref, data, merge in transaction.pending:
                record = db.documents.get(ref.path, {}).copy() if merge else {}
                for key, value in data.items():
                    if value is session_revocation.firestore.DELETE_FIELD:
                        record.pop(key, None)
                    else:
                        record[key] = value
                db.documents[ref.path] = record
            return result
        return apply

    def transaction(**_):
        pending = []
        return SimpleNamespace(
            pending=pending, set=lambda ref, data, merge=False: pending.append((ref, data, merge)),
        )

    def verify(token, *, check_revoked):
        checks.append((token, check_revoked))
        if token == "expired":
            raise admin_api.auth.ExpiredIdTokenError("expired", None)
        if token not in clients:
            raise admin_api.auth.InvalidIdTokenError("invalid")
        claims = clients[token]
        if check_revoked and claims["iat"] < firebase.valid_after:
            raise admin_api.auth.RevokedIdTokenError("revoked")
        return claims

    def read_user(uid):
        assert uid == "alice"
        if firebase.fail_read:
            raise RuntimeError("Firebase lookup failed")
        return SimpleNamespace(tokens_valid_after_timestamp=firebase.valid_after * 1000)

    def revoke(uid):
        assert uid == "alice"
        assert db.documents["sessionRevocations", "alice"]["throughAuthTime"] >= 100
        firebase.calls += 1
        if firebase.fail_revoke:
            raise RuntimeError("Firebase unavailable")
        firebase.valid_after = int(clock.now)
        if firebase.lose_provider_reply:
            raise RuntimeError("Firebase reply lost")

    monkeypatch.setattr(db, "transaction", transaction)
    monkeypatch.setattr(session_revocation.firestore, "transactional", transactional)
    monkeypatch.setattr(session_revocation, "time", SimpleNamespace(
        time=lambda: clock.now, sleep=lambda delay: setattr(clock, "now", clock.now + delay),
    ))
    monkeypatch.setattr(admin_api, "db_client", lambda: db)
    monkeypatch.setattr(admin_api.auth, "verify_id_token", verify)
    monkeypatch.setattr(admin_api.auth, "get_user", read_user)
    monkeypatch.setattr(admin_api.auth, "revoke_refresh_tokens", revoke)
    client = TestClient(admin_api.app, base_url="https://testserver")

    def post(token="old"):
        headers = {"Authorization": f"Bearer {token}"} if token else {}
        return client.post("/v1/session/logout", headers=headers, json={"uid": "forged"})

    return SimpleNamespace(db=db, clock=clock, firebase=firebase, post=post,
                           client=client, clients=clients, checks=checks, revoke=revoke)


def retry_after_lease(logout):
    logout.clock.now += session_revocation.LEASE_SECONDS + 1
    return logout.post()


def test_cutoff_failure_has_no_firebase_side_effect(logout):
    logout.firebase.fail_commit = lambda name, _: name == "prepare"
    assert logout.post().status_code == 503
    assert logout.firebase.calls == 0
    assert not logout.db.documents
    logout.firebase.fail_commit = None
    assert logout.post().status_code == 204


def test_lost_http_reply_replays_only_the_confirmed_receipt(logout):
    assert logout.post().status_code == 204
    assert logout.firebase.valid_after == 101
    assert logout.db.documents["sessionRevocations", "alice"]["throughAuthTime"] == 100
    logout.clock.now = 160
    assert logout.post().status_code == 204
    assert logout.firebase.calls == 1
    assert ("old", False) in logout.checks
    assert logout.post("second").status_code == 401
    successful = logout.client.post(
        "/v1/notifications/register", headers={"Authorization": "Bearer fresh"},
        json={"token": "fresh-registered-device"},
    )
    assert successful.status_code == 204


@pytest.mark.parametrize("fault", ["provider_reply", "completion_commit"])
def test_reconciles_provider_success_without_revoking_again(logout, fault):
    if fault == "provider_reply":
        logout.firebase.lose_provider_reply = True
    else:
        logout.firebase.fail_commit = lambda name, args: name == "update_lease" and bool(args)
    assert logout.post().status_code == 503
    assert logout.firebase.valid_after == 101
    assert logout.post().status_code == 503
    logout.firebase.fail_commit = None
    logout.firebase.lose_provider_reply = False
    assert retry_after_lease(logout).status_code == 204
    assert logout.firebase.calls == 1
    assert logout.db.documents["sessionRevocations", "alice"]["throughAuthTime"] == 100


@pytest.mark.parametrize("fault", ["fail_read", "fail_revoke"])
def test_provider_failure_leaves_cutoff_and_resumes(logout, fault):
    setattr(logout.firebase, fault, True)
    assert logout.post().status_code == 503
    assert logout.db.documents["sessionRevocations", "alice"]["throughAuthTime"] == 100
    with pytest.raises(InactiveSession):
        RegistrationStore(logout.db).register("alice", 80, "old-device")
    setattr(logout.firebase, fault, False)
    assert retry_after_lease(logout).status_code == 204
    assert logout.db.documents["sessionRevocations", "alice"]["throughAuthTime"] >= 100


def test_concurrent_logout_does_not_issue_two_provider_mutations(logout, monkeypatch):
    def during_revoke(uid):
        assert logout.post().status_code == 503
        assert logout.post("second").status_code == 401
        logout.revoke(uid)

    monkeypatch.setattr(admin_api.auth, "revoke_refresh_tokens", during_revoke)
    assert logout.post().status_code == 204
    assert logout.post().status_code == 204
    assert logout.firebase.calls == 1


def test_stale_or_invalid_bearer_cannot_start_logout_or_register(logout):
    assert logout.post(None).status_code == 401
    assert logout.post("invalid").status_code == 401
    assert logout.post("expired").status_code == 401
    assert ("invalid", False) not in logout.checks
    assert ("expired", False) not in logout.checks
    assert logout.post().status_code == 204
    response = logout.client.post(
        "/v1/notifications/register", headers={"Authorization": "Bearer old"},
        json={"token": "old-device"},
    )
    assert response.status_code == 401


def test_external_cutoff_write_preserves_confirmation_and_never_lowers_cutoff(logout):
    assert logout.post().status_code == 204
    session_revocation.record_revocation(logout.db, "alice", 120)
    assert logout.post().status_code == 204
    assert logout.firebase.calls == 1
    assert logout.db.documents["sessionRevocations", "alice"]["throughAuthTime"] == 120


def test_firebase_accepting_a_refreshed_old_session_is_insufficient(logout, monkeypatch):
    assert logout.post().status_code == 204
    logout.clients["old"].update(
        iat=102, admin=True, firebase={"sign_in_second_factor": "totp"},
    )
    monkeypatch.setattr(admin_api, "time", SimpleNamespace(time=lambda: 102))
    headers = {"Authorization": "Bearer old"}
    assert logout.client.post("/v1/overrides/example/clear", headers=headers).status_code == 401
    assert logout.client.post(
        "/v1/notifications/register", headers=headers, json={"token": "old-device"},
    ).status_code == 401


def test_operator_role_removal_writes_cutoff_before_mutating_auth(logout, monkeypatch):
    monkeypatch.delenv("FIREBASE_AUTH_EMULATOR_HOST", raising=False)
    monkeypatch.delenv("FIRESTORE_EMULATOR_HOST", raising=False)
    monkeypatch.setattr(set_admin_claim, "_init_app", lambda: None)
    monkeypatch.setattr(set_admin_claim, "_resolve_uid", lambda _: "alice")
    monkeypatch.setattr(set_admin_claim, "time", SimpleNamespace(time=lambda: 100))
    monkeypatch.setattr(set_admin_claim.firestore, "client", lambda: logout.db)
    monkeypatch.setattr(admin_api.auth, "get_user", lambda _: SimpleNamespace(
        custom_claims={"admin": True, "another": True}, tokens_valid_after_timestamp=100_000,
    ))
    claim_updates = []

    def remove(uid, claims):
        assert logout.db.documents["sessionRevocations", uid]["throughAuthTime"] == 100
        claim_updates.append(claims)

    monkeypatch.setattr(admin_api.auth, "set_custom_user_claims", remove)
    logout.firebase.fail_commit = lambda name, _: name == "record"
    with pytest.raises(RuntimeError, match="simulated write failure"):
        set_admin_claim.set_admin("alice", grant=False)
    assert not claim_updates and logout.firebase.calls == 0
    logout.firebase.fail_commit = None
    set_admin_claim.set_admin("alice", grant=False)
    assert claim_updates == [{"another": True}]
    assert logout.firebase.calls == 1
