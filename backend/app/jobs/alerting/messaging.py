"""FCM send seam for the dispatch engine (Sprint 4, Prompt 2).

Wraps firebase-admin messaging behind a small protocol so the engine is testable
with a fake. Classifies each send as ``sent`` / ``token_invalid`` / ``failed``;
**token pruning is Prompt 3** (this only surfaces the ``token_invalid`` status).
The notification text is built from the targeting result + the cited
recommendation — no medical text is generated here.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass
from typing import Callable, Protocol

from app.jobs.alerting.recommendation_lookup import Recommendation
from app.jobs.alerting.targeting import Target

logger = logging.getLogger("foreseeme.jobs.alerting.messaging")


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


PUSH_DISCLAIMER = "Health awareness only — not a medical diagnosis."

def with_push_disclaimer(body: str) -> str:
    return body if body.startswith(f"{PUSH_DISCLAIMER} ") else f"{PUSH_DISCLAIMER} {body}"


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
    body = with_push_disclaimer(
        f"{target.risk_level} {target.disease} risk. {recommendation.text}"
    )
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
    API service never needs firebase-admin.

    Retries a bounded number of times, with backoff, on a transient (non-token)
    send failure before classifying it terminal (``failed``). This matters
    because a ``failed`` outcome still writes the audit log keyed by the
    estimate's idempotency key — a later run would never retry it on its own —
    so the only chance to recover from a transient FCM/network blip is within
    this call. Token-related failures are never retried: a dead token stays
    dead regardless of how many times you resend to it, and Prompt 3's token
    pruning should run immediately rather than waste retries on it.
    """

    def __init__(
        self,
        *,
        max_retries: int = 2,
        backoff_seconds: float = 0.5,
        sleep: Callable[[float], None] = time.sleep,
    ) -> None:
        self._max_retries = max_retries
        self._backoff_seconds = backoff_seconds
        self._sleep = sleep

    def send(
        self, *, token: str, title: str, body: str, data: dict[str, str]
    ) -> SendResult:
        from firebase_admin import messaging

        message = messaging.Message(
            token=token,
            notification=messaging.Notification(title=title, body=with_push_disclaimer(body)),
            data={k: str(v) for k, v in data.items()},
        )

        attempt = 0
        while True:
            try:
                message_id = messaging.send(message)
                return SendResult(status="sent", message_id=message_id)
            except messaging.UnregisteredError:
                # Token no longer valid — Prompt 3 prunes it from `users`.
                return SendResult(status="token_invalid", error="unregistered")
            except Exception as exc:  # noqa: BLE001 — classify any other failure
                invalid = "token" in str(exc).lower() and "invalid" in str(exc).lower()
                if invalid:
                    return SendResult(status="token_invalid", error="invalid_token")
                if attempt >= self._max_retries:
                    return SendResult(status="failed", error=type(exc).__name__)
                logger.warning(
                    "fcm_send_retry",
                    extra={"attempt": attempt + 1, "max_retries": self._max_retries,
                           "error": type(exc).__name__},
                )
                self._sleep(self._backoff_seconds * (2**attempt))
                attempt += 1
