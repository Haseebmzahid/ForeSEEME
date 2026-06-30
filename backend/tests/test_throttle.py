"""Throttle + idempotency gate unit tests (Sprint 4, Prompt 3).

Pure logic over a fake ledger: idempotency precedes throttle; the 24h window is
inclusive at the boundary and per-(user, category).
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

from app.jobs.alerting import throttle
from app.jobs.alerting.throttle import ThrottleDecision

NOW = datetime(2026, 6, 30, 12, 0, tzinfo=timezone.utc)


class FakeLedger:
    def __init__(self, dispatched=frozenset(), sent=()):
        self._dispatched = set(dispatched)  # log_ids already present
        self._sent = list(sent)  # (uid, category, created_at)

    def has_dispatch(self, log_id):
        return log_id in self._dispatched

    def recently_sent(self, uid, category, since):
        return any(
            u == uid and c == category and t >= since
            for (u, c, t) in self._sent
        )


def _eval(ledger, log_id="k", uid="u1", category="respiratory", now=NOW):
    return throttle.evaluate(
        ledger, uid=uid, category=category, log_id=log_id, now=now
    )


def test_allow_when_fresh() -> None:
    assert _eval(FakeLedger()) is ThrottleDecision.ALLOW


def test_idempotent_when_log_exists() -> None:
    assert _eval(FakeLedger(dispatched={"k"})) is ThrottleDecision.SKIP_IDEMPOTENT


def test_throttled_within_window() -> None:
    led = FakeLedger(sent=[("u1", "respiratory", NOW - timedelta(hours=1))])
    assert _eval(led, log_id="new") is ThrottleDecision.SKIP_THROTTLED


def test_window_boundary_is_inclusive() -> None:
    led = FakeLedger(sent=[("u1", "respiratory", NOW - timedelta(hours=24))])
    assert _eval(led, log_id="new") is ThrottleDecision.SKIP_THROTTLED


def test_allow_after_window() -> None:
    led = FakeLedger(sent=[("u1", "respiratory", NOW - timedelta(hours=25))])
    assert _eval(led, log_id="new") is ThrottleDecision.ALLOW


def test_throttle_is_per_category() -> None:
    led = FakeLedger(sent=[("u1", "cardiovascular", NOW - timedelta(hours=1))])
    assert _eval(led, log_id="new", category="respiratory") is ThrottleDecision.ALLOW


def test_idempotency_precedes_throttle() -> None:
    led = FakeLedger(
        dispatched={"k"},
        sent=[("u1", "respiratory", NOW - timedelta(hours=1))],
    )
    assert _eval(led, log_id="k") is ThrottleDecision.SKIP_IDEMPOTENT
