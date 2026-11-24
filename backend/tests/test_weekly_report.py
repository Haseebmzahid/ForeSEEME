"""Tests for the Weekly Health Report dispatch hook (Sprint 5, Prompt 8).

Uses in-memory fakes for every seam so the hook runs offline. Asserts:
- one weekly report per consenting user, with a CITED recommendation + the
  weekly deep link, written to the inbox;
- idempotency per (user, ISO week): a second run in the same week sends nothing;
- preference respect: a user with all severities disabled receives nothing;
- token hygiene: a dead token is pruned and no inbox doc is written.
"""

from __future__ import annotations

from datetime import datetime, timezone

from app.notification_registrations import Registration
from app.jobs import weekly_report as wr
from app.jobs.alerting.messaging import SendResult
from app.jobs.alerting.targeting import CityRisk, TargetUser

NOW = datetime(2026, 7, 2, tzinfo=timezone.utc)  # ISO week 27 of 2026
CITIES = [{"name": "Lahore"}, {"name": "Karachi"}]

ENABLED_PREFS = {
    "highRiskAlerts": True,
    "mediumRiskAlerts": True,
    "lowRiskUpdates": False,
    "conditions": {"respiratory": True, "cardiovascular": False},
}
OPTED_OUT_PREFS = {
    "highRiskAlerts": False,
    "mediumRiskAlerts": False,
    "lowRiskUpdates": False,
    "conditions": {"respiratory": True},
}


def _risk(city: str) -> CityRisk:
    return CityRisk(
        city=city,
        risk_level="Medium",
        disease="Smog",
        generated_at="2026-07-01T00:00:00Z",
        model_version="rf-1.0.0",
        doc_id=f"{city}_2026-07-01",
    )


class FakeHistory:
    def __init__(self, cities): self._cities = set(cities)
    def latest_two(self, city):
        return (_risk(city), _risk(city)) if city in self._cities else (None, None)


class FakeDirectory:
    def __init__(self, by_city): self._by_city = by_city
    def users_in_city(self, city): return self._by_city.get(city, [])


class FakeSender:
    def __init__(self, status="sent"): self.status = status; self.sent = []
    def send(self, *, token, title, body, data, still_current=None):
        self.sent.append({"token": token, "title": title, "body": body, "data": data})
        return SendResult(status=self.status, message_id="m1")


class FakeRepository:
    def __init__(self):
        self.logs = {}
        self.alerts = {}
        self.pruned = []
    def write_dispatch_log(self, log_id, body): self.logs[log_id] = body
    def write_user_alert(self, uid, alert_id, body):
        self.alerts.setdefault(uid, {})[alert_id] = body
    def has_dispatch(self, log_id): return log_id in self.logs
    def claim_dispatch(self, log_id, now):
        if log_id in self.logs:
            return False
        self.logs[log_id] = {"status": "claimed", "claimedAt": now}
        return True

    def recently_sent(self, uid, category, since): return False
    def is_current_registration(self, registration):
        return registration.uid not in self.pruned

    def prune_token(self, registration): self.pruned.append(registration.uid)


def _user(uid, token="tok", prefs=None):
    return TargetUser(uid=uid, city="Lahore",
                      conditions=("Asthma",), registrations=(Registration(uid, token, 1, "test"),) if token else (),
                      preferences=prefs or ENABLED_PREFS)


# --- Composition ------------------------------------------------------------


def test_compose_weekly_is_cited_and_non_diagnostic() -> None:
    from app.jobs.alerting import recommendation_lookup

    rec = recommendation_lookup.lookup("respiratory", "Air quality")
    alert = wr.compose_weekly(_risk("Lahore"), rec, NOW)
    title, body = alert["title"], alert["body"]

    assert "weekly health report" in title.lower()
    assert "Lahore" in title
    assert rec.text in body                         # cited advisory verbatim
    assert alert["category"] == "weekly_report"
    assert alert["deepLink"] == "/weekly-report"
    assert alert["recommendation"]["source"] == rec.source
    assert alert["recommendation"]["sourceUrl"] == rec.source_url
    # Non-diagnostic: about the environment, never a personal diagnosis.
    from app.jobs.alerting.messaging import PUSH_DISCLAIMER
    assert body.startswith(PUSH_DISCLAIMER)
    assert body.count(PUSH_DISCLAIMER) == 1
    assert "diagnos" not in body.removeprefix(PUSH_DISCLAIMER).lower()
    assert "environmental" in body.lower()


# --- One report per consenting user, cited, to the inbox --------------------


def test_sends_one_weekly_report_per_consenting_user() -> None:
    sender = FakeSender()
    repo = FakeRepository()
    directory = FakeDirectory({
        "Lahore": [_user("u1"), _user("u2")],
        "Karachi": [_user("u3", prefs=ENABLED_PREFS)],
    })
    outcomes = wr.run(history=FakeHistory({"Lahore", "Karachi"}), directory=directory,
                      sender=sender, repository=repo, cities=CITIES, now=NOW)

    sent = [o for o in outcomes if o.status == "sent"]
    assert len(sent) == 3
    assert len(sender.sent) == 3
    # Each recipient got exactly one inbox doc with the weekly deep link.
    for uid in ("u1", "u2", "u3"):
        (alert,) = repo.alerts[uid].values()
        assert alert["deepLink"] == "/weekly-report"
        assert alert["recommendation"]["source"]  # cited


# --- Idempotency per (user, week): re-run sends nothing ---------------------


def test_weekly_fans_out_with_neutral_copy_and_one_private_inbox():
    from dataclasses import replace
    from app.jobs.alerting.messaging import PUSH_BODY, PUSH_TITLE

    user = replace(_user("u1"), registrations=(
        Registration("u1", "device-one", 1, "g1"),
        Registration("u1", "device-two", 1, "g2"),
    ))
    repo = FakeRepository()
    sender = FakeSender()
    outcomes = wr.run(
        history=FakeHistory({"Lahore": _risk("Lahore")}),
        directory=FakeDirectory({"Lahore": [user]}), sender=sender,
        repository=repo, cities=[{"name": "Lahore"}], now=NOW,
    )
    assert len(outcomes) == len(repo.logs) == len(repo.alerts[user.uid]) == 1
    assert len(sender.sent) == 2
    alert = next(iter(repo.alerts[user.uid].values()))
    for send in sender.sent:
        assert send["title"] == PUSH_TITLE
        assert send["body"] == PUSH_BODY
        assert send["data"] == {"recipientUid": user.uid, "alertId": alert["pushId"]}
    assert "Lahore" in alert["title"]
    assert "environmental" in alert["body"]


def test_rerun_same_week_sends_nothing() -> None:
    directory = FakeDirectory({"Lahore": [_user("u1")]})
    repo = FakeRepository()

    first = FakeSender()
    wr.run(history=FakeHistory({"Lahore"}), directory=directory, sender=first,
           repository=repo, cities=[{"name": "Lahore"}], now=NOW)
    assert len(first.sent) == 1

    second = FakeSender()
    outcomes = wr.run(history=FakeHistory({"Lahore"}), directory=directory,
                      sender=second, repository=repo, cities=[{"name": "Lahore"}],
                      now=NOW)
    assert len(second.sent) == 0                       # the decisive spam guard
    assert all(o.status == "skipped_idempotent" for o in outcomes)
    assert len(repo.alerts["u1"]) == 1                 # no duplicate inbox doc


def test_next_week_sends_again() -> None:
    directory = FakeDirectory({"Lahore": [_user("u1")]})
    repo = FakeRepository()
    wr.run(history=FakeHistory({"Lahore"}), directory=directory, sender=FakeSender(),
           repository=repo, cities=[{"name": "Lahore"}], now=NOW)

    next_week = datetime(2026, 7, 9, tzinfo=timezone.utc)  # ISO week 28
    sender = FakeSender()
    wr.run(history=FakeHistory({"Lahore"}), directory=directory, sender=sender,
           repository=repo, cities=[{"name": "Lahore"}], now=next_week)
    assert len(sender.sent) == 1
    assert len(repo.alerts["u1"]) == 2                 # one per distinct week


# --- Preference respect + token hygiene -------------------------------------


def test_opted_out_user_receives_nothing() -> None:
    directory = FakeDirectory({"Lahore": [_user("out", prefs=OPTED_OUT_PREFS)]})
    sender = FakeSender()
    repo = FakeRepository()
    outcomes = wr.run(history=FakeHistory({"Lahore"}), directory=directory,
                      sender=sender, repository=repo, cities=[{"name": "Lahore"}],
                      now=NOW)
    assert len(sender.sent) == 0
    assert outcomes[0].status == "skipped_opted_out"
    assert "out" not in repo.alerts


def test_missing_token_is_skipped() -> None:
    directory = FakeDirectory({"Lahore": [_user("u1", token=None)]})
    sender = FakeSender()
    repo = FakeRepository()
    outcomes = wr.run(history=FakeHistory({"Lahore"}), directory=directory,
                      sender=sender, repository=repo, cities=[{"name": "Lahore"}],
                      now=NOW)
    assert len(sender.sent) == 0
    assert outcomes[0].status == "skipped_no_token"


def test_dead_token_is_pruned_and_no_inbox_written() -> None:
    directory = FakeDirectory({"Lahore": [_user("u1")]})
    sender = FakeSender(status="token_invalid")
    repo = FakeRepository()
    wr.run(history=FakeHistory({"Lahore"}), directory=directory, sender=sender,
           repository=repo, cities=[{"name": "Lahore"}], now=NOW)
    assert repo.pruned == ["u1"]
    assert "u1" not in repo.alerts       # no inbox doc on a failed send


def test_weekly_enabled_gate() -> None:
    assert wr.weekly_enabled(ENABLED_PREFS) is True
    assert wr.weekly_enabled(OPTED_OUT_PREFS) is False
    assert wr.weekly_enabled({}) is False
