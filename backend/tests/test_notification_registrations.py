from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from app import admin_api
from app.jobs.dispatch_alerts import FirestoreUserDirectory
from app.notification_registrations import (
    COLLECTION,
    RegistrationConflict,
    RegistrationStore,
    registration_id,
)


class Ref:
    def __init__(self, db, path):
        self.db = db
        self.path = path

    def document(self, name):
        return Ref(self.db, (*self.path, name))

    def collection(self, name):
        return self.document(name)

    def get(self, **_):
        data = self.db.documents.get(self.path)
        return SimpleNamespace(
            id=self.path[-1], exists=data is not None,
            to_dict=lambda: data.copy() if data is not None else None,
        )

    def stream(self, **_):
        length = len(self.path) + 1
        return [
            Ref(self.db, path).get() for path in self.db.documents
            if len(path) == length and path[:-1] == self.path
        ]

    def where(self, *, filter):
        return SimpleNamespace(stream=lambda **_: [
            snap for snap in self.stream()
            if snap.to_dict().get(filter.field_path) == filter.value
        ])


class MemoryFirestore:
    def __init__(self):
        self.documents = {}

    def collection(self, name):
        return Ref(self, (name,))

    def transaction(self, **_):
        return SimpleNamespace(set=lambda ref, data: self.documents.__setitem__(ref.path, data))


@pytest.fixture
def db(monkeypatch):
    db = MemoryFirestore()
    monkeypatch.setattr("app.notification_registrations.firestore.transactional", lambda op: op)
    monkeypatch.setattr(admin_api, "db_client", lambda: db)
    return db


@pytest.fixture
def request_registration(db, monkeypatch):
    claims = {"uid": "alice", "auth_time": 10, "email_verified": True}

    def verify(token, *, check_revoked):
        assert token == "test-session" and check_revoked
        return claims

    monkeypatch.setattr(admin_api.auth, "verify_id_token", verify)
    client = TestClient(admin_api.app, base_url="https://testserver")

    def post(action, body, authenticated=True):
        headers = {"Authorization": "Bearer test-session"} if authenticated else {}
        return client.post(f"/v1/notifications/{action}", headers=headers, json=body)

    return post, claims


def test_api_uses_verified_identity_and_rejects_untrusted_input(request_registration, db):
    post, _ = request_registration
    assert post("register", {"token": "example-one"}, authenticated=False).status_code == 401
    for invalid in ("", "has spaces", "has/newline\n", 4, "x" * 4097):
        response = post("register", {"token": invalid})
        assert response.status_code == 422
        assert response.json() == {"detail": {"code": "invalid_input"}}
    assert post("register", {"token": "example-one", "uid": "injected"}).status_code == 422
    assert post("register", {"token": "example-one"}).status_code == 204
    assert next(iter(RegistrationStore(db).for_user("alice"))).auth_time == 10


def test_api_rejects_revoked_token_and_cutoff(request_registration, db, monkeypatch):
    post, _ = request_registration
    db.documents[("sessionRevocations", "alice")] = {"throughAuthTime": 10}
    assert post("register", {"token": "example-one"}).status_code == 401

    def revoked(*_, **__):
        raise admin_api.auth.RevokedIdTokenError("revoked")

    monkeypatch.setattr(admin_api.auth, "verify_id_token", revoked)
    assert post("unregister", {"token": "example-one"}).status_code == 401


def test_registration_requires_email_verification_but_cleanup_remains_available(
    request_registration, db,
):
    post, claims = request_registration
    payload = {"token": "example-one"}
    assert post("register", payload).status_code == 204
    claims["email_verified"] = False
    rejected = post("register", {"token": "example-two"})
    assert rejected.status_code == 403
    assert rejected.json()["detail"]["code"] == "email_verification_required"
    assert post("unregister", payload).status_code == 204
    assert not RegistrationStore(db).for_user("alice")


def test_idempotent_registration_supports_multiple_devices(db):
    store = RegistrationStore(db)
    store.register("alice", 10, "example-one")
    first = store.for_user("alice")
    store.register("alice", 10, "example-one")
    assert store.for_user("alice") == first
    store.register("alice", 10, "example-two")
    assert len(store.for_user("alice")) == 2
    assert (COLLECTION, registration_id("example-one")) in db.documents


def test_newer_owner_wins_old_and_equal_conflicts_fail_closed(request_registration, db):
    post, claims = request_registration
    payload = {"token": "example-one"}
    assert post("register", payload).status_code == 204
    claims.update(uid="bob")
    assert post("register", payload).status_code == 409
    claims.update(auth_time=11)
    assert post("register", payload).status_code == 204
    claims.update(uid="alice", auth_time=10)
    assert post("register", payload).status_code == 409
    assert post("unregister", payload).status_code == 204
    assert not RegistrationStore(db).for_user("alice")
    assert len(RegistrationStore(db).for_user("bob")) == 1


def test_unregister_is_idempotent_and_leaves_ordering_after_removal(db):
    store = RegistrationStore(db)
    store.register("alice", 10, "example-one")
    store.unregister("alice", 10, "example-one")
    store.unregister("alice", 10, "example-one")
    assert not store.for_user("alice")
    with pytest.raises(RegistrationConflict):
        store.register("alice", 10, "example-one")
    with pytest.raises(RegistrationConflict):
        store.register("bob", 9, "example-one")
    store.register("bob", 11, "example-one")
    assert len(store.for_user("bob")) == 1


def test_unregistration_before_delayed_register_blocks_it(db):
    store = RegistrationStore(db)
    store.unregister("alice", 10, "example-one")
    with pytest.raises(RegistrationConflict):
        store.register("alice", 10, "example-one")


def test_rotation_only_retires_the_previous_token_for_that_session(db):
    store = RegistrationStore(db)
    store.register("alice", 10, "example-one")
    store.register("alice", 10, "other-device")
    store.register("alice", 10, "example-two", "example-one")
    assert len(store.for_user("alice")) == 2
    with pytest.raises(RegistrationConflict):
        store.register("alice", 10, "example-one")
    store.register("bob", 11, "example-one")
    store.register("alice", 10, "example-two", "example-one")
    assert len(store.for_user("bob")) == 1


def test_prune_only_removes_the_exact_attempted_registration(db):
    store = RegistrationStore(db)
    store.register("alice", 10, "example-one")
    old, = store.for_user("alice")
    store.register("alice", 11, "example-one")
    refreshed, = store.for_user("alice")
    assert not store.prune(old)
    store.register("bob", 12, "example-one")
    assert not store.prune(refreshed)
    assert not store.is_current(old)
    current, = store.for_user("bob")
    assert store.is_current(current)
    assert store.prune(current)
    assert not store.is_current(current)
    assert "token" not in db.documents[(COLLECTION, registration_id("example-one"))]


def test_directory_has_no_legacy_fallback_and_filters_revoked_sessions(db):
    db.documents[("users", "alice")] = {"fcmToken": "legacy"}
    db.documents[("users", "alice", "profile", "alice")] = {"city": "Example"}
    directory = FirestoreUserDirectory(db)
    assert not directory.users_in_city("Example")[0].registrations
    RegistrationStore(db).register("alice", 10, "example-one")
    assert len(directory.users_in_city("Example")[0].registrations) == 1
    db.documents[("sessionRevocations", "alice")] = {"throughAuthTime": 10}
    assert not directory.users_in_city("Example")[0].registrations


def test_directory_reads_updated_city_and_passes_custom_labels_separately(db):
    path = ("users", "alice", "profile", "alice")
    db.documents[("users", "alice")] = {}
    db.documents[path] = {"city": "Lahore", "chronicConditions": ["Asthma"]}
    directory = FirestoreUserDirectory(db)
    assert directory.users_in_city("Lahore")[0].custom_conditions == ()

    db.documents[path].update(city="Karachi", customConditions=["Custom label"])
    assert directory.users_in_city("Lahore") == []
    user, = directory.users_in_city("Karachi")
    assert user.conditions == ("Asthma",)
    assert user.custom_conditions == ("Custom label",)
