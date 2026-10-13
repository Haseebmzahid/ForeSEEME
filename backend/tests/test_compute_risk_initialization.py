"""Initialization regressions: Firebase clients and ADC are always mocked."""

from types import SimpleNamespace
from unittest.mock import Mock

import firebase_admin
import pytest
from firebase_admin import credentials, firestore
from google.auth.credentials import AnonymousCredentials
from google.auth.exceptions import DefaultCredentialsError

from app.jobs import compute_risk, observability
from app.jobs import firestore_runtime


@pytest.fixture
def sdk(monkeypatch):
    for key in ("FIREBASE_PROJECT_ID", "GCLOUD_PROJECT", "GOOGLE_CLOUD_PROJECT",
                "GOOGLE_APPLICATION_CREDENTIALS", "FIRESTORE_EMULATOR_HOST"):
        monkeypatch.delenv(key, raising=False)
    monkeypatch.setattr(firestore_runtime, "_apps", {})
    monkeypatch.setattr(firestore_runtime, "_file_signature", lambda path: path)
    app = SimpleNamespace(project_id="foreseeme-83587", credential=object())
    adc = Mock(name="adc")
    get_app = Mock(side_effect=ValueError("no default app"))
    initialize = Mock(return_value=app)
    client = Mock()
    # No test can discover ambient credentials or construct a real client.
    monkeypatch.setattr(credentials, "ApplicationDefault", adc)
    monkeypatch.setattr(credentials, "Certificate", Mock(side_effect=AssertionError("certificate path")))
    monkeypatch.setattr(firebase_admin, "get_app", get_app)
    monkeypatch.setattr(firebase_admin, "initialize_app", initialize)
    monkeypatch.setattr(firestore, "client", client)
    return SimpleNamespace(app=app, adc=adc, get_app=get_app,
                           initialize=initialize, client=client)


@pytest.mark.parametrize("project_key", ["FIREBASE_PROJECT_ID", "GCLOUD_PROJECT", "GOOGLE_CLOUD_PROJECT"])
def test_adc_uses_explicit_project(monkeypatch, sdk, project_key):
    monkeypatch.setenv(project_key, "foreseeme-83587")
    compute_risk.init_firestore_repository()
    sdk.initialize.assert_called_once_with(sdk.adc.return_value,
                                          options={"projectId": "foreseeme-83587"})
    sdk.client.assert_called_once_with(app=sdk.app)


@pytest.mark.parametrize("credential_path", [None, "optional-service-account.json", "user-adc.json"])
def test_adc_supports_attached_identity_and_optional_files(monkeypatch, sdk, credential_path):
    if credential_path:
        monkeypatch.setenv("GOOGLE_APPLICATION_CREDENTIALS", credential_path)
    compute_risk.init_firestore_repository()
    sdk.adc.assert_called_once_with()
    sdk.initialize.assert_called_once_with(sdk.adc.return_value, options=None)


@pytest.mark.parametrize("project", [None, "demo-test"])
def test_emulator_never_discovers_adc_even_with_a_credential_file(monkeypatch, sdk, project):
    monkeypatch.setenv("FIRESTORE_EMULATOR_HOST", "localhost:8080")
    monkeypatch.setenv("GOOGLE_APPLICATION_CREDENTIALS", "must-not-be-read.json")
    if project:
        monkeypatch.setenv("FIREBASE_PROJECT_ID", project)
    sdk.app.project_id = project or "demo-foreseeme"
    compute_risk.init_firestore_repository()
    credential = sdk.initialize.call_args.args[0]
    assert isinstance(credential.get_credential(), AnonymousCredentials)
    assert sdk.initialize.call_args.kwargs["options"] == {"projectId": sdk.app.project_id}
    sdk.adc.assert_not_called()


def test_missing_adc_fails_before_repository_writes(sdk):
    sdk.client.side_effect = DefaultCredentialsError("ADC unavailable")
    with pytest.raises(DefaultCredentialsError, match="ADC unavailable"):
        compute_risk.init_firestore_repository()
    sdk.client.return_value.collection.assert_not_called()


def test_reuses_matching_default_app_and_heartbeat_client(monkeypatch, sdk):
    monkeypatch.setenv("FIREBASE_PROJECT_ID", sdk.app.project_id)
    compute_risk.init_firestore_repository()
    sdk.initialize.reset_mock()
    sdk.adc.reset_mock()
    sdk.get_app.side_effect = None
    sdk.get_app.return_value = sdk.app
    compute_risk.init_firestore_repository()
    sink = observability.init_firestore_heartbeat_sink()
    assert sink._db is sdk.client.return_value
    sdk.initialize.assert_not_called()
    sdk.adc.assert_not_called()
    assert all(call.kwargs == {"app": sdk.app} for call in sdk.client.call_args_list)


def test_existing_wrong_project_fails_before_client_creation(monkeypatch, sdk):
    compute_risk.init_firestore_repository()
    sdk.client.reset_mock()
    monkeypatch.setenv("FIREBASE_PROJECT_ID", "another-project")
    sdk.get_app.side_effect = None
    sdk.get_app.return_value = sdk.app
    with pytest.raises(ValueError, match="does not match"):
        compute_risk.init_firestore_repository()
    sdk.client.assert_not_called()


def test_conflicting_project_settings_fail_before_initialization(monkeypatch, sdk):
    monkeypatch.setenv("FIREBASE_PROJECT_ID", "one")
    monkeypatch.setenv("GCLOUD_PROJECT", "two")
    with pytest.raises(ValueError, match="Conflicting"):
        compute_risk.init_firestore_repository()
    sdk.initialize.assert_not_called()
    sdk.client.assert_not_called()


def test_named_app_does_not_prevent_default_initialization(monkeypatch, sdk):
    monkeypatch.setattr(firebase_admin, "_apps", {"named": sdk.app})
    compute_risk.init_firestore_repository()
    sdk.initialize.assert_called_once()
