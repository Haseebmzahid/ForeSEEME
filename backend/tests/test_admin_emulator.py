"""End-to-end Admin SDK Auth and Firestore writes against demo emulators only."""
import os
import time
from types import SimpleNamespace
from uuid import uuid4
from datetime import datetime, timedelta, timezone
from urllib.parse import urlsplit

import httpx

import pytest
from fastapi.testclient import TestClient
from firebase_admin import auth

from app import admin_api
from app.jobs.account_metrics import backfill_record, run_aggregation
from app.notification_registrations import COLLECTION, RegistrationStore, registration_id

pytestmark = pytest.mark.skipif(
    not (os.getenv("FIREBASE_AUTH_EMULATOR_HOST") and os.getenv("FIRESTORE_EMULATOR_HOST")
         and os.getenv("FIREBASE_PROJECT_ID") == "demo-foreseeme"),
    reason="Set both Firebase emulator hosts and use project demo-foreseeme",
)


def emulator_client():
    origin = f"http://{os.environ['FIREBASE_AUTH_EMULATOR_HOST']}"
    assert urlsplit(origin).hostname in {"localhost", "127.0.0.1", "::1"}
    return httpx.Client(base_url=origin, timeout=10, trust_env=False)


def test_authenticated_registration_reassignment_and_delayed_cleanup():
    db = admin_api.db_client()
    suffix = uuid4().hex
    alice, bob = f"push-alice-{suffix}", f"push-bob-{suffix}"
    password = uuid4().hex
    device = "fixture-" + suffix
    auth.create_user(uid=alice, email=f"{alice}@example.test", password=password,
                     email_verified=True)
    auth.create_user(uid=bob, email=f"{bob}@example.test", password=password)
    client = TestClient(admin_api.app, base_url="https://testserver")
    registry = RegistrationStore(db)
    try:
        with emulator_client() as http:
            a = password_sign_in(http, f"{alice}@example.test", password)
            a.raise_for_status()
            token_a = a.json()["idToken"]
            time.sleep(1.1)
            b = password_sign_in(http, f"{bob}@example.test", password)
            b.raise_for_status()
            token_b = b.json()["idToken"]

        def post(action, bearer):
            return client.post(
                f"/v1/notifications/{action}", json={"token": device},
                headers={"Authorization": f"Bearer {bearer}"},
            )

        assert post("register", token_a).status_code == 204
        old, = registry.for_user(alice)
        pending = post("register", token_b)
        assert pending.status_code == 403
        assert pending.json()["detail"]["code"] == "email_verification_required"
        auth.update_user(bob, email_verified=True)
        with emulator_client() as http:
            b = password_sign_in(http, f"{bob}@example.test", password)
            b.raise_for_status()
            token_b = b.json()["idToken"]
        assert post("register", token_b).status_code == 204
        assert post("register", token_a).status_code == 409
        assert post("unregister", token_a).status_code == 204
        assert not registry.prune(old)
        assert len(registry.for_user(bob)) == 1
        assert post("unregister", token_b).status_code == 204
        assert not registry.for_user(bob)
    finally:
        db.collection(COLLECTION).document(registration_id(device)).delete()
        for uid in (alice, bob):
            db.collection("users").document(uid).delete()
            auth.delete_user(uid)


def password_sign_in(http, email, password):
    return http.post("/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword",
                     params={"key": "demo-api-key"},
                     json={"email": email, "password": password, "returnSecureToken": True})


def test_logout_receipt_retries_and_fresh_sign_in_on_real_emulators():
    db = admin_api.db_client()
    uid = "logout-" + uuid4().hex
    email, password = f"{uid}@example.test", uuid4().hex
    device = f"device-{uid}"
    cutoff = db.collection("sessionRevocations").document(uid)
    auth.create_user(uid=uid, email=email, password=password, email_verified=True)
    client = TestClient(admin_api.app, base_url="https://testserver")
    try:
        with emulator_client() as http:
            first_login = password_sign_in(http, email, password)
            first_login.raise_for_status()
            old = {"Authorization": "Bearer " + first_login.json()["idToken"]}
            registration = "/v1/notifications/register"
            logout = "/v1/session/logout"
            assert client.post(registration, headers=old, json={"token": device}).status_code == 204
            assert client.post(logout, headers=old).status_code == 204
            first_cutoff = cutoff.get().get("throughAuthTime")
            valid_after = auth.get_user(uid).tokens_valid_after_timestamp
            assert first_cutoff < valid_after // 1000

            fresh_login = password_sign_in(http, email, password)
            fresh_login.raise_for_status()
            fresh = {"Authorization": "Bearer " + fresh_login.json()["idToken"]}
            assert client.post(logout, headers=old).status_code == 204
            assert auth.get_user(uid).tokens_valid_after_timestamp == valid_after
            assert cutoff.get().get("throughAuthTime") == first_cutoff
            assert client.post(registration, headers=old, json={"token": device}).status_code == 401
            assert client.post(registration, headers=fresh, json={"token": device}).status_code == 204
            assert len(RegistrationStore(db).for_user(uid)) == 1
    finally:
        for intent in cutoff.collection("logoutIntents").stream():
            intent.reference.delete()
        cutoff.delete()
        db.collection(COLLECTION).document(registration_id(device)).delete()
        db.collection("users").document(uid).delete()
        auth.delete_user(uid)


def enroll_and_sign_in(http, first_factor, email, password):
    def post(action, body):
        response = http.post(f"/identitytoolkit.googleapis.com/v2/accounts/{action}",
                             params={"key": "demo-api-key"}, json=body)
        response.raise_for_status()
        return response.json()

    def verification(session):
        response = http.get("/emulator/v1/projects/demo-foreseeme/verificationCodes")
        response.raise_for_status()
        code = next(item["code"] for item in response.json()["verificationCodes"]
                    if item["sessionInfo"] == session)
        return {"sessionInfo": session, "code": code}

    enrollment = post("mfaEnrollment:start", {
        "idToken": first_factor, "phoneEnrollmentInfo": {"phoneNumber": "+16505550101"},
    })
    post("mfaEnrollment:finalize", {
        "idToken": first_factor, "displayName": "Demo factor",
        "phoneVerificationInfo": verification(enrollment["phoneSessionInfo"]["sessionInfo"]),
    })
    result = password_sign_in(http, email, password)
    result.raise_for_status()
    challenge = result.json()
    pending = challenge["mfaPendingCredential"]
    sign_in = post("mfaSignIn:start", {
        "mfaPendingCredential": pending, "mfaEnrollmentId": challenge["mfaInfo"][0]["mfaEnrollmentId"],
        "phoneSignInInfo": {},
    })
    final = post("mfaSignIn:finalize", {
        "mfaPendingCredential": pending,
        "phoneVerificationInfo": verification(sign_in["phoneResponseInfo"]["sessionInfo"]),
    })
    return final["idToken"]


def test_admin_workflow(monkeypatch):
    db = admin_api.db_client()
    uid = "module8-" + uuid4().hex
    actor = uid + "-operator"
    email = f"{uid}@example.org"
    actor_email = f"{actor}@example.org"
    password = uuid4().hex
    auth.create_user(uid=uid, email=email, password=password, email_verified=True,
                     display_name="Emulator User")
    auth.create_user(uid=actor, email=actor_email, password=password, email_verified=True)
    http = emulator_client()
    try:
        user = auth.get_user(uid)
        profile = db.collection("users").document(uid).collection("profile").document(uid)
        profile.set({"privateTestField": "must not leave Firestore"})
        assert profile.get(field_paths=[]).to_dict() == {}
        assert backfill_record(db, user, apply=False) == "would_update"
        assert backfill_record(db, user, apply=True) == "updated"
        assert backfill_record(db, user, apply=True) == "skipped"
        directory = db.collection("userDirectory").document(uid)
        assert directory.get().get("status") == "active"
        assert "privateTestField" not in directory.get().to_dict()
        directory.update({"name": "Retained preferred name", "status": "active"})
        assert backfill_record(db, user, apply=True) == "skipped"

        auth.set_custom_user_claims(actor, {"admin": True})
        password_response = password_sign_in(http, actor_email, password)
        password_response.raise_for_status()
        first_factor = password_response.json()["idToken"]
        client = TestClient(admin_api.app, base_url="https://testserver")
        client.headers["Authorization"] = f"Bearer {first_factor}"
        rejected = client.post(f"/v1/users/{uid}", json={"action": "suspend"})
        assert rejected.status_code == 403
        assert rejected.json()["detail"]["code"] == "mfa_required"
        token = enroll_and_sign_in(http, first_factor, actor_email, password)
        client.headers["Authorization"] = f"Bearer {token}"
        old_login = password_sign_in(http, email, password)
        old_login.raise_for_status()
        old_headers = {"Authorization": "Bearer " + old_login.json()["idToken"]}
        register = "/v1/notifications/register"
        device = f"fixture-{uid}"
        assert client.post(register, headers=old_headers, json={"token": device}).status_code == 204
        # Pin the authorized test requests to one rate-limit window.
        current = time.time()
        monkeypatch.setattr(admin_api, "time", SimpleNamespace(time=lambda: current))

        def post(action, **kwargs):
            return client.post(f"/v1/users/{uid}", json={"action": action, **kwargs})

        assert post("delete").status_code == 422
        assert post("suspend").status_code == 200
        cutoff = db.collection("sessionRevocations").document(uid)
        suspended_through = cutoff.get().get("throughAuthTime")
        assert not RegistrationStore(db).for_user(uid)
        assert client.post(register, headers=old_headers, json={"token": device}).status_code == 401
        assert auth.get_user(uid).disabled
        assert password_sign_in(http, email, password).status_code == 400
        assert directory.get().get("authDisabled") is True
        assert post("reactivate").status_code == 200
        assert cutoff.get().get("throughAuthTime") == suspended_through
        assert not auth.get_user(uid).disabled
        assert password_sign_in(http, email, password).status_code == 200
        assert directory.get().get("status") == "active"
        assert directory.get().get("name") == "Retained preferred name"
        retained = db.collection("users").document(uid).collection("example").document("record")
        retained.set({"retention": "test"})
        assert post("delete", confirmUid=uid, retention="retain_firestore").status_code == 200
        assert cutoff.get().get("throughAuthTime") >= suspended_through
        with pytest.raises(auth.UserNotFoundError):
            auth.get_user(uid)
        assert not directory.get().exists
        assert retained.get().exists
        assert backfill_record(db, user, apply=True) == "skipped"

        article_id = uid
        body = {"title": "Title", "summary": "Summary", "sourceName": "Source",
                "sourceUrl": "https://example.org", "topic": "heat", "categories": ["heat"],
                "content": [{"kind": "paragraph", "text": "Body"}], "create": True}
        assert client.post(f"/v1/articles/{article_id}", json=body).status_code == 200
        assert client.post(f"/v1/articles/{article_id}", json=body).status_code == 409
        assert client.post(f"/v1/articles/{article_id}", json={**body, "create": False,
                                                               "title": "Edited"}).status_code == 200
        assert db.collection("articles").document(article_id).get().get("title") == "Edited"
        override = {"riskLevel": "High", "disease": "Smog", "reason": "Operator review",
                    "expiresAt": "2099-01-01T00:00:00Z"}
        assert client.post("/v1/overrides/Lahore", json=override).status_code == 422
        override["expiresAt"] = (datetime.now(timezone.utc) + timedelta(hours=1)).isoformat()
        assert client.post("/v1/overrides/Lahore", json=override).status_code == 200
        assert db.collection("overrides").document("Lahore").get().get("riskLevel") == "High"
        assert client.post("/v1/overrides/Lahore/clear").status_code == 200
        assert db.collection("overrides").document("Lahore").get().get("active") is False
        assert post("suspend").status_code == 429
        logs = [doc.to_dict() for doc in db.collection("adminActivityLog").stream()]
        logs = [event for event in logs if event.get("authorUid") == actor]
        assert sum(event["outcome"] == "success" for event in logs) == 7
        assert sum(event["outcome"] == "failure" for event in logs) == 2
        assert all(event["eventId"] and event["requestId"] for event in logs)

        db.collection("alertDispatchLog").document(uid + "-sent").set({"status": "sent"})
        db.collection("alertDispatchLog").document(uid + "-failed").set({"status": "failed"})
        assert run_aggregation(db, 30)
        assert db.collection("operationalMetrics").document("alerts").get().get("totalAlerts") >= 1
        assert db.collection("operationalMetrics").document("accounts").get().get("measurementWindowDays") == 30
    finally:
        http.close()
        db.collection(COLLECTION).document(registration_id(f"fixture-{uid}")).delete()
        db.collection("sessionRevocations").document(uid).delete()
        for account_uid in (uid, actor):
            try:
                auth.delete_user(account_uid)
            except auth.UserNotFoundError:
                pass



def test_invitation_uses_firebase_password_reset_and_can_retry(monkeypatch):
    db = admin_api.db_client()
    actor = "invite-operator-" + uuid4().hex
    actor_email = f"{actor}@example.org"
    email = f"invite-{uuid4().hex}@example.org"
    password = uuid4().hex
    auth.create_user(uid=actor, email=actor_email, password=password, email_verified=True)
    http = emulator_client()
    try:
        auth.set_custom_user_claims(actor, {"admin": True})
        first_factor = password_sign_in(http, actor_email, password)
        first_factor.raise_for_status()
        token = enroll_and_sign_in(http, first_factor.json()["idToken"], actor_email, password)
        client = TestClient(admin_api.app, base_url="https://testserver",
                            headers={"Authorization": f"Bearer {token}"})
        sender = admin_api.send_invitation

        def unavailable(*_args):
            raise TimeoutError("simulated sender outage")

        monkeypatch.setattr(admin_api, "send_invitation", unavailable)
        incomplete = client.post("/v1/invitations", json={"email": email})
        assert incomplete.status_code == 503
        assert incomplete.json()["detail"]["code"] == "invitation_delivery_unconfirmed"
        user = auth.get_user_by_email(email)
        assert not user.custom_claims
        assert db.collection("userDirectory").document(user.uid).get().get("status") == "pending"

        monkeypatch.setattr(admin_api, "send_invitation", sender)
        assert client.post("/v1/invitations", json={"email": email}).status_code == 200
        assert auth.get_user_by_email(email).uid == user.uid
        assert client.post("/v1/invitations", json={"email": email}).status_code == 409
        response = http.get("/emulator/v1/projects/demo-foreseeme/oobCodes")
        response.raise_for_status()
        code = next(item["oobCode"] for item in response.json()["oobCodes"]
                    if item["email"] == email and item["requestType"] == "PASSWORD_RESET")
        response = http.post(
            "/identitytoolkit.googleapis.com/v1/accounts:resetPassword",
            params={"key": "demo-api-key"},
            json={"oobCode": code, "newPassword": password},
        )
        response.raise_for_status()
        assert password_sign_in(http, email, password).status_code == 200

        attempts = [snap.to_dict() for snap in db.collection("adminActivityLog").stream()]
        recorded = [event["outcome"] for event in attempts if event.get("authorUid") == actor]
        assert recorded.count("success") == 1
        assert recorded.count("failure") == 2
    finally:
        http.close()
        auth.delete_user(actor)
        try:
            auth.delete_user(auth.get_user_by_email(email).uid)
        except auth.UserNotFoundError:
            pass
