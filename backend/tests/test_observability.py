"""Scheduled-job observability tests (Sprint 5, Prompt 12).

Covers the shared signal module plus each job's ``run_and_report`` wrapper:
- a successful run writes an ``ok`` heartbeat + an INFO ``job_run`` log;
- a simulated failure (compute_risk producing zero output) writes a ``failed``
  heartbeat + an ERROR ``job_run`` log with ``alert=true``;
- dispatch/weekly "zero sends" is healthy (``ok``), never a false alarm;
- heartbeat bodies carry no secrets;
- a heartbeat-sink failure never crashes the job it observes.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import datetime, timezone

from app.jobs import compute_risk, dispatch_alerts, observability, weekly_report
from app.jobs.alerting.messaging import SendResult
from app.jobs.alerting.targeting import CityRisk, TargetUser
from app.predict import load_bundle, resolve_artifact_path

STARTED = datetime(2026, 7, 2, 12, 0, 0, tzinfo=timezone.utc)
FINISHED = datetime(2026, 7, 2, 12, 0, 1, 500_000, tzinfo=timezone.utc)  # +1.5s


# --- Shared fakes -----------------------------------------------------------


class FakeHeartbeat:
    def __init__(self) -> None:
        self.docs: dict[str, dict] = {}

    def write_heartbeat(self, job: str, body: dict) -> None:
        self.docs[job] = body


class BoomHeartbeat:
    def write_heartbeat(self, job: str, body: dict) -> None:
        raise RuntimeError("firestore unavailable")


@dataclass
class _Outcome:
    status: str


def _job_run_records(caplog):
    return [r for r in caplog.records if r.getMessage() == "job_run"]


# --- RunReport / counting ---------------------------------------------------


def test_run_report_document_shape_and_duration() -> None:
    report = observability.RunReport(
        "compute_risk", observability.STATUS_OK, STARTED, FINISHED,
        counts={"written": 3, "skipped_no_data": 1},
    )
    doc = report.to_document()
    assert doc["job"] == "compute_risk"
    assert doc["status"] == "ok" and doc["ok"] is True
    assert doc["durationMs"] == 1500
    assert doc["total"] == 4
    assert doc["counts"] == {"written": 3, "skipped_no_data": 1}
    assert doc["error"] is None
    # Timestamps are real datetimes (Firestore serialises them natively).
    assert doc["startedAt"] == STARTED and doc["finishedAt"] == FINISHED


def test_count_by_status_tallies() -> None:
    counts = observability.count_by_status(
        [_Outcome("written"), _Outcome("written"), _Outcome("error")]
    )
    assert counts == {"written": 2, "error": 1}


def test_heartbeat_body_carries_no_secrets() -> None:
    report = observability.RunReport(
        "dispatch_alerts", observability.STATUS_OK, STARTED, FINISHED,
        counts={"sent": 1},
    )
    keys = set(report.to_document())
    assert keys == {
        "job", "status", "ok", "startedAt", "finishedAt",
        "durationMs", "total", "counts", "error",
    }  # no token / credential / payload fields


# --- emit: heartbeat + structured signal ------------------------------------


def test_emit_ok_writes_heartbeat_and_info_signal(caplog) -> None:
    hb = FakeHeartbeat()
    report = observability.RunReport(
        "compute_risk", observability.STATUS_OK, STARTED, FINISHED,
        counts={"written": 3},
    )
    with caplog.at_level(logging.INFO):
        observability.emit(report, sink=hb, logger=logging.getLogger("t.ok"))

    assert hb.docs["compute_risk"]["status"] == "ok"
    (rec,) = _job_run_records(caplog)
    assert rec.levelno == logging.INFO
    assert rec.status == "ok" and rec.alert is False


def test_emit_failed_raises_error_signal_with_alert(caplog) -> None:
    hb = FakeHeartbeat()
    report = observability.failed_report(
        "compute_risk", STARTED, FINISHED, "RuntimeError: boom"
    )
    with caplog.at_level(logging.INFO):
        observability.emit(report, sink=hb, logger=logging.getLogger("t.fail"))

    assert hb.docs["compute_risk"]["status"] == "failed"
    assert hb.docs["compute_risk"]["error"] == "RuntimeError: boom"
    (rec,) = _job_run_records(caplog)
    assert rec.levelno == logging.ERROR
    assert rec.alert is True


def test_emit_survives_a_heartbeat_sink_failure(caplog) -> None:
    """Telemetry must not crash the job: a sink error is logged, the run log still
    fires (the log-based alert remains as a fallback)."""
    report = observability.RunReport(
        "compute_risk", observability.STATUS_OK, STARTED, FINISHED,
        counts={"written": 3},
    )
    with caplog.at_level(logging.INFO):
        observability.emit(
            report, sink=BoomHeartbeat(), logger=logging.getLogger("t.boom")
        )

    messages = {r.getMessage() for r in caplog.records}
    assert "heartbeat_write_failed" in messages
    assert "job_run" in messages  # still emitted despite the sink failure


# --- compute_risk.run_and_report --------------------------------------------

_BUNDLE = load_bundle(resolve_artifact_path())
_CITIES = [{"name": "Lahore"}, {"name": "Karachi"}, {"name": "Islamabad"}]
_GEN_AT = datetime(2026, 6, 29, tzinfo=timezone.utc)


def _fake_base(city: str, n_weeks: int = 10, start_week: int = 10):
    import pandas as pd

    rows = [
        {
            "city": city, "iso_year": 2026, "week_of_year": start_week + i,
            "days_in_week": 7, "temperature": 20.0 + i, "humidity": 55.0 + (i % 5),
            "precipitation": 3.0 + (i % 4), "pm2_5": 30.0 + i, "pm10": 50.0 + i,
            "us_aqi": 90.0 + 2 * i, "aqi_available": True,
        }
        for i in range(n_weeks)
    ]
    return pd.DataFrame(rows)


class _FakeProvider:
    def __init__(self, bases, errors=frozenset()):
        self._bases, self._errors = bases, errors

    def recent_weekly_base(self, city):
        name = city["name"]
        if name in self._errors:
            raise RuntimeError("simulated upstream fetch failure")
        return self._bases.get(name)


class _FakeRiskRepo:
    def __init__(self):
        self.docs: dict[str, dict] = {}

    def upsert(self, doc_id, body):
        self.docs[doc_id] = body


def test_compute_risk_success_writes_ok_heartbeat() -> None:
    hb = FakeHeartbeat()
    provider = _FakeProvider({c["name"]: _fake_base(c["name"]) for c in _CITIES})
    report, outcomes = compute_risk.run_and_report(
        provider, _FakeRiskRepo(), heartbeat=hb,
        bundle=_BUNDLE, cities=_CITIES, generated_at=_GEN_AT,
    )

    assert report.status == "ok"
    assert report.counts["written"] == len(_CITIES)
    assert hb.docs["compute_risk"]["status"] == "ok"
    assert hb.docs["compute_risk"]["counts"]["written"] == len(_CITIES)


def test_compute_risk_zero_output_raises_failed_signal() -> None:
    """The realistic pipeline failure: every city's fetch fails, so NOTHING is
    written. The run is graded ``failed`` and the heartbeat records it — an
    operator (and Cloud Logging) can now detect the silent/empty run (audit H1)."""
    hb = FakeHeartbeat()
    provider = _FakeProvider(
        {c["name"]: _fake_base(c["name"]) for c in _CITIES},
        errors=frozenset(c["name"] for c in _CITIES),
    )
    report, outcomes = compute_risk.run_and_report(
        provider, _FakeRiskRepo(), heartbeat=hb,
        bundle=_BUNDLE, cities=_CITIES, generated_at=_GEN_AT,
    )

    assert report.status == "failed"
    assert report.counts.get("written", 0) == 0
    assert hb.docs["compute_risk"]["status"] == "failed"
    assert hb.docs["compute_risk"]["ok"] is False


def test_compute_risk_partial_output_is_degraded() -> None:
    bases = {c["name"]: _fake_base(c["name"]) for c in _CITIES}
    bases["Karachi"] = None  # one city has no recent data
    hb = FakeHeartbeat()
    report, _ = compute_risk.run_and_report(
        _FakeProvider(bases), _FakeRiskRepo(), heartbeat=hb,
        bundle=_BUNDLE, cities=_CITIES, generated_at=_GEN_AT,
    )

    assert report.status == "degraded"
    assert hb.docs["compute_risk"]["status"] == "degraded"


def test_compute_risk_crash_emits_failed_then_reraises() -> None:
    """An unexpected crash (a city dict missing ``name`` escapes ``run``) still
    emits a ``failed`` heartbeat before propagating for a non-zero exit."""
    import pytest

    hb = FakeHeartbeat()
    with pytest.raises(KeyError):
        compute_risk.run_and_report(
            _FakeProvider({}), _FakeRiskRepo(), heartbeat=hb,
            bundle=_BUNDLE, cities=[{"no_name": True}], generated_at=_GEN_AT,
        )
    assert hb.docs["compute_risk"]["status"] == "failed"
    assert hb.docs["compute_risk"]["error"].startswith("KeyError")


# --- dispatch_alerts / weekly_report: zero sends is healthy -----------------

_DISPATCH_CITIES = [{"name": "Lahore"}]
_NOW = datetime(2026, 6, 30, 12, 0, tzinfo=timezone.utc)
_PREFS_ALL = {
    "highRiskAlerts": True, "mediumRiskAlerts": True, "lowRiskUpdates": False,
    "conditions": {"respiratory": True, "cardiovascular": True},
}


def _city_risk(level: str) -> CityRisk:
    return CityRisk(
        city="Lahore", risk_level=level, disease="Smog",
        generated_at="2026-06-30T00:00:00.000Z", model_version="rf-1.0.0",
        doc_id=f"Lahore_2026-06-30_{level}",
    )


def _user(token="tok-1") -> TargetUser:
    return TargetUser(
        uid="u1", city="Lahore", conditions=("Asthma",),  # frozen map key
        fcm_token=token, preferences=_PREFS_ALL,
    )


class _FakeHistory:
    def __init__(self, mapping):
        self._m = mapping

    def latest_two(self, city):
        return self._m.get(city, (None, None))


class _FakeDirectory:
    def __init__(self, mapping):
        self._m = mapping

    def users_in_city(self, city):
        return self._m.get(city, [])


class _FakeSender:
    def __init__(self, result=None):
        self.result = result or SendResult("sent", message_id="m1")

    def send(self, *, token, title, body, data):
        return self.result


class _FakeDispatchRepo:
    def __init__(self):
        self.logs: dict[str, dict] = {}
        self.alerts: dict = {}
        self.pruned: list = []

    def write_dispatch_log(self, log_id, body):
        self.logs[log_id] = body

    def write_user_alert(self, uid, alert_id, body):
        self.alerts[(uid, alert_id)] = body

    def has_dispatch(self, log_id):
        return log_id in self.logs

    def recently_sent(self, uid, category, since):
        return False

    def prune_token(self, uid):
        self.pruned.append(uid)

    def claim_dispatch(self, log_id, now):
        if log_id in self.logs:
            return False
        self.logs[log_id] = {"status": "claimed", "claimedAt": now}
        return True


def test_dispatch_zero_sends_is_ok_and_writes_heartbeat() -> None:
    """No risk transition (steady risk) → zero sends. That is NORMAL, so the run is
    ``ok`` and still writes a heartbeat (proving the job ran)."""
    hb = FakeHeartbeat()
    history = _FakeHistory({"Lahore": (_city_risk("Low"), _city_risk("Low"))})
    report, outcomes = dispatch_alerts.run_and_report(
        history=history, directory=_FakeDirectory({"Lahore": [_user()]}),
        sender=_FakeSender(), repository=_FakeDispatchRepo(), heartbeat=hb,
        cities=_DISPATCH_CITIES, now=_NOW,
    )

    assert outcomes == []
    assert report.status == "ok"
    assert hb.docs["dispatch_alerts"]["status"] == "ok"
    assert hb.docs["dispatch_alerts"]["total"] == 0


def test_dispatch_send_failure_is_degraded() -> None:
    hb = FakeHeartbeat()
    history = _FakeHistory({"Lahore": (_city_risk("High"), _city_risk("Low"))})
    report, outcomes = dispatch_alerts.run_and_report(
        history=history, directory=_FakeDirectory({"Lahore": [_user()]}),
        sender=_FakeSender(SendResult("failed")), repository=_FakeDispatchRepo(),
        heartbeat=hb, cities=_DISPATCH_CITIES, now=_NOW,
    )

    assert any(o.status == "failed" for o in outcomes)
    assert report.status == "degraded"
    assert hb.docs["dispatch_alerts"]["status"] == "degraded"


def test_weekly_report_writes_heartbeat() -> None:
    hb = FakeHeartbeat()
    history = _FakeHistory({"Lahore": (_city_risk("Medium"), _city_risk("Medium"))})
    report, outcomes = weekly_report.run_and_report(
        history=history, directory=_FakeDirectory({"Lahore": [_user()]}),
        sender=_FakeSender(), repository=_FakeDispatchRepo(), heartbeat=hb,
        cities=_DISPATCH_CITIES, now=_NOW,
    )

    assert report.status == "ok"
    assert hb.docs["weekly_report"]["status"] == "ok"
    assert hb.docs["weekly_report"]["counts"].get("sent") == 1
