"""FCM send-seam tests (M7.3): payload shape + failure-classification + retry.

`FirebaseAdminFcmSender.send()` lazily imports `firebase_admin.messaging`, so
these tests patch `messaging.send` directly (a plain function call, no app
needed) rather than initialising a real Firebase app. `messaging.Message` /
`messaging.Notification` / `messaging.UnregisteredError` are constructed for
real — none of them touch the network on their own.
"""

from __future__ import annotations

from unittest.mock import patch

from firebase_admin import messaging as fcm

from app.jobs.alerting.messaging import FirebaseAdminFcmSender, build_notification
from app.jobs.alerting.recommendation_lookup import Recommendation
from app.jobs.alerting.targeting import Target

_TARGET = Target(
    uid="u1",
    city="Lahore",
    category="respiratory",
    driver="Air quality",
    disease="Smog",
    risk_level="High",
    previous_risk_level="Medium",
)
_REC = Recommendation(
    id="rec-resp-air",
    category="respiratory",
    driver="Air quality",
    text="Limit outdoor exertion.",
    source="WHO",
    source_url="https://www.who.int/example",
    deep_link="/resources",
    escalation="If breathing worsens, seek care; emergency -> Rescue 1122.",
)


def _sleep_recorder():
    calls: list[float] = []

    def sleep(seconds: float) -> None:
        calls.append(seconds)

    return sleep, calls


# --- build_notification -------------------------------------------------------


def test_build_notification_shape() -> None:
    title, body, data = build_notification(_TARGET, _REC, "Lahore_2026-06-30")

    assert title == "Air quality rising in Lahore"
    assert body == "High Smog risk. Limit outdoor exertion."
    assert data == {
        "type": "risk_alert",
        "deepLink": "/resources",
        "category": "respiratory",
        "city": "Lahore",
        "riskLevel": "High",
        "riskEstimateId": "Lahore_2026-06-30",
    }
    assert all(isinstance(v, str) for v in data.values())  # FCM requires strings


# --- FirebaseAdminFcmSender: classification -----------------------------------


def test_send_success_no_retry() -> None:
    sleep, calls = _sleep_recorder()
    sender = FirebaseAdminFcmSender(sleep=sleep)

    with patch.object(fcm, "send", return_value="msg-123") as mock_send:
        result = sender.send(token="tok-1", title="t", body="b", data={"k": "v"})

    assert result.status == "sent"
    assert result.message_id == "msg-123"
    assert mock_send.call_count == 1
    assert calls == []  # never slept


def test_send_unregistered_error_is_token_invalid_no_retry() -> None:
    sleep, calls = _sleep_recorder()
    sender = FirebaseAdminFcmSender(sleep=sleep)

    with patch.object(fcm, "send", side_effect=fcm.UnregisteredError("gone")) as mock_send:
        result = sender.send(token="tok-1", title="t", body="b", data={})

    assert result.status == "token_invalid"
    assert result.error == "unregistered"
    assert mock_send.call_count == 1  # never retried
    assert calls == []


def test_send_generic_token_invalid_message_no_retry() -> None:
    """A non-Unregistered exception whose text still says token+invalid is
    classified token_invalid (existing heuristic), not retried."""
    sleep, calls = _sleep_recorder()
    sender = FirebaseAdminFcmSender(sleep=sleep)

    with patch.object(
        fcm, "send", side_effect=ValueError("Requested entity was not found: invalid token")
    ) as mock_send:
        result = sender.send(token="tok-1", title="t", body="b", data={})

    assert result.status == "token_invalid"
    assert mock_send.call_count == 1
    assert calls == []


def test_send_generic_failure_retries_then_succeeds() -> None:
    sleep, calls = _sleep_recorder()
    sender = FirebaseAdminFcmSender(max_retries=2, backoff_seconds=0.5, sleep=sleep)

    with patch.object(
        fcm, "send", side_effect=[RuntimeError("network blip"), "msg-456"]
    ) as mock_send:
        result = sender.send(token="tok-1", title="t", body="b", data={})

    assert result.status == "sent"
    assert result.message_id == "msg-456"
    assert mock_send.call_count == 2
    assert calls == [0.5]  # one backoff before the successful retry


def test_send_generic_failure_exhausts_retries_and_fails() -> None:
    sleep, calls = _sleep_recorder()
    sender = FirebaseAdminFcmSender(max_retries=2, backoff_seconds=0.5, sleep=sleep)

    with patch.object(
        fcm, "send", side_effect=RuntimeError("persistent outage")
    ) as mock_send:
        result = sender.send(token="tok-1", title="t", body="b", data={})

    assert result.status == "failed"
    assert result.error == "persistent outage"
    assert mock_send.call_count == 3  # 1 initial + 2 retries
    assert calls == [0.5, 1.0]  # exponential backoff


def test_send_zero_retries_configured_fails_immediately() -> None:
    sleep, calls = _sleep_recorder()
    sender = FirebaseAdminFcmSender(max_retries=0, sleep=sleep)

    with patch.object(fcm, "send", side_effect=RuntimeError("down")) as mock_send:
        result = sender.send(token="tok-1", title="t", body="b", data={})

    assert result.status == "failed"
    assert mock_send.call_count == 1
    assert calls == []
