"""Dispatch engine tests (Sprint 4, Prompt 2) with fakes for every seam.

Asserts: an asthma user in a city transitioning into High smog risk gets ONE
personalized, cited alert; a non-matching / disabled user gets none; steady risk
sends nothing; every send attempt is audited; a successful send writes the inbox
doc; a token-invalid send is audited without an inbox doc.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone

from app.jobs import dispatch_alerts as job
from app.jobs.alerting.messaging import SendResult
from app.jobs.alerting.targeting import CityRisk, TargetUser

NOW = datetime(2026, 6, 30, 12, 0, tzinfo=timezone.utc)
CITIES = [{"name": "Lahore"}]

_PREFS_ALL = {
    "highRiskAlerts": True,
    "mediumRiskAlerts": True,
    "lowRiskUpdates": False,
    "conditions": {"respiratory": True, "cardiovascular": True},
}


def _city(level: str, disease: str = "Smog") -> CityRisk:
    return CityRisk(
        city="Lahore",
        risk_level=level,
        disease=disease,
        generated_at="2026-06-30T00:00:00.000Z",
        model_version="rf-1.0.0",
        doc_id="Lahore_2026-06-30",
    )


def _user(uid: str, conditions, prefs=None, token="tok-1") -> TargetUser:
    return TargetUser(
        uid=uid,
        city="Lahore",
        conditions=tuple(conditions),
        fcm_token=token,
        preferences=prefs if prefs is not None else _PREFS_ALL,
    )


class FakeHistory:
    def __init__(self, mapping):
        self._m = mapping

    def latest_two(self, city):
        return self._m.get(city, (None, None))


class FakeDirectory:
    def __init__(self, mapping):
        self._m = mapping

    def users_in_city(self, city):
        return self._m.get(city, [])


@dataclass
class FakeSender:
    result: SendResult = field(default_factory=lambda: SendResult("sent", message_id="m1"))
    sends: list = field(default_factory=list)

    def send(self, *, token, title, body, data):
        self.sends.append({"token": token, "title": title, "body": body, "data": data})
        return self.result


class FakeRepository:
    """In-memory ledger that reads its own logs (realistic throttle/idempotency)."""

    def __init__(self):
        self.logs: dict[str, dict] = {}
        self.alerts: dict[tuple[str, str], dict] = {}
        self.pruned: list[str] = []

    def write_dispatch_log(self, log_id, body):
        self.logs[log_id] = body

    def write_user_alert(self, uid, alert_id, body):
        self.alerts[(uid, alert_id)] = body

    def has_dispatch(self, log_id):
        return log_id in self.logs

    def recently_sent(self, uid, category, since):
        return any(
            b["uid"] == uid
            and b["category"] == category
            and b["status"] == "sent"
            and b["createdAt"] >= since
            for b in self.logs.values()
        )

    def prune_token(self, uid):
        self.pruned.append(uid)


def _run(history, directory, sender=None, repository=None):
    sender = sender or FakeSender()
    repository = repository or FakeRepository()
    outcomes = job.run(
        history=history,
        directory=directory,
        sender=sender,
        repository=repository,
        cities=CITIES,
        now=NOW,
    )
    return outcomes, sender, repository


def test_asthma_user_gets_one_cited_alert() -> None:
    history = FakeHistory({"Lahore": (_city("High"), _city("Medium"))})
    directory = FakeDirectory(
        {"Lahore": [_user("u1", ["Asthma"]), _user("u2", ["None"])]}
    )

    outcomes, sender, repo = _run(history, directory)

    # exactly one attempt, for the asthma user
    assert len(outcomes) == 1
    assert outcomes[0].uid == "u1"
    assert outcomes[0].status == "sent"
    assert len(sender.sends) == 1

    log_id = "u1__Lahore_2026-06-30__respiratory"
    assert outcomes[0].log_id == log_id
    assert log_id in repo.logs

    log = repo.logs[log_id]
    assert log["status"] == "sent"
    assert log["category"] == "respiratory"
    assert log["previousRiskLevel"] == "Medium"
    assert log["riskLevel"] == "High"
    assert log["recommendationId"] == "rec-resp-air"
    assert log["fcmMessageId"] == "m1"
    assert log["throttleWindowEnd"] > log["createdAt"]

    # inbox doc written on success, with the cited recommendation
    alert = repo.alerts[("u1", log_id)]
    assert alert["read"] is False
    assert alert["recommendation"]["id"] == "rec-resp-air"
    assert alert["recommendation"]["sourceUrl"].startswith("https://")
    assert alert["deepLink"] == "/resources"


def test_disabled_category_user_receives_nothing() -> None:
    prefs = dict(_PREFS_ALL, conditions={"respiratory": False, "cardiovascular": True})
    history = FakeHistory({"Lahore": (_city("High"), _city("Medium"))})
    directory = FakeDirectory({"Lahore": [_user("u1", ["Asthma"], prefs)]})

    outcomes, sender, repo = _run(history, directory)

    assert outcomes == []
    assert sender.sends == []
    assert repo.logs == {}


def test_steady_risk_sends_nothing() -> None:
    history = FakeHistory({"Lahore": (_city("High"), _city("High"))})
    directory = FakeDirectory({"Lahore": [_user("u1", ["Asthma"])]})

    outcomes, sender, _ = _run(history, directory)

    assert outcomes == []
    assert sender.sends == []


def test_token_invalid_is_audited_without_inbox() -> None:
    history = FakeHistory({"Lahore": (_city("High"), _city("Medium"))})
    directory = FakeDirectory({"Lahore": [_user("u1", ["Asthma"])]})
    sender = FakeSender(result=SendResult("token_invalid", error="unregistered"))

    outcomes, sender, repo = _run(history, directory, sender=sender)

    assert outcomes[0].status == "token_invalid"
    log_id = "u1__Lahore_2026-06-30__respiratory"
    assert repo.logs[log_id]["status"] == "token_invalid"
    assert ("u1", log_id) not in repo.alerts  # no inbox doc on failure
    assert repo.pruned == ["u1"]  # token hygiene: dead token removed


def test_insufficient_history_skips_city() -> None:
    history = FakeHistory({"Lahore": (_city("High"), None)})
    directory = FakeDirectory({"Lahore": [_user("u1", ["Asthma"])]})

    outcomes, sender, _ = _run(history, directory)

    assert outcomes == []
    assert sender.sends == []


def test_dispatch_key_is_derived_from_the_estimate() -> None:
    assert (
        job.dispatch_key("u1", "Lahore_2026-06-30", "respiratory")
        == "u1__Lahore_2026-06-30__respiratory"
    )


def test_rerun_same_estimate_sends_nothing_new() -> None:
    history = FakeHistory({"Lahore": (_city("High"), _city("Medium"))})
    directory = FakeDirectory({"Lahore": [_user("u1", ["Asthma"])]})
    sender = FakeSender()
    repo = FakeRepository()

    def _go(now):
        return job.run(
            history=history,
            directory=directory,
            sender=sender,
            repository=repo,
            cities=CITIES,
            now=now,
        )

    first = _go(NOW)
    second = _go(NOW)  # identical estimate

    assert first[0].status == "sent"
    assert second[0].status == "skipped_idempotent"
    assert len(sender.sends) == 1  # zero duplicate sends on re-run
    assert len(repo.alerts) == 1  # one inbox doc total


def test_second_event_within_24h_is_throttled() -> None:
    directory = FakeDirectory({"Lahore": [_user("u1", ["Asthma"])]})
    sender = FakeSender()
    repo = FakeRepository()

    # First qualifying event.
    job.run(
        history=FakeHistory({"Lahore": (_city("High"), _city("Medium"))}),
        directory=directory,
        sender=sender,
        repository=repo,
        cities=CITIES,
        now=NOW,
    )

    # A second, DIFFERENT estimate ~1h later (new key, but within 24h).
    later = CityRisk(
        city="Lahore",
        risk_level="High",
        disease="Smog",
        generated_at="2026-07-01T00:00:00.000Z",
        model_version="rf-1.0.0",
        doc_id="Lahore_2026-07-01",
    )
    outcomes = job.run(
        history=FakeHistory({"Lahore": (later, _city("Medium"))}),
        directory=directory,
        sender=sender,
        repository=repo,
        cities=CITIES,
        now=NOW + timedelta(hours=1),
    )

    assert outcomes[0].status == "skipped_throttled"
    assert len(sender.sends) == 1  # second event suppressed (no spam)
    assert repo.logs["u1__Lahore_2026-07-01__respiratory"]["status"] == "skipped_throttled"
