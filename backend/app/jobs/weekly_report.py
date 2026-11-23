"""Weekly Health Report dispatch hook (Sprint 5, Prompt 8).

A proactive, *scheduled* digest that reaches the user through the **existing**
Phase-1 alert channel — it reuses the dispatch engine's seams and helpers rather
than introducing a new pipeline:

* recipients + tokens + preferences via :class:`UserDirectory`,
* latest city risk via :class:`RiskHistoryProvider` (``latest_two`` → latest),
* the **cited** recommendation via ``recommendation_lookup`` (never generated),
* FCM send via :class:`FcmSender`, and the audit-log/inbox writes + token hygiene
  via :class:`DispatchRepository`.

It differs from the transition alert (``dispatch_alerts``) only in cadence and
targeting: it is sent **once per ISO week** to every consenting user with a
token (not gated on a risk transition), carries ``category="weekly_report"`` and
``deepLink="/weekly-report"``, and is **idempotent per (user, week)** so a re-run
in the same week sends nothing new (the same spam-safety discipline as Phase 1).

The pushed digest summarises what the backend holds — the week's environmental
risk plus a cited recommendation; the full report (which also folds in the user's
adherence) is composed in-app on the Weekly Report screen this alert deep-links
to. No medical text is generated here.

Run (sibling of dispatch_alerts)::

    FIRESTORE_EMULATOR_HOST=localhost:8080 python -m app.jobs.weekly_report
    GOOGLE_APPLICATION_CREDENTIALS=/secure/sa.json python -m app.jobs.weekly_report
"""

from __future__ import annotations

import logging
import os
from dataclasses import dataclass
from datetime import datetime, timezone

from app.jobs import observability
from app.jobs.alerting import recommendation_lookup, targeting
from app.jobs.alerting.messaging import FcmSender
from app.jobs.alerting.recommendation_lookup import Recommendation
from app.jobs.alerting.targeting import CityRisk, TargetUser
from app.jobs.dispatch_alerts import (
    DispatchRepository,
    RiskHistoryProvider,
    UserDirectory,
)
from ml.pipelines import clean

logger = logging.getLogger("foreseeme.jobs.weekly_report")

JOB_NAME = "weekly_report"
CATEGORY = "weekly_report"
DEEP_LINK = "/weekly-report"

#: The severity toggles; a user who has disabled *all* of them has opted out of
#: proactive push, so they receive no weekly report either (respects preferences
#: without inventing a new persisted flag the app cannot set).
_SEVERITY_KEYS = ("highRiskAlerts", "mediumRiskAlerts", "lowRiskUpdates")

_REASONS = {
    "sent": "delivered",
    "token_invalid": "fcm token unregistered",
    "failed": "fcm send failed",
    "skipped_idempotent": "already sent this week",
    "skipped_opted_out": "no notification severities enabled",
    "skipped_no_token": "no delivery token",
}


@dataclass
class WeeklyOutcome:
    uid: str
    city: str
    status: str
    log_id: str | None = None


# --- Preference gate & key --------------------------------------------------


def weekly_enabled(preferences: dict) -> bool:
    """A user is eligible iff they have at least one alert severity enabled."""
    return any(bool(preferences.get(key, False)) for key in _SEVERITY_KEYS)


def weekly_key(uid: str, iso_year: int, iso_week: int) -> str:
    """Idempotency key per ``(user, ISO week)`` — a re-run in the same week is a
    no-op. Stored in ``alertDispatchLog`` (doc-existence check, no index)."""
    return f"{uid}__{CATEGORY}__{iso_year}W{iso_week:02d}"


def _reco_key(user: TargetUser, risk: CityRisk) -> tuple[str, str]:
    """Pick the cited recommendation's ``(category, driver)`` for this user/week.

    Reuses the frozen targeting maps: the user's consented condition category
    that the week's disease makes vulnerable, else the cited default (``*``).
    """
    matched = targeting.user_categories(user.conditions) & targeting.disease_categories(
        risk.disease
    )
    consented_prefs = user.preferences.get("conditions", {}) or {}
    consented = {c for c in matched if bool(consented_prefs.get(c, False))}
    category = targeting.choose_category(consented)
    if category is None:
        return "*", "*"  # -> cited DEFAULT recommendation
    return category, targeting.driver_for_disease(risk.disease)


# --- Composition (pure; no I/O) ---------------------------------------------


def compose_weekly(
    risk: CityRisk,
    recommendation: Recommendation,
    now: datetime,
) -> tuple[str, str, dict[str, str], dict]:
    """Return ``(title, body, data, alert_body)`` for the weekly digest.

    Descriptive and non-diagnostic; the advisory is the cited lookup verbatim.
    ``alert_body`` mirrors the ``userAlerts`` shape the app already parses
    (``dispatch_alerts._alert_body``), with the weekly category + deep link.
    """
    title = f"Your weekly health report — {risk.city}"
    body = (
        f"This week: {risk.risk_level} environmental {risk.disease} risk. "
        f"{recommendation.text}"
    )
    data = {
        "type": CATEGORY,
        "deepLink": DEEP_LINK,
        "category": CATEGORY,
        "city": risk.city,
        "riskLevel": risk.risk_level,
        "riskEstimateId": risk.doc_id,
    }
    alert_body = {
        "title": title,
        "body": body,
        "category": CATEGORY,
        "city": risk.city,
        "riskLevel": risk.risk_level,
        "disease": risk.disease,
        "recommendation": {
            "id": recommendation.id,
            "text": recommendation.text,
            "source": recommendation.source,
            "sourceUrl": recommendation.source_url,
        },
        "deepLink": DEEP_LINK,
        "riskEstimateId": risk.doc_id,
        "createdAt": now,
        "read": False,
        "readAt": None,
    }
    return title, body, data, alert_body


def _log_body(uid: str, risk: CityRisk, recommendation_id: str | None,
              status: str, now: datetime, iso_year: int, iso_week: int) -> dict:
    return {
        "uid": uid,
        "city": risk.city,
        "category": CATEGORY,
        "riskEstimateId": risk.doc_id,
        "riskLevel": risk.risk_level,
        "disease": risk.disease,
        "isoYear": iso_year,
        "isoWeek": iso_week,
        "status": status,
        "reason": _REASONS.get(status, status),
        "recommendationId": recommendation_id,
        "createdAt": now,
    }


# --- Orchestration ----------------------------------------------------------


def run(
    *,
    history: RiskHistoryProvider,
    directory: UserDirectory,
    sender: FcmSender,
    repository: DispatchRepository,
    cities: list[dict],
    now: datetime,
) -> list[WeeklyOutcome]:
    """Send one weekly report per consenting user, idempotent per ISO week.

    One city's failure never aborts the run. Users with no token or with all
    severities disabled are skipped (logged, no send). A ``(uid, week)`` already
    logged is skipped without re-sending.
    """
    iso_year, iso_week, _ = now.isocalendar()
    outcomes: list[WeeklyOutcome] = []

    for city in cities:
        name = city["name"]
        try:
            latest, _previous = history.latest_two(name)
        except Exception as exc:  # one city must not kill the run
            logger.error("history_fetch_failed", extra={"city": name, "error": str(exc)})
            continue
        if latest is None:
            logger.info("city_skipped_no_estimate", extra={"city": name})
            continue

        try:
            users = directory.users_in_city(name)
        except Exception as exc:
            logger.error("users_fetch_failed", extra={"city": name, "error": str(exc)})
            continue

        for user in users:
            outcomes.append(
                _dispatch_one(user, latest, sender, repository, now, iso_year, iso_week)
            )

    return outcomes


def _dispatch_one(
    user: TargetUser,
    risk: CityRisk,
    sender: FcmSender,
    repository: DispatchRepository,
    now: datetime,
    iso_year: int,
    iso_week: int,
) -> WeeklyOutcome:
    if not user.fcm_token:
        return WeeklyOutcome(user.uid, risk.city, "skipped_no_token")
    if not weekly_enabled(user.preferences):
        return WeeklyOutcome(user.uid, risk.city, "skipped_opted_out")

    log_id = weekly_key(user.uid, iso_year, iso_week)
    if repository.has_dispatch(log_id):  # idempotent per (user, week)
        logger.info("skipped_idempotent", extra={"uid": user.uid, "log_id": log_id})
        return WeeklyOutcome(user.uid, risk.city, "skipped_idempotent", log_id)

    category, driver = _reco_key(user, risk)
    recommendation = recommendation_lookup.lookup(category, driver)
    title, body, data, alert_body = compose_weekly(risk, recommendation, now)

    result = sender.send(token=user.fcm_token, title=title, body=body, data=data)
    repository.write_dispatch_log(
        log_id, _log_body(user.uid, risk, recommendation.id, result.status,
                          now, iso_year, iso_week)
    )
    if result.status == "sent":
        repository.write_user_alert(user.uid, log_id, alert_body)
    elif result.status == "token_invalid":
        repository.prune_token(user.uid)
        logger.info("token_pruned", extra={"uid": user.uid})

    logger.info(
        "weekly_report_attempt",
        extra={"uid": user.uid, "city": risk.city, "status": result.status,
               "log_id": log_id},
    )
    return WeeklyOutcome(user.uid, risk.city, result.status, log_id)


# --- Observability: heartbeat + failure signal (Sprint 5, Prompt 12) --------


def classify_run(outcomes: list[WeeklyOutcome]) -> str:
    """Grade a weekly-report run's health for the heartbeat/alert signal.

    Like ``dispatch_alerts``, **zero sends is normal**: mid-week re-runs are all
    idempotent skips, and opted-out/no-token users are healthy skips — none warrant
    an alert. Only an actual FCM send failure degrades the run; a crash is ``failed``
    (handled in :func:`run_and_report`).
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
) -> tuple[observability.RunReport, list[WeeklyOutcome]]:
    """Run the weekly-report job and emit its heartbeat + run-summary signal."""
    started_at = datetime.now(timezone.utc)
    try:
        outcomes = run(
            history=history, directory=directory, sender=sender,
            repository=repository, cities=cities, now=now,
        )
    except Exception:
        report = observability.failed_report(
            JOB_NAME, started_at, datetime.now(timezone.utc),
            "job_execution_failed",
        )
        observability.emit(report, sink=heartbeat, logger=logger)
        raise

    report = observability.RunReport(
        JOB_NAME, classify_run(outcomes), started_at, datetime.now(timezone.utc),
        counts=observability.count_by_status(outcomes),
    )
    observability.emit(report, sink=heartbeat, logger=logger)
    return report, outcomes


# --- Entry point ------------------------------------------------------------


def main() -> int:
    from app.jobs.dispatch_alerts import (
        FirestoreDispatchRepository,
        FirestoreRiskHistoryProvider,
        FirestoreUserDirectory,
        init_firestore,
    )
    from app.jobs.alerting.messaging import FirebaseAdminFcmSender
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
        print(f"  {o.city:11} {o.uid:28} {o.status}")
    print(f"done: {sent}/{len(outcomes)} weekly reports sent [{report.status}]")
    return 1 if report.status == observability.STATUS_FAILED else 0


if __name__ == "__main__":
    import sys

    sys.exit(main())
