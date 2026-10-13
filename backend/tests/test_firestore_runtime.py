"""Real SDK app/cache behavior with ADC and Firestore construction isolated."""

from types import SimpleNamespace
from unittest.mock import Mock

import firebase_admin
import google.auth
import pytest
from firebase_admin import firestore
from google.auth.credentials import AnonymousCredentials
from google.auth.exceptions import DefaultCredentialsError

from app.jobs import compute_risk, dispatch_alerts, firestore_runtime, observability


@pytest.fixture
def isolated(monkeypatch):
    for key in ("FIREBASE_PROJECT_ID", "GCLOUD_PROJECT", "GOOGLE_CLOUD_PROJECT",
                "GOOGLE_APPLICATION_CREDENTIALS", "FIRESTORE_EMULATOR_HOST",
                "GOOGLE_CLOUD_QUOTA_PROJECT"):
        monkeypatch.delenv(key, raising=False)
    monkeypatch.setenv("FIREBASE_PROJECT_ID", "demo-runtime")
    monkeypatch.setattr(firebase_admin, "_apps", {})
    monkeypatch.setattr(firestore_runtime, "_apps", {})
    monkeypatch.setattr(firestore_runtime, "_file_signature", lambda path: path)
    adc = Mock(return_value=(AnonymousCredentials(), "demo-runtime"))
    monkeypatch.setattr(google.auth, "default", adc)
    clients = []

    def construct(**kwargs):
        db = SimpleNamespace(collection=Mock(), configuration=kwargs)
        clients.append(db)
        return db

    constructor = Mock(side_effect=construct)
    monkeypatch.setattr(firestore.firestore, "Client", constructor)
    # Any unforeseen HTTP attempt fails closed too.
    import requests.sessions
    monkeypatch.setattr(requests.sessions.Session, "request",
                        Mock(side_effect=AssertionError("Real HTTP forbidden")))
    yield SimpleNamespace(adc=adc, constructor=constructor, clients=clients)
    for app in list(firebase_admin._apps.values()):
        firebase_admin.delete_app(app)


@pytest.mark.parametrize("emulator", [False, True])
def test_compatible_reuse_and_heartbeat_share_sdk_cached_client(monkeypatch, isolated, emulator):
    if emulator:
        monkeypatch.setenv("FIRESTORE_EMULATOR_HOST", "localhost:8080")
    repo = compute_risk.init_firestore_repository()
    db = firestore_runtime.get_firestore_client()
    assert observability.init_firestore_heartbeat_sink()._db is db
    assert repo._collection is db.collection.return_value
    assert isolated.constructor.call_count == 1
    assert isolated.adc.call_count == (0 if emulator else 1)
    db.collection.return_value.document.assert_not_called()


def test_dispatch_initializer_remains_compatible_with_shared_heartbeat(isolated):
    db = dispatch_alerts.init_firestore()
    assert observability.init_firestore_heartbeat_sink()._db is db
    assert isolated.constructor.call_count == 1
    db.collection.return_value.document.assert_not_called()


@pytest.mark.parametrize("start,end", [(None, "localhost:8080"), ("localhost:8080", None),
                                     ("localhost:8080", "localhost:8081")])
def test_endpoint_change_fails_before_cached_client_access(monkeypatch, isolated, start, end):
    if start:
        monkeypatch.setenv("FIRESTORE_EMULATOR_HOST", start)
    firestore_runtime.get_firestore_client()
    if end:
        monkeypatch.setenv("FIRESTORE_EMULATOR_HOST", end)
    else:
        monkeypatch.delenv("FIRESTORE_EMULATOR_HOST")
    with pytest.raises(ValueError, match="configuration changed"):
        compute_risk.init_firestore_repository()
    with pytest.raises(ValueError, match="configuration changed"):
        observability.init_firestore_heartbeat_sink()
    assert isolated.constructor.call_count == 1
    isolated.clients[0].collection.assert_not_called()


def test_unknown_preinitialized_app_is_rejected(isolated):
    firebase_admin.initialize_app(AnonymousCredentials(), {"projectId": "demo-runtime"})
    # Simulate a client cached by an unrelated caller.
    firestore.client()
    with pytest.raises(ValueError, match="unknown Firestore configuration"):
        firestore_runtime.get_firestore_client()
    assert isolated.constructor.call_count == 1
    isolated.clients[0].collection.assert_not_called()


def test_project_mismatch_is_rejected(monkeypatch, isolated):
    firestore_runtime.get_firestore_client()
    monkeypatch.setenv("FIREBASE_PROJECT_ID", "demo-other")
    with pytest.raises(ValueError, match="does not match"):
        firestore_runtime.get_firestore_client()
    assert isolated.constructor.call_count == 1


def test_adc_failure_never_constructs_client(isolated):
    isolated.adc.side_effect = DefaultCredentialsError("Mock ADC unavailable")
    with pytest.raises(DefaultCredentialsError, match="Mock ADC unavailable"):
        firestore_runtime.get_firestore_client()
    isolated.constructor.assert_not_called()
    assert not firestore_runtime._apps


def test_credential_file_configuration_change_is_rejected(monkeypatch, isolated):
    monkeypatch.setenv("GOOGLE_APPLICATION_CREDENTIALS", "one.json")
    firestore_runtime.get_firestore_client()
    monkeypatch.setenv("GOOGLE_APPLICATION_CREDENTIALS", "two.json")
    with pytest.raises(ValueError, match="configuration changed"):
        firestore_runtime.get_firestore_client()
    assert isolated.constructor.call_count == 1


def test_same_path_file_replacement_changes_signature(tmp_path):
    path = tmp_path / "dummy.json"
    path.write_text("dummy", encoding="utf-8")
    old = firestore_runtime._file_signature(path)
    path.write_text("different dummy", encoding="utf-8")
    assert firestore_runtime._file_signature(path) != old


def test_changed_file_metadata_rejects_cached_identity(monkeypatch, isolated):
    signature = ["original"]
    monkeypatch.setattr(firestore_runtime, "_file_signature", lambda path: signature[0])
    firestore_runtime.get_firestore_client()
    signature[0] = "replaced"
    with pytest.raises(ValueError, match="configuration changed"):
        firestore_runtime.get_firestore_client()
    isolated.clients[0].collection.assert_not_called()


def test_replaced_app_credential_is_rejected(isolated):
    firestore_runtime.get_firestore_client()
    firebase_admin.get_app()._credential = AnonymousCredentials()
    with pytest.raises(ValueError, match="configuration changed"):
        firestore_runtime.get_firestore_client()
    isolated.clients[0].collection.assert_not_called()
