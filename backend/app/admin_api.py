"""Dedicated HTTPS admin service. Start with uvicorn app.admin_api:app."""
from __future__ import annotations

import hashlib
import json
import logging
import os
import re
import time
from secrets import token_urlsafe
from datetime import datetime, timedelta, timezone
from typing import Annotated, Literal
from urllib.parse import urlencode, urlsplit
from urllib.request import HTTPRedirectHandler, Request as UrlRequest, build_opener
from uuid import uuid4

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from firebase_admin import auth, firestore
from pydantic import BaseModel, ConfigDict, Field, StringConstraints, field_validator

from app.jobs.account_metrics import account_projection
from app.jobs.compute_risk import load_cities
from app.jobs.firestore_runtime import get_firestore_client
from app.notification_registrations import InactiveSession, RegistrationConflict, RegistrationStore
from app.session_revocation import (
    LogoutRejected, LogoutUnconfirmed, complete_logout, record_revocation,
)

app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)
logger = logging.getLogger(__name__)
origins = [value.strip() for value in os.getenv("ADMIN_WEB_ORIGINS", "").split(",") if value.strip()]
if any(not re.fullmatch(r"https://[^/*?#\s]+", origin) for origin in origins):
    raise RuntimeError("ADMIN_WEB_ORIGINS requires exact HTTPS origins")
if origins:
    app.add_middleware(
        CORSMiddleware, allow_origins=origins, allow_methods=["POST"],
        allow_headers=["Authorization", "Content-Type"],
    )

Key = Annotated[str, StringConstraints(min_length=1, max_length=128, pattern=r"^[^/\x00-\x1f\x7f]+$")]
Topic = Literal["lungs", "asthma", "airQuality", "heat", "heart"]


class Input(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class Block(Input):
    kind: Literal["heading", "paragraph", "tip", "warning"]
    text: str = Field(min_length=1, max_length=5000)


class Article(Input):
    title: str = Field(min_length=1, max_length=160)
    summary: str = Field(min_length=1, max_length=2000)
    sourceName: str = Field(min_length=1, max_length=160)
    sourceUrl: str = Field(min_length=1, max_length=2048)
    topic: Topic
    categories: list[Topic] = Field(max_length=5)
    content: list[Block] = Field(min_length=1, max_length=60)
    create: bool

    @field_validator("sourceUrl")
    @classmethod
    def validate_source(cls, value):
        url = urlsplit(value)
        if (url.scheme != "https" or not url.hostname or url.username is not None
                or any(char.isspace() for char in value) or "\\" in value):
            raise ValueError("HTTPS source URL required")
        _ = url.port
        return value

    @field_validator("content")
    @classmethod
    def validate_content(cls, value):
        if all(block.kind == "heading" for block in value):
            raise ValueError("At least one reading block is required")
        return value


class Override(Input):
    riskLevel: Literal["Low", "Medium", "High"]
    disease: Literal["Dengue", "Smog", "Influenza", "Respiratory Illness", "Heat-Related Illness"]
    reason: str = Field(min_length=1, max_length=1000)
    expiresAt: datetime


class AccountAction(Input):
    action: Literal["suspend", "reactivate", "delete"]
    confirmUid: Key | None = None
    retention: Literal["retain_firestore"] | None = None


FcmToken = Annotated[str, StringConstraints(
    strict=True, strip_whitespace=False, min_length=1, max_length=4096,
    pattern=r"^[A-Za-z0-9:_-]+$",
)]


class NotificationToken(Input):
    token: FcmToken


class NotificationRegistration(NotificationToken):
    previousToken: FcmToken | None = None


def problem(status: int, code: str):
    return HTTPException(status, detail={"code": code})


@app.exception_handler(RequestValidationError)
async def validation_error(_request, _exc):
    return JSONResponse(status_code=422, content={"detail": {"code": "invalid_input"}})


@app.middleware("http")
async def transport(request: Request, call_next):
    if request.url.scheme != "https":
        return JSONResponse(status_code=400, content={"detail": {"code": "https_required"}})
    if request.method == "POST":
        length = request.headers.get("content-length")
        if length is None and request.headers.get("content-type"):
            return JSONResponse(status_code=411, content={"detail": {"code": "length_required"}})
        if length is not None and (not length.isdecimal() or len(length) > 6 or int(length) > 400_000):
            return JSONResponse(status_code=413, content={"detail": {"code": "payload_too_large"}})
    return await call_next(request)


def db_client():
    if bool(os.getenv("FIREBASE_AUTH_EMULATOR_HOST")) != bool(os.getenv("FIRESTORE_EMULATOR_HOST")):
        raise RuntimeError("Auth and Firestore emulator modes must match")
    if os.getenv("FIRESTORE_EMULATOR_HOST") and os.getenv("FIREBASE_PROJECT_ID") != "demo-foreseeme":
        raise RuntimeError("Admin emulator requires demo-foreseeme")
    if not os.getenv("FIRESTORE_EMULATOR_HOST") and os.getenv("FIRESTORE_AUTH_MODE") != "attached":
        raise RuntimeError("Admin service requires attached runtime identity")
    return get_firestore_client()


def verify_session_token(token: str) -> dict:
    try:
        return auth.verify_id_token(token, check_revoked=True)
    except (auth.InvalidIdTokenError, auth.ExpiredIdTokenError, auth.RevokedIdTokenError,
            auth.UserDisabledError, auth.UserNotFoundError, ValueError):
        raise problem(401, "invalid_session") from None


def bearer_token(request: Request) -> str:
    header = request.headers.get("authorization", "")
    if not header.startswith("Bearer ") or not 8 < len(header) <= 8192:
        raise problem(401, "token_required")
    return header[7:]


def session_identity(claims):
    uid = claims.get("uid")
    auth_time = claims.get("auth_time")
    if not isinstance(uid, str) or not uid or "/" in uid or type(auth_time) is not int or auth_time < 0:
        raise problem(401, "invalid_session")
    return uid, auth_time


def verify_admin(token: str, *, now: float) -> dict:
    claims = verify_session_token(token)
    if claims.get("admin") is not True:
        raise problem(403, "admin_required")
    firebase_claims = claims.get("firebase")
    if not isinstance(firebase_claims, dict) or firebase_claims.get("sign_in_second_factor") not in ("phone", "totp"):
        raise problem(403, "mfa_required")
    auth_time = claims.get("auth_time")
    if type(auth_time) is not int or not -30 <= now - auth_time <= 300:
        raise problem(403, "recent_sign_in_required")
    return claims


def rate_limit(db, uid: str, now: float):
    key = hashlib.sha256(uid.encode()).hexdigest()
    ref = db.collection("adminRateLimits").document(key)
    interval = int(now) // 60

    @firestore.transactional
    def consume(transaction):
        previous = ref.get(transaction=transaction, timeout=5).to_dict() or {}
        count = previous.get("count", 0) if previous.get("interval") == interval else 0
        if count >= 10:
            raise HTTPException(429, detail={"code": "rate_limited"},
                                headers={"Retry-After": str(60 - int(now) % 60)})
        transaction.set(ref, {"interval": interval, "count": count + 1})

    consume(db.transaction(max_attempts=3))


def authorize(request: Request):
    token = bearer_token(request)
    try:
        db = db_client()
        now = time.time()
        actor = verify_admin(token, now=now)
        cutoff = db.collection("sessionRevocations").document(actor["uid"]).get(timeout=5)
        if cutoff.exists and actor["auth_time"] <= cutoff.to_dict()["throughAuthTime"]:
            raise problem(401, "invalid_session")
        if (auth.get_user(actor["uid"]).custom_claims or {}).get("admin") is not True:
            raise problem(403, "admin_required")
        rate_limit(db, actor["uid"], now)
        return db, actor
    except HTTPException:
        raise
    except Exception as exc:
        logger.error("Admin authorization unavailable (%s)", type(exc).__name__)
        raise problem(503, "authorization_unavailable") from None


Access = Annotated[tuple, Depends(authorize)]


@app.post("/v1/session/logout", status_code=204)
def revoke_own_session(request: Request):
    """Revoke every Firebase session belonging to the verified caller."""
    token = bearer_token(request)
    try:
        db = db_client()
        try:
            claims = auth.verify_id_token(token, check_revoked=True)
            may_start = True
        except auth.RevokedIdTokenError:
            # A signature-verified revoked token can only resume its existing receipt.
            claims = auth.verify_id_token(token, check_revoked=False)
            may_start = False
        uid, authenticated_at = session_identity(claims)
    except (auth.InvalidIdTokenError, auth.ExpiredIdTokenError, auth.RevokedIdTokenError,
            auth.UserDisabledError, auth.UserNotFoundError, ValueError):
        raise problem(401, "invalid_session") from None
    except HTTPException:
        raise
    except Exception as exc:
        logger.error("Session verification unavailable (%s)", type(exc).__name__)
        raise problem(503, "revocation_unconfirmed") from None

    try:
        complete_logout(
            db, uid, authenticated_at, may_start=may_start,
            read_valid_after=lambda: auth.get_user(uid).tokens_valid_after_timestamp,
            revoke=lambda: auth.revoke_refresh_tokens(uid),
        )
    except LogoutRejected:
        raise problem(401, "invalid_session") from None
    except LogoutUnconfirmed:
        raise problem(503, "revocation_unconfirmed") from None
    except Exception as exc:
        logger.error("Session revocation unconfirmed (%s)", type(exc).__name__)
        raise problem(503, "revocation_unconfirmed") from None


def change_registration(
    request: Request, token_value: str, *, register: bool, previous_token: str | None = None,
):
    token = bearer_token(request)
    try:
        claims = verify_session_token(token)
        uid, auth_time = session_identity(claims)
        if register and claims.get("email_verified") is not True:
            raise problem(403, "email_verification_required")
        store = RegistrationStore(db_client())
        if register:
            store.register(uid, auth_time, token_value, previous_token)
        else:
            store.unregister(uid, auth_time, token_value)
    except HTTPException:
        raise
    except InactiveSession:
        raise problem(401, "invalid_session") from None
    except RegistrationConflict:
        raise problem(409, "registration_conflict") from None
    except Exception as exc:
        logger.error("Notification registration unavailable (%s)", type(exc).__name__)
        raise problem(503, "registration_unavailable") from None


@app.post("/v1/notifications/register", status_code=204)
def register_notification(request: Request, body: NotificationRegistration):
    change_registration(request, body.token, register=True, previous_token=body.previousToken)


@app.post("/v1/notifications/unregister", status_code=204)
def unregister_notification(request: Request, body: NotificationToken):
    change_registration(request, body.token, register=False)


def audit(db, actor, action, target, request_id, outcome, summary):
    ref = db.collection("adminActivityLog").document()
    event = {
        "eventId": ref.id,
        "authorUid": actor["uid"],
        "authorEmail": actor.get("email", ""),
        "action": action,
        "target": target,
        "requestId": request_id,
        "outcome": outcome,
        "summary": summary,
        "createdAt": datetime.now(timezone.utc).isoformat(timespec="microseconds"),
        "recordedAt": firestore.SERVER_TIMESTAMP,
    }
    return ref, event


def audit_failure(db, actor, action, target, request_id, code):
    ref, event = audit(db, actor, action, target, request_id, "failure", code)
    try:
        ref.create(event, timeout=5)
    except Exception as exc:
        logger.error("Admin audit unavailable request=%s type=%s", request_id, type(exc).__name__)
        raise problem(503, "audit_unavailable") from None


def valid_key(value: str):
    if value in {".", ".."} or re.fullmatch(r"__.*__", value):
        raise problem(422, "invalid_target")


def audited_document_write(db, actor, action, ref, apply):
    request_id = uuid4().hex
    audit_ref, event = audit(db, actor, action, ref.id, request_id, "success", action)

    @firestore.transactional
    def commit(transaction):
        apply(transaction, ref)
        transaction.create(audit_ref, event)

    try:
        commit(db.transaction(max_attempts=3))
    except HTTPException as exc:
        audit_failure(db, actor, action, ref.id, request_id, exc.detail["code"])
        raise
    except Exception as exc:
        logger.error("Admin transaction unconfirmed request=%s type=%s", request_id, type(exc).__name__)
        raise HTTPException(503, detail={"code": "operation_unconfirmed", "requestId": request_id}) from None
    return {"requestId": request_id}


@app.post("/v1/articles/{article_id}")
def save_article(article_id: Annotated[str, Key], body: Article, access: Access):
    valid_key(article_id)
    db, actor = access
    ref = db.collection("articles").document(article_id)
    action = "article_create" if body.create else "article_update"

    def apply(transaction, ref):
        previous = ref.get(transaction=transaction, timeout=5).to_dict()
        if body.create and previous is not None:
            raise problem(409, "article_exists")
        if not body.create and previous is None:
            raise problem(404, "article_missing")
        payload = body.model_dump(exclude={"create"})
        if previous is None or any(previous.get(key) != payload[key] for key in
                                   ("content", "sourceName", "sourceUrl")):
            payload.update(verified=False, authority="other", lastVerifiedAt=firestore.DELETE_FIELD)
        if previous is None:
            payload.pop("lastVerifiedAt")
            payload["publishedAt"] = datetime.now(timezone.utc).isoformat()
            transaction.create(ref, payload)
        else:
            transaction.update(ref, payload)

    return audited_document_write(db, actor, action, ref, apply)


@app.post("/v1/overrides/{city}")
def set_override(city: Annotated[str, Key], body: Override, access: Access):
    db, actor = access
    if city not in {row["name"] for row in load_cities()}:
        raise problem(422, "invalid_city")
    now = datetime.now(timezone.utc)
    if body.expiresAt.tzinfo is None or not now < body.expiresAt <= now + timedelta(days=7):
        raise problem(422, "invalid_expiry")
    ref = db.collection("overrides").document(city)

    def apply(transaction, ref):
        transaction.set(ref, {
            **body.model_dump(mode="json"), "city": city, "active": True,
            "authorUid": actor["uid"], "authorEmail": actor.get("email", ""),
            "createdAt": now.isoformat(),
        })

    return audited_document_write(db, actor, "override_set", ref, apply)


@app.post("/v1/overrides/{city}/clear")
def clear_override(city: Annotated[str, Key], access: Access):
    valid_key(city)
    db, actor = access
    ref = db.collection("overrides").document(city)

    def apply(transaction, ref):
        data = ref.get(transaction=transaction, timeout=5).to_dict() or {}
        if data.get("active") is not True:
            raise problem(409, "no_active_override")
        transaction.update(ref, {"active": False})

    return audited_document_write(db, actor, "override_clear", ref, apply)


@app.post("/v1/users/{uid}")
def change_account(uid: Annotated[str, Key], body: AccountAction, access: Access):
    valid_key(uid)
    db, actor = access
    request_id = uuid4().hex
    action = f"user_{body.action}"
    directory = db.collection("userDirectory").document(uid)
    lock = db.collection("adminAccountOperations").document(uid)

    try:
        if uid == actor["uid"]:
            raise problem(403, "protected_account")
        if body.action == "delete" and (body.confirmUid != uid or body.retention != "retain_firestore"):
            raise problem(422, "deletion_confirmation_required")
        try:
            target = auth.get_user(uid)
        except auth.UserNotFoundError:
            raise problem(404, "account_missing") from None
        if (target.custom_claims or {}).get("admin") is True:
            raise problem(403, "protected_account")
    except HTTPException as exc:
        audit_failure(db, actor, action, uid, request_id, exc.detail["code"])
        raise
    except Exception as exc:
        logger.error("Account lookup unavailable request=%s type=%s", request_id, type(exc).__name__)
        raise problem(503, "account_lookup_unavailable") from None

    @firestore.transactional
    def reserve(transaction):
        if lock.get(transaction=transaction, timeout=5).exists:
            raise problem(409, "account_operation_pending")
        log_ref, event = audit(db, actor, action, uid, request_id, "started", "Account change requested")
        transaction.create(lock, {
            "requestId": request_id, "action": action, "authorUid": actor["uid"],
            "authorEmail": actor.get("email", ""), "createdAt": firestore.SERVER_TIMESTAMP,
        })
        transaction.create(log_ref, event)

    try:
        reserve(db.transaction(max_attempts=3))
    except HTTPException as exc:
        audit_failure(db, actor, action, uid, request_id, exc.detail["code"])
        raise
    except Exception as exc:
        logger.error("Account reservation unconfirmed request=%s type=%s", request_id, type(exc).__name__)
        raise problem(503, "audit_unavailable") from None

    try:
        ends_sessions = body.action in ("suspend", "delete")
        if ends_sessions:
            record_revocation(db, uid, int(time.time()))
        if body.action == "delete":
            auth.delete_user(uid)
            try:
                auth.get_user(uid)
            except auth.UserNotFoundError:
                pass
            else:
                raise RuntimeError("Account deletion unconfirmed")
        else:
            disabled = body.action == "suspend"
            auth.update_user(uid, disabled=disabled)
            if disabled:
                auth.revoke_refresh_tokens(uid)
            target = auth.get_user(uid)
            if target.disabled != disabled:
                raise RuntimeError("Account status unconfirmed")
        if ends_sessions:
            # Cover sessions authenticated while the Auth mutation was in flight.
            record_revocation(db, uid, int(time.time()))

        log_ref, event = audit(db, actor, action, uid, request_id, "success", "Auth state verified")
        batch = db.batch()
        if body.action == "delete":
            batch.delete(directory)
        else:
            payload = account_projection(target)
            payload.pop("name", None)
            batch.set(directory, payload, merge=True)
        batch.create(log_ref, event)
        if body.action == "delete":
            batch.set(lock, {"deleted": True, "requestId": request_id})
        else:
            batch.delete(lock)
        batch.commit(timeout=10)
    except Exception as exc:
        # Auth and Firestore cannot share a transaction. Preserve the reservation
        # and started event until an operator verifies the actual Auth outcome.
        logger.error("Account operation unconfirmed request=%s type=%s", request_id, type(exc).__name__)
        try:
            ref, event = audit(db, actor, action, uid, request_id, "unknown", "Auth or audit outcome unconfirmed")
            ref.create(event, timeout=5)
        except Exception as audit_exc:
            logger.error("Account outcome audit unavailable request=%s type=%s",
                         request_id, type(audit_exc).__name__)
        raise HTTPException(503, detail={"code": "operation_unconfirmed", "requestId": request_id}) from None
    return {"requestId": request_id}


class Invitation(Input):
    email: str = Field(min_length=5, max_length=254)

    @field_validator("email")
    @classmethod
    def validate_email(cls, value):
        email = value.lower()
        local, _, domain = email.rpartition("@")
        atom = r"[a-z0-9!#$%&'*+/=?^_{}|~-]+"
        label = r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?"
        if (len(local) > 64 or not re.fullmatch(rf"{atom}(?:[.]{atom})*", local)
                or not re.fullmatch(rf"{label}(?:[.]{label})+", domain)):
            raise ValueError("A valid email address is required")
        return email


def invitation_endpoint():
    emulator = os.getenv("FIREBASE_AUTH_EMULATOR_HOST")
    if emulator:
        origin = f"http://{emulator}"
        if urlsplit(origin).hostname not in {"localhost", "127.0.0.1", "::1"}:
            raise problem(503, "invitation_unavailable")
        return f"{origin}/identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=demo-api-key"
    key = os.getenv("ADMIN_INVITATION_API_KEY")
    if not key:
        raise problem(503, "invitation_unavailable")
    return ("https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?"
            + urlencode({"key": key}))


class NoEmailRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def send_invitation(endpoint, email):
    request = UrlRequest(
        endpoint,
        data=json.dumps({"requestType": "PASSWORD_RESET", "email": email}).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with build_opener(NoEmailRedirect()).open(request, timeout=8):
        pass


@app.post("/v1/invitations")
def provision_account(body: Invitation, access: Access):
    db, actor = access
    endpoint = invitation_endpoint()
    request_id = uuid4().hex
    key = hashlib.sha256(body.email.encode()).hexdigest()
    reservation = (db.collection("adminAccountOperations").document("invitations")
                   .collection("requests").document(key))

    @firestore.transactional
    def reserve(transaction):
        existing = reservation.get(transaction=transaction, timeout=5).to_dict() or {}
        if existing.get("state") == "running":
            raise problem(409, "invitation_pending")
        retrying = existing.get("state") == "retry"
        uid = existing["uid"] if retrying else uuid4().hex
        account_lock = db.collection("adminAccountOperations").document(uid)
        if account_lock.get(transaction=transaction, timeout=5).exists:
            raise problem(409, "account_operation_pending")
        ref, event = audit(db, actor, "user_provision", uid, request_id,
                           "started", "Invitation requested")
        transaction.set(reservation, {
            "uid": uid, "state": "running", "requestId": request_id,
            "createdAt": firestore.SERVER_TIMESTAMP,
        })
        transaction.create(ref, event)
        transaction.create(account_lock, {
            "requestId": request_id, "invitationKey": key,
            "authorUid": actor["uid"], "authorEmail": actor.get("email", ""),
        })
        return uid, retrying

    def finish(uid, outcome, summary, *, retry=False):
        ref, event = audit(db, actor, "user_provision", uid, request_id, outcome, summary)
        batch = db.batch()
        batch.create(ref, event)
        batch.delete(db.collection("adminAccountOperations").document(uid))
        if retry:
            batch.update(reservation, {"state": "retry"})
        else:
            batch.delete(reservation)
        batch.commit(timeout=10)

    try:
        uid, retrying = reserve(db.transaction(max_attempts=3))
        if retrying:
            try:
                account = auth.get_user(uid)
            except auth.UserNotFoundError:
                finish(uid, "failure", "Invited account no longer exists")
                raise problem(409, "invitation_restart_required") from None
            if account.email != body.email or account.disabled or (account.custom_claims or {}).get("admin"):
                finish(uid, "failure", "Invited account is no longer eligible")
                raise problem(409, "protected_account")
        else:
            try:
                account = auth.create_user(uid=uid, email=body.email, password=token_urlsafe(48) + "Aa1!")
            except auth.EmailAlreadyExistsError:
                finish(uid, "failure", "An account already uses this address")
                raise problem(409, "account_exists") from None

        directory = db.collection("userDirectory").document(uid)
        directory.set({"status": "pending", **account_projection(account)} if not retrying
                      else account_projection(account), merge=True, timeout=5)
        try:
            send_invitation(endpoint, body.email)
        except Exception as exc:
            logger.warning("Invitation delivery unconfirmed request=%s type=%s",
                           request_id, type(exc).__name__)
            finish(uid, "failure", "Account created; invitation delivery unconfirmed", retry=True)
            raise HTTPException(503, detail={
                "code": "invitation_delivery_unconfirmed", "requestId": request_id,
            }) from None
        finish(uid, "success", "Firebase accepted invitation email request")
    except HTTPException:
        raise
    except Exception as exc:
        logger.error("Provisioning unconfirmed request=%s type=%s", request_id, type(exc).__name__)
        raise HTTPException(503, detail={"code": "operation_unconfirmed", "requestId": request_id}) from None
    return {"requestId": request_id}
