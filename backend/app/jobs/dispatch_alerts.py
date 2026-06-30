"""Personalized alert dispatch engine (Sprint 4, Prompt 2).

Scheduled backend job (sibling of ``compute_risk``) that turns a city risk
*transition* into a personalized, consented FCM alert with a **cited**
recommendation, then audits the attempt (``alertDispatchLog``) and writes the
in-app inbox doc (``userAlerts``) on success. Runs only on the backend via the
firebase-admin service account; **Flutter never dispatches**.

Implements the frozen Prompt-1 contract (``docs/alert_dispatch_design.md``):
targeting predicate, the per-estimate idempotency key, and both schemas. The
24h **throttle**, the idempotency *check*, and token **pruning** are Prompt 3 —
this prompt establishes the engine and writes the audit log keyed by the
deterministic id so those gates can build on it.

Run (sibling of compute_risk)::

    FIRESTORE_EMULATOR_HOST=localhost:8080 python -m app.jobs.dispatch_alerts
    GOOGLE_APPLICATION_CREDENTIALS=/secure/sa.json python -m app.jobs.dispatch_alerts
"""

from __future__ import annotations

import logging
import os
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Protocol

from app.jobs.alerting import recommendation_lookup, targeting
from app.jobs.alerting.messaging import (
    FcmSender,
    FirebaseAdminFcmSender,
    SendResult,
    build_notification,
)
from app.jobs.alerting.recommendation_lookup import Recommendation
from app.jobs.alerting.targeting import CityRisk, Target, TargetUser
from ml.pipelines import clean

logger = logging.getLogger("foreseeme.jobs.dispatch_alerts")

COLLECTION_RISK = "riskEstimates"
COLLECTION_LOG = "alertDispatchLog"
COLLECTION_USER_ALERTS = "userAlerts"
THROTTLE_WINDOW = timedelta(hours=24)

_REASONS = {
    "sent": "delivered",
    "token_invalid": "fcm token unregistered",
    "failed": "fcm send failed",
}


# --- Seams (injected; the whole job runs offline against fakes) -------------


class RiskHistoryProvider(Protocol):
    """Latest + previous estimate for a city (newest first)."""

    def latest_two(
        self, city: str
    ) -> tuple[CityRisk | None, CityRisk | None]: ...


class UserDirectory(Protocol):
    """Users whose profile city matches, with token + preferences."""

    def users_in_city(self, city: str) -> list[TargetUser]: ...


class DispatchRepository(Protocol):
    """Idempotent writes for the audit log + the in-app inbox."""

    def write_dispatch_log(self, log_id: str, body: dict) -> None: ...

    def write_user_alert(self, uid: str, alert_id: str, body: dict) -> None: ...


@dataclass
class DispatchOutcome:
    uid: str
    city: str
    category: str
    status: str
    log_id: str | None = None


# --- Orchestration ----------------------------------------------------------


def run(
    *,
    history: RiskHistoryProvider,
    directory: UserDirectory,
    sender: FcmSender,
    repository: DispatchRepository,
    cities: list[dict],
    now: datetime,
) -> list[DispatchOutcome]:
    """Dispatch alerts for every qualifying (user, city) on a single run.

    One city's failure never aborts the run; only users passing the targeting
    predicate become send *attempts* (each audited; inbox on success).
    """
    outcomes: list[DispatchOutcome] = []
    for city in cities:
        name = city["name"]
        try:
            latest, previous = history.latest_two(name)
        except Exception as exc:  # one city must not kill the run
            logger.error(
                "history_fetch_failed", extra={"city": name, "error": str(exc)}
            )
            continue

        if latest is None or previous is None:
            logger.info("city_skipped_insufficient_history", extra={"city": name})
            continue
        if not targeting.risk_rose(previous, latest):
            logger.info(
                "city_skipped_no_transition",
                extra={"city": name, "level": latest.risk_level},
            )
            continue

        try:
            users = directory.users_in_city(name)
        except Exception as exc:
            logger.error(
                "users_fetch_failed", extra={"city": name, "error": str(exc)}
            )
            continue

        for user in users:
            target = targeting.evaluate(user, latest, previous)
            if target is None:
                continue
            outcomes.append(
                _dispatch(target, latest, user, sender, repository, now)
            )

    return outcomes


def _dispatch(
    target: Target,
    latest: CityRisk,
    user: TargetUser,
    sender: FcmSender,
    repository: DispatchRepository,
    now: datetime,
) -> DispatchOutcome:
    recommendation = recommendation_lookup.lookup(target.category, target.driver)
    log_id = dispatch_key(target.uid, latest.doc_id, target.category)
    title, body, data = build_notification(target, recommendation, latest.doc_id)

    assert user.fcm_token is not None  # guaranteed by targeting.evaluate
    result = sender.send(token=user.fcm_token, title=title, body=body, data=data)

    repository.write_dispatch_log(
        log_id, _log_body(target, latest, recommendation, result, now)
    )
    if result.status == "sent":
        repository.write_user_alert(
            target.uid,
            log_id,
            _alert_body(target, latest, recommendation, title, body, now),
        )

    logger.info(
        "dispatch_attempt",
        extra={
            "uid": target.uid,
            "city": target.city,
            "category": target.category,
            "status": result.status,
            "log_id": log_id,
        },
    )
    return DispatchOutcome(
        target.uid, target.city, target.category, result.status, log_id
    )


def dispatch_key(uid: str, risk_estimate_id: str, category: str) -> str:
    """The frozen idempotency key (contract §3): derived from the *specific*
    risk estimate so a re-run never re-sends."""
    return f"{uid}__{risk_estimate_id}__{category}"


def _log_body(
    target: Target,
    latest: CityRisk,
    recommendation: Recommendation,
    result: SendResult,
    now: datetime,
) -> dict:
    return {
        "uid": target.uid,
        "city": target.city,
        "category": target.category,
        "riskEstimateId": latest.doc_id,
        "generatedAt": latest.generated_at,
        "previousRiskLevel": target.previous_risk_level,
        "riskLevel": target.risk_level,
        "disease": target.disease,
        "driver": target.driver,
        "modelVersion": latest.model_version,
        "status": result.status,
        "reason": _REASONS.get(result.status, result.status),
        "recommendationId": recommendation.id,
        "fcmMessageId": result.message_id,
        "createdAt": now,
        "throttleWindowEnd": now + THROTTLE_WINDOW,
    }


def _alert_body(
    target: Target,
    latest: CityRisk,
    recommendation: Recommendation,
    title: str,
    body: str,
    now: datetime,
) -> dict:
    return {
        "title": title,
        "body": body,
        "category": target.category,
        "city": target.city,
        "riskLevel": target.risk_level,
        "disease": target.disease,
        "recommendation": {
            "id": recommendation.id,
            "text": recommendation.text,
            "source": recommendation.source,
            "sourceUrl": recommendation.source_url,
        },
        "deepLink": recommendation.deep_link,
        "riskEstimateId": latest.doc_id,
        "createdAt": now,
        "read": False,
        "readAt": None,
    }


# --- Firestore seams (service account; lazy firebase imports) ---------------


def _to_iso(value: object) -> str:
    if isinstance(value, str):
        return value
    isoformat = getattr(value, "isoformat", None)
    return isoformat() if callable(isoformat) else str(value)


def _to_city_risk(doc) -> CityRisk:
    data = doc.to_dict() or {}
    return CityRisk(
        city=data.get("city", ""),
        risk_level=data.get("riskLevel", ""),
        disease=data.get("disease", ""),
        generated_at=_to_iso(data.get("generatedAt")),
        model_version=data.get("modelVersion", ""),
        doc_id=doc.id,
    )


class FirestoreRiskHistoryProvider:
    """Reads the two most recent estimates per city (same composite index as the
    Sprint 3 client query)."""

    def __init__(self, db) -> None:
        self._db = db

    def latest_two(self, city: str):
        from firebase_admin import firestore
        from google.cloud.firestore_v1.base_query import FieldFilter

        snapshot = (
            self._db.collection(COLLECTION_RISK)
            .where(filter=FieldFilter("city", "==", city))
            .order_by("generatedAt", direction=firestore.Query.DESCENDING)
            .limit(2)
            .get()
        )
        docs = list(snapshot)
        latest = _to_city_risk(docs[0]) if docs else None
        previous = _to_city_risk(docs[1]) if len(docs) > 1 else None
        return latest, previous


class FirestoreUserDirectory:
    """Enumerates ``users`` (token + preferences) joined with each user's profile
    (``users/{uid}/profile/{uid}`` — city + chronicConditions)."""

    def __init__(self, db) -> None:
        self._db = db

    def users_in_city(self, city: str) -> list[TargetUser]:
        users: list[TargetUser] = []
        for user_doc in self._db.collection("users").stream():
            data = user_doc.to_dict() or {}
            profile_snap = (
                self._db.collection("users")
                .document(user_doc.id)
                .collection("profile")
                .document(user_doc.id)
                .get()
            )
            if not profile_snap.exists:
                continue
            profile = profile_snap.to_dict() or {}
            if profile.get("city") != city:
                continue
            users.append(
                TargetUser(
                    uid=user_doc.id,
                    city=city,
                    conditions=tuple(profile.get("chronicConditions") or []),
                    fcm_token=data.get("fcmToken"),
                    preferences=data.get("notificationPreferences") or {},
                )
            )
        return users


class FirestoreDispatchRepository:
    """Idempotent ``set`` writes (keyed by the deterministic ids) for the audit
    log + inbox."""

    def __init__(self, db) -> None:
        self._db = db

    def write_dispatch_log(self, log_id: str, body: dict) -> None:
        self._db.collection(COLLECTION_LOG).document(log_id).set(body)

    def write_user_alert(self, uid: str, alert_id: str, body: dict) -> None:
        (
            self._db.collection(COLLECTION_USER_ALERTS)
            .document(uid)
            .collection("items")
            .document(alert_id)
            .set(body)
        )


def init_firestore():
    """Initialise the Admin SDK from the environment (compute_risk pattern)."""
    import firebase_admin
    from firebase_admin import credentials, firestore

    if not firebase_admin._apps:
        cred_path = os.getenv("GOOGLE_APPLICATION_CREDENTIALS")
        emulator = os.getenv("FIRESTORE_EMULATOR_HOST")
        if cred_path:
            logger.info("firestore_auth", extra={"mode": "service_account"})
            firebase_admin.initialize_app(credentials.Certificate(cred_path))
        elif emulator:
            project_id = (
                os.getenv("FIREBASE_PROJECT_ID")
                or os.getenv("GCLOUD_PROJECT")
                or "demo-foreseeme"
            )
            logger.info(
                "firestore_auth",
                extra={"mode": "emulator", "host": emulator, "project": project_id},
            )
            firebase_admin.initialize_app(options={"projectId": project_id})
        else:
            raise SystemExit(
                "Set GOOGLE_APPLICATION_CREDENTIALS (real project) or "
                "FIRESTORE_EMULATOR_HOST (emulator) before running the job."
            )
    return firestore.client()


# --- Entry point ------------------------------------------------------------


def main() -> int:
    from app.logging_config import configure_logging

    configure_logging(os.getenv("LOG_LEVEL", "INFO"))
    db = init_firestore()
    outcomes = run(
        history=FirestoreRiskHistoryProvider(db),
        directory=FirestoreUserDirectory(db),
        sender=FirebaseAdminFcmSender(),
        repository=FirestoreDispatchRepository(db),
        cities=clean.load_cities(),
        now=datetime.now(timezone.utc),
    )

    sent = sum(1 for o in outcomes if o.status == "sent")
    for o in outcomes:
        print(f"  {o.city:11} {o.uid:28} {o.category:14} {o.status}")
    print(f"done: {sent}/{len(outcomes)} alerts sent")
    return 0


if __name__ == "__main__":
    import sys

    sys.exit(main())
