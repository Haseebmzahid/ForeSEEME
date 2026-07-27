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
from datetime import datetime, timezone
from typing import Protocol

from app.jobs import observability
from app.jobs.alerting import recommendation_lookup, targeting, throttle
from app.jobs.alerting.messaging import (
    FcmSender,
    FirebaseAdminFcmSender,
    SendResult,
    build_notification,
)
from app.jobs.alerting.recommendation_lookup import Recommendation
from app.jobs.alerting.targeting import CityRisk, Target, TargetUser
from app.jobs.alerting.throttle import ThrottleDecision
from ml.pipelines import clean

logger = logging.getLogger("foreseeme.jobs.dispatch_alerts")

JOB_NAME = "dispatch_alerts"
COLLECTION_RISK = "riskEstimates"
COLLECTION_LOG = "alertDispatchLog"
COLLECTION_USER_ALERTS = "userAlerts"
THROTTLE_WINDOW = throttle.THROTTLE_WINDOW

_REASONS = {
    "sent": "delivered",
    "token_invalid": "fcm token unregistered",
    "failed": "fcm send failed",
    "skipped_idempotent": "already dispatched for this estimate",
    "skipped_throttled": "within 24h of a prior alert for this category",
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
    """Reads + idempotent writes for the audit log/inbox, plus token hygiene."""

    def write_dispatch_log(self, log_id: str, body: dict) -> None: ...

    def write_user_alert(self, uid: str, alert_id: str, body: dict) -> None: ...

    # Ledger reads for the throttle/idempotency gate (Prompt 3).
    def has_dispatch(self, log_id: str) -> bool: ...

    def recently_sent(self, uid: str, category: str, since: datetime) -> bool: ...

    # Token hygiene (Prompt 3): drop a token FCM reported as unregistered.
    def prune_token(self, uid: str) -> None: ...

    # Concurrency gate (M7.4): atomically create-if-absent the log doc right
    # before send, so two overlapping dispatch runs can't both pass the
    # (non-atomic) `has_dispatch` check and both send. Returns True iff this
    # call won the claim; False means another run already claimed it.
    def claim_dispatch(self, log_id: str, now: datetime) -> bool: ...


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
    log_id = dispatch_key(target.uid, latest.doc_id, target.category)

    # Idempotency + 24h throttle gate (Prompt 3) — before any send.
    decision = throttle.evaluate(
        repository,
        uid=target.uid,
        category=target.category,
        log_id=log_id,
        now=now,
    )
    if decision is ThrottleDecision.SKIP_IDEMPOTENT:
        # The estimate was already dispatched; leave the original log intact.
        logger.info(
            "skipped_idempotent", extra={"uid": target.uid, "log_id": log_id}
        )
        return DispatchOutcome(
            target.uid, target.city, target.category, "skipped_idempotent", log_id
        )
    if decision is ThrottleDecision.SKIP_THROTTLED:
        repository.write_dispatch_log(
            log_id, _skip_log_body(target, latest, "skipped_throttled", now)
        )
        logger.info(
            "skipped_throttled", extra={"uid": target.uid, "log_id": log_id}
        )
        return DispatchOutcome(
            target.uid, target.city, target.category, "skipped_throttled", log_id
        )

    # Concurrency gate (M7.4): `has_dispatch` above is a cheap, non-atomic
    # pre-check; two overlapping runs could both pass it before either writes
    # (see docs/dispatch_concurrency.md). `claim_dispatch` atomically
    # create-if-absents the log doc — only the run that wins the claim may
    # proceed to send. A loser treats this exactly like an idempotent skip.
    if not repository.claim_dispatch(log_id, now):
        logger.info(
            "skipped_idempotent_claim_lost", extra={"uid": target.uid, "log_id": log_id}
        )
        return DispatchOutcome(
            target.uid, target.city, target.category, "skipped_idempotent", log_id
        )

    recommendation = recommendation_lookup.lookup(target.category, target.driver)
    title, body, data = build_notification(target, recommendation, latest.doc_id)

    assert user.fcm_token is not None  # guaranteed by targeting.evaluate
    try:
        result = sender.send(token=user.fcm_token, title=title, body=body, data=data)
    except Exception as exc:  # noqa: BLE001 — the claim must always be finalized
        logger.error(
            "dispatch_send_crashed",
            extra={"uid": target.uid, "log_id": log_id, "error": str(exc)},
        )
        repository.write_dispatch_log(
            log_id, _crash_log_body(target, latest, str(exc), now)
        )
        return DispatchOutcome(target.uid, target.city, target.category, "failed", log_id)

    repository.write_dispatch_log(
        log_id, _log_body(target, latest, recommendation, result, now)
    )
    if result.status == "sent":
        repository.write_user_alert(
            target.uid,
            log_id,
            _alert_body(target, latest, recommendation, title, body, now),
        )
    elif result.status == "token_invalid":
        # Token hygiene: drop the dead token so future runs skip it.
        repository.prune_token(target.uid)
        logger.info("token_pruned", extra={"uid": target.uid})

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


def _skip_log_body(
    target: Target, latest: CityRisk, status: str, now: datetime
) -> dict:
    """Audit entry for a suppressed (throttled) dispatch — no send, no inbox."""
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
        "status": status,
        "reason": _REASONS.get(status, status),
        "recommendationId": None,
        "fcmMessageId": None,
        "createdAt": now,
        "throttleWindowEnd": now + THROTTLE_WINDOW,
    }


def _crash_log_body(target: Target, latest: CityRisk, error: str, now: datetime) -> dict:
    """Audit entry finalizing a claimed log_id whose send raised unexpectedly
    (M7.4). Same shape as `_log_body`'s failure case, so a claim is never left
    stuck 'claimed' forever — a later run's `has_dispatch`/`claim_dispatch`
    correctly treats this estimate/category as already (unsuccessfully)
    attempted, same as any other terminal `failed` outcome."""
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
        "status": "failed",
        "reason": _REASONS["failed"],
        "recommendationId": None,
        "fcmMessageId": None,
        "createdAt": now,
        "throttleWindowEnd": now + THROTTLE_WINDOW,
        "error": error,
    }


# --- Observability: heartbeat + failure signal (Sprint 5, Prompt 12) --------


def classify_run(outcomes: list[DispatchOutcome]) -> str:
    """Grade a dispatch run's health for the heartbeat/alert signal.

    **Zero sends is normal, not a failure**: most runs have no risk transition, so
    an empty run is expected (alerting on it would be pure noise — the risk the
    prompt calls out). A run is only ``degraded`` when an FCM send actually failed
    (``status == "failed"``); a crash before outcomes are produced is ``failed``
    (handled in :func:`run_and_report`). Idempotent/throttled skips are healthy —
    they are the spam-safety guard working.
    """
    if any(o.status == "failed" for o in outcomes):
        return observability.STATUS_DEGRADED
    return observability.STATUS_OK


def run_and_report(
    *,
    history: RiskHistoryProvider,
    directory: UserDirectory,
    sender: FcmSender,
    repository: DispatchRepository,
    heartbeat: observability.HeartbeatSink,
    cities: list[dict],
    now: datetime,
) -> tuple[observability.RunReport, list[DispatchOutcome]]:
    """Run the dispatch job and emit its heartbeat + run-summary signal.

    Observability wrapper over :func:`run` (unchanged). A crash emits a ``failed``
    heartbeat and re-raises so the process exits non-zero.
    """
    started_at = datetime.now(timezone.utc)
    try:
        outcomes = run(
            history=history, directory=directory, sender=sender,
            repository=repository, cities=cities, now=now,
        )
    except Exception as exc:
        report = observability.failed_report(
            JOB_NAME, started_at, datetime.now(timezone.utc),
            f"{type(exc).__name__}: {exc}",
        )
        observability.emit(report, sink=heartbeat, logger=logger)
        raise

    report = observability.RunReport(
        JOB_NAME, classify_run(outcomes), started_at, datetime.now(timezone.utc),
        counts=observability.count_by_status(outcomes),
    )
    observability.emit(report, sink=heartbeat, logger=logger)
    return report, outcomes


# --- Firestore seams (service account; lazy firebase imports) ---------------


def _to_iso(value: object) -> str:
    if isinstance(value, str):
        return value
    isoformat = getattr(value, "isoformat", None)
    return isoformat() if callable(isoformat) else str(value)


_REQUIRED_RISK_FIELDS = ("city", "riskLevel", "disease", "generatedAt", "modelVersion")


def _malformed_risk_reason(data: dict) -> str | None:
    """Returns why a `riskEstimates` doc is unusable, or ``None`` if it's fine."""
    missing = [f for f in _REQUIRED_RISK_FIELDS if not data.get(f)]
    return f"missing/empty fields: {', '.join(missing)}" if missing else None


def _to_city_risk(doc) -> CityRisk | None:
    """Parses one `riskEstimates` doc, or ``None`` (logged) if it's malformed.

    Required fields missing/empty used to silently become ``""``, which could
    make a corrupt doc look like a real (and wrong) risk level to
    ``targeting.risk_rose()``. A malformed doc is now treated as absent rather
    than guessed at.
    """
    data = doc.to_dict() or {}
    reason = _malformed_risk_reason(data)
    if reason:
        logger.warning(
            "malformed_risk_estimate_skipped", extra={"doc_id": doc.id, "reason": reason}
        )
        return None
    return CityRisk(
        city=data["city"],
        risk_level=data["riskLevel"],
        disease=data["disease"],
        generated_at=_to_iso(data["generatedAt"]),
        model_version=data["modelVersion"],
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
        parsed = [_to_city_risk(doc) for doc in snapshot]
        valid = [risk for risk in parsed if risk is not None]
        latest = valid[0] if valid else None
        previous = valid[1] if len(valid) > 1 else None
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

    def has_dispatch(self, log_id: str) -> bool:
        return self._db.collection(COLLECTION_LOG).document(log_id).get().exists

    def recently_sent(self, uid: str, category: str, since: datetime) -> bool:
        from google.cloud.firestore_v1.base_query import FieldFilter

        # Needs the composite index (uid, category, status, createdAt) in
        # firestore.indexes.json.
        snapshot = (
            self._db.collection(COLLECTION_LOG)
            .where(filter=FieldFilter("uid", "==", uid))
            .where(filter=FieldFilter("category", "==", category))
            .where(filter=FieldFilter("status", "==", "sent"))
            .where(filter=FieldFilter("createdAt", ">=", since))
            .limit(1)
            .get()
        )
        return len(list(snapshot)) > 0

    def prune_token(self, uid: str) -> None:
        from firebase_admin import firestore

        self._db.collection("users").document(uid).update(
            {"fcmToken": firestore.DELETE_FIELD}
        )

    def claim_dispatch(self, log_id: str, now: datetime) -> bool:
        """Atomically create-if-absent the log doc (M7.4 concurrency gate).

        `write_dispatch_log` immediately overwrites this placeholder with the
        real, final body once the send outcome is known — the transaction's
        only job is to guarantee at most one caller ever observes an absent
        doc for a given `log_id`, closing the read-then-much-later-write race
        `has_dispatch` alone cannot close (see docs/dispatch_concurrency.md).
        """
        from firebase_admin import firestore

        doc_ref = self._db.collection(COLLECTION_LOG).document(log_id)

        @firestore.transactional
        def _claim(transaction) -> bool:
            snapshot = doc_ref.get(transaction=transaction)
            if snapshot.exists:
                return False
            transaction.set(doc_ref, {"status": "claimed", "claimedAt": now})
            return True

        return _claim(self._db.transaction())


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

            class _EmulatorCredential(credentials.Base):
                """Never touches Application Default Credentials. Required
                because passing no explicit credential defaults to
                ``credentials.ApplicationDefault()``, which eagerly calls
                ``google.auth.default()`` and raises when no real GCP
                credentials are configured (as in a pure local-emulator
                sandbox) — the emulator host env var alone does not prevent
                that lookup. The emulator itself does not validate tokens, so
                an anonymous credential is sufficient."""

                def get_credential(self):
                    from google.auth.credentials import AnonymousCredentials

                    return AnonymousCredentials()

            firebase_admin.initialize_app(
                _EmulatorCredential(), options={"projectId": project_id}
            )
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
    report, outcomes = run_and_report(
        history=FirestoreRiskHistoryProvider(db),
        directory=FirestoreUserDirectory(db),
        sender=FirebaseAdminFcmSender(),
        repository=FirestoreDispatchRepository(db),
        heartbeat=observability.FirestoreHeartbeatSink(db),
        cities=clean.load_cities(),
        now=datetime.now(timezone.utc),
    )

    sent = sum(1 for o in outcomes if o.status == "sent")
    for o in outcomes:
        print(f"  {o.city:11} {o.uid:28} {o.category:14} {o.status}")
    print(f"done: {sent}/{len(outcomes)} alerts sent [{report.status}]")
    return 1 if report.status == observability.STATUS_FAILED else 0


if __name__ == "__main__":
    import sys

    sys.exit(main())
