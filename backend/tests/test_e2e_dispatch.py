"""End-to-end dispatch pipeline + engagement-safeguard proof (Sprint 4, Prompt 9).

Exercises the whole engine over *multiple cities and users* and then **re-runs it
repeatedly** to prove the engagement safeguards hold end-to-end:

* only vulnerable, consenting users on a transition are alerted — no one else;
* every delivered alert produces exactly one audited send and one inbox doc whose
  shape matches the frozen contract the Flutter inbox consumes;
* repeated runs and a second within-24h event produce **zero** extra sends
  (no spam, no duplicates);
* an invalid token is pruned once.

Self-contained fakes (no Firebase); the job runs fully offline.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone

from app.notification_registrations import Registration
from app.jobs import dispatch_alerts as job
from app.jobs.alerting.messaging import SendResult
from app.jobs.alerting.targeting import CityRisk, TargetUser

NOW = datetime(2026, 6, 30, 12, 0, tzinfo=timezone.utc)

_PREFS_ALL = {
    "highRiskAlerts": True,
    "mediumRiskAlerts": True,
    "lowRiskUpdates": False,
    "conditions": {"respiratory": True, "cardiovascular": True},
}


def _city(name: str, level: str, disease: str, date: str = "2026-06-30") -> CityRisk:
    return CityRisk(
        city=name,
        risk_level=level,
        disease=disease,
        generated_at=f"{date}T00:00:00.000Z",
        model_version="rf-1.0.0",
        doc_id=f"{name}_{date}",
    )


def _user(uid, city, conditions, prefs=None, token="tok") -> TargetUser:
    return TargetUser(
        uid=uid,
        city=city,
        conditions=tuple(conditions),
        registrations=(Registration(uid, token, 1, "test"),) if token else (),
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
    result: SendResult = field(
        default_factory=lambda: SendResult("sent", message_id="m1")
    )
    sends: list = field(default_factory=list)

    def send(self, *, token, title, body, data, still_current=None):
        self.sends.append({"token": token, "data": data})
        return self.result


class FakeRepository:
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

    def is_current_registration(self, registration):
        return registration.uid not in self.pruned

    def prune_token(self, registration):
        self.pruned.append(registration.uid)

    def claim_dispatch(self, log_id, now):
        if log_id in self.logs:
            return False
        self.logs[log_id] = {"status": "claimed", "claimedAt": now}
        return True


# Cities: Lahore transitions up (smog), Islamabad transitions up (heat),
# Karachi stays steady (no transition → must never alert).
CITIES = [{"name": "Lahore"}, {"name": "Karachi"}, {"name": "Islamabad"}]


def _history():
    return FakeHistory(
        {
            "Lahore": (_city("Lahore", "High", "Smog"), _city("Lahore", "Medium", "Smog", "2026-06-23")),
            "Karachi": (_city("Karachi", "High", "Smog"), _city("Karachi", "High", "Smog", "2026-06-23")),
            "Islamabad": (
                _city("Islamabad", "Medium", "Heat-Related Illness"),
                _city("Islamabad", "Low", "Heat-Related Illness", "2026-06-23"),
            ),
        }
    )


def _directory():
    resp_disabled = dict(
        _PREFS_ALL, conditions={"respiratory": False, "cardiovascular": True}
    )
    return FakeDirectory(
        {
            "Lahore": [
                _user("asthma_ok", "Lahore", ["Asthma"]),            # → sent
                _user("healthy", "Lahore", ["None"]),                 # no condition
                _user("resp_off", "Lahore", ["Asthma"], resp_disabled),  # consent off
                _user("no_token", "Lahore", ["Asthma"], token=None),  # undeliverable
            ],
            "Karachi": [_user("steady", "Karachi", ["Asthma"])],      # no transition
            "Islamabad": [_user("htn_ok", "Islamabad", ["Hypertension"])],  # → sent
        }
    )


def _run(history, directory, sender, repo, now=NOW):
    return job.run(
        history=history,
        directory=directory,
        sender=sender,
        repository=repo,
        cities=CITIES,
        now=now,
    )


def test_pipeline_targets_only_vulnerable_consenting_users() -> None:
    sender, repo = FakeSender(), FakeRepository()
    outcomes = _run(_history(), _directory(), sender, repo)

    sent = {o.uid for o in outcomes if o.status == "sent"}
    assert sent == {"asthma_ok", "htn_ok"}  # and no one else
    assert len(sender.sends) == 2
    assert len(repo.alerts) == 2

    # Inbox doc shape matches the frozen contract the Flutter inbox reads.
    resp = repo.alerts[("asthma_ok", "asthma_ok__Lahore_2026-06-30__respiratory")]
    assert resp["read"] is False
    assert resp["recommendation"]["id"] == "rec-resp-air"
    assert resp["recommendation"]["sourceUrl"].startswith("https://")
    assert resp["deepLink"] == "/resources"

    cardio = repo.alerts[("htn_ok", "htn_ok__Islamabad_2026-06-30__cardiovascular")]
    assert cardio["recommendation"]["id"] == "rec-cardio-heat"
    assert cardio["deepLink"] == "/nearby-hospitals"


def test_repeated_runs_produce_no_spam_and_no_duplicates() -> None:
    history, directory = _history(), _directory()
    sender, repo = FakeSender(), FakeRepository()

    for _ in range(5):  # scheduler fires the same estimates five times
        outcomes = _run(history, directory, sender, repo)

    # Still exactly two deliveries and two inbox docs after five runs.
    assert len(sender.sends) == 2
    assert len(repo.alerts) == 2
    # Every re-run is short-circuited by the per-estimate idempotency key.
    assert all(o.status == "skipped_idempotent" for o in outcomes if o.uid in {"asthma_ok", "htn_ok"})


def test_second_event_within_24h_is_throttled_end_to_end() -> None:
    directory = FakeDirectory({"Lahore": [_user("asthma_ok", "Lahore", ["Asthma"])]})
    sender, repo = FakeSender(), FakeRepository()

    # First qualifying Lahore delivery.
    job.run(
        history=FakeHistory(
            {"Lahore": (_city("Lahore", "High", "Smog"), _city("Lahore", "Medium", "Smog", "2026-06-23"))}
        ),
        directory=directory,
        sender=sender,
        repository=repo,
        cities=[{"name": "Lahore"}],
        now=NOW,
    )

    # A NEW Lahore estimate ~2h later (fresh idempotency key, still within 24h).
    later = FakeHistory(
        {
            "Lahore": (
                _city("Lahore", "High", "Smog", "2026-07-01"),
                _city("Lahore", "Medium", "Smog", "2026-06-30"),
            )
        }
    )
    outcomes = job.run(
        history=later,
        directory=directory,
        sender=sender,
        repository=repo,
        cities=[{"name": "Lahore"}],
        now=NOW + timedelta(hours=2),
    )

    throttled = [o for o in outcomes if o.uid == "asthma_ok"]
    assert throttled and throttled[0].status == "skipped_throttled"
    assert len(sender.sends) == 1  # the within-window event sent nothing new


def test_invalid_token_pruned_once_across_reruns() -> None:
    history = FakeHistory(
        {"Lahore": (_city("Lahore", "High", "Smog"), _city("Lahore", "Medium", "Smog", "2026-06-23"))}
    )
    directory = FakeDirectory({"Lahore": [_user("asthma_ok", "Lahore", ["Asthma"])]})
    sender = FakeSender(result=SendResult("token_invalid", error="unregistered"))
    repo = FakeRepository()

    for _ in range(3):
        job.run(
            history=history,
            directory=directory,
            sender=sender,
            repository=repo,
            cities=[{"name": "Lahore"}],
            now=NOW,
        )

    # Pruned exactly once (first run); re-runs are idempotent, no re-prune, no inbox.
    assert repo.pruned == ["asthma_ok"]
    assert repo.alerts == {}
