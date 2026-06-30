"""FCM send seam for the dispatch engine (Sprint 4, Prompt 2).

Wraps firebase-admin messaging behind a small protocol so the engine is testable
with a fake. Classifies each send as ``sent`` / ``token_invalid`` / ``failed``;
**token pruning is Prompt 3** (this only surfaces the ``token_invalid`` status).
The notification text is built from the targeting result + the cited
recommendation — no medical text is generated here.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol

from app.jobs.alerting.recommendation_lookup import Recommendation
from app.jobs.alerting.targeting import Target


@dataclass(frozen=True)
class SendResult:
    status: str  # "sent" | "token_invalid" | "failed"
    message_id: str | None = None
    error: str | None = None


# Human noun phrase per driver, for a calm title.
_DRIVER_PHRASE: dict[str, str] = {
    "Air quality": "Air quality",
    "Heat": "Heat",
    "Respiratory": "Respiratory risk",
    "Vector-borne": "Risk",
}


def build_notification(
    target: Target,
    recommendation: Recommendation,
    risk_estimate_id: str,
) -> tuple[str, str, dict[str, str]]:
    """Returns ``(title, body, data)`` for the FCM message + in-app routing.

    ``data`` carries the deep link + identifiers used by the in-app handlers
    (Prompt 4); all values are strings, as FCM requires.
    """
    phrase = _DRIVER_PHRASE.get(target.driver, "Risk")
    title = f"{phrase} rising in {target.city}"
    body = f"{target.risk_level} {target.disease} risk. {recommendation.text}"
    data = {
        "type": "risk_alert",
        "deepLink": recommendation.deep_link,
        "category": target.category,
        "city": target.city,
        "riskLevel": target.risk_level,
        "riskEstimateId": risk_estimate_id,
    }
    return title, body, data


class FcmSender(Protocol):
    def send(
        self, *, token: str, title: str, body: str, data: dict[str, str]
    ) -> SendResult: ...


class FirebaseAdminFcmSender:
    """Production sender using firebase-admin (Admin SDK). Imported lazily so the
    API service never needs firebase-admin."""

    def send(
        self, *, token: str, title: str, body: str, data: dict[str, str]
    ) -> SendResult:
        from firebase_admin import messaging

        message = messaging.Message(
            token=token,
            notification=messaging.Notification(title=title, body=body),
            data={k: str(v) for k, v in data.items()},
        )
        try:
            message_id = messaging.send(message)
            return SendResult(status="sent", message_id=message_id)
        except messaging.UnregisteredError:
            # Token no longer valid — Prompt 3 prunes it from `users`.
            return SendResult(status="token_invalid", error="unregistered")
        except Exception as exc:  # noqa: BLE001 — classify any other failure
            invalid = "token" in str(exc).lower() and "invalid" in str(exc).lower()
            status = "token_invalid" if invalid else "failed"
            return SendResult(status=status, error=str(exc))
