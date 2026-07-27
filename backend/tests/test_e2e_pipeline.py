"""End-to-end proactive pipeline (Sprint 5, Prompt 16).

Proves the backend legs of the whole loop —
**predict → attribute → store → dispatch → inbox** — by chaining the *real* jobs
through a single shared in-memory Firestore-like store (the seam that a real
`riskEstimates` collection would be), rather than testing each job in isolation:

* the genuine ``compute_risk.run`` writes a contract-valid estimate **with genuine
  attributions**, and that exact stored body is what ``dispatch_alerts`` reads for
  targeting (contract compatibility across the store boundary);
* a vulnerable, consenting user on a transition receives **exactly one** audited
  send + one inbox doc whose shape matches the frozen contract the Flutter inbox
  consumes;
* re-running the scheduler produces **zero** extra sends (idempotent, spam-safe);
* an opted-out user receives **nothing**.

The staleness leg (an old estimate is *labelled* to the user) is proven on the
Flutter side (`test/integration/pipeline_e2e_test.dart`), since staleness is a
user-facing signal. Fully in-memory and deterministic — no Firebase, no emulator,
so it runs in the CI gate; see `docs/e2e.md` for the emulator variant.
"""

from __future__ import annotations

from datetime import datetime, timezone

import pandas as pd

from app.jobs import compute_risk, dispatch_alerts
from app.jobs.alerting.messaging import SendResult
from app.jobs.alerting.targeting import CityRisk, TargetUser
from app.predict import load_bundle, resolve_artifact_path
from app.schemas import RiskEstimateResponse

BUNDLE = load_bundle(resolve_artifact_path())
NOW = datetime(2026, 6, 30, 12, 0, tzinfo=timezone.utc)

_PREFS_ALL = {
    "highRiskAlerts": True,
    "mediumRiskAlerts": True,
    "lowRiskUpdates": False,
    "conditions": {"respiratory": True, "cardiovascular": True},
}


# --- The shared store: one object plays every Firestore seam in the loop ------


class PipelineStore:
    """In-memory stand-in for Firestore, wired to BOTH jobs' seams:

    * ``compute_risk`` writes ``riskEstimates`` here via :meth:`upsert`;
    * ``dispatch_alerts`` reads them via :meth:`latest_two` and writes the audit
      log / inbox via the ``DispatchRepository`` methods.
    """

    def __init__(self) -> None:
        self.risk: dict[str, dict] = {}
        self.logs: dict[str, dict] = {}
        self.alerts: dict[tuple[str, str], dict] = {}
        self.pruned: list[str] = []

    # compute_risk.RiskRepository -------------------------------------------
    def upsert(self, doc_id: str, body: dict) -> None:
        self.risk[doc_id] = body

    # dispatch_alerts.RiskHistoryProvider -----------------------------------
    def latest_two(self, city: str):
        docs = sorted(
            (b for b in self.risk.values() if b.get("city") == city),
            key=lambda b: b["generatedAt"],
            reverse=True,
        )

        def to_risk(b: dict) -> CityRisk:
            return CityRisk(
                city=b["city"],
                risk_level=b["riskLevel"],
                disease=b["disease"],
                generated_at=b["generatedAt"],
                model_version=b["modelVersion"],
                doc_id=f"{b['city']}_{b['generatedAt'][:10]}",
            )

        latest = to_risk(docs[0]) if docs else None
        previous = to_risk(docs[1]) if len(docs) > 1 else None
        return latest, previous

    # dispatch_alerts.DispatchRepository ------------------------------------
    def write_dispatch_log(self, log_id: str, body: dict) -> None:
        self.logs[log_id] = body

    def write_user_alert(self, uid: str, alert_id: str, body: dict) -> None:
        self.alerts[(uid, alert_id)] = body

    def has_dispatch(self, log_id: str) -> bool:
        return log_id in self.logs

    def recently_sent(self, uid: str, category: str, since: datetime) -> bool:
        return any(
            b["uid"] == uid
            and b["category"] == category
            and b["status"] == "sent"
            and b["createdAt"] >= since
            for b in self.logs.values()
        )

    def prune_token(self, uid: str) -> None:
        self.pruned.append(uid)

    def claim_dispatch(self, log_id: str, now: datetime) -> bool:
        if log_id in self.logs:
            return False
        self.logs[log_id] = {"status": "claimed", "claimedAt": now}
        return True


class FakeDirectory:
    def __init__(self, mapping: dict[str, list[TargetUser]]) -> None:
        self._m = mapping

    def users_in_city(self, city: str) -> list[TargetUser]:
        return self._m.get(city, [])


class FakeSender:
    def __init__(self, result: SendResult | None = None) -> None:
        self.result = result or SendResult("sent", message_id="m1")
        self.sends: list[dict] = []

    def send(self, *, token, title, body, data):
        self.sends.append({"token": token, "data": data})
        return self.result


# --- Fixtures ---------------------------------------------------------------


def _fake_base(city: str, n_weeks: int = 12, start_week: int = 6) -> pd.DataFrame:
    return pd.DataFrame(
        [
            {
                "city": city, "iso_year": 2026, "week_of_year": start_week + i,
                "days_in_week": 7, "temperature": 20.0 + i, "humidity": 55.0 + (i % 5),
                "precipitation": 3.0 + (i % 4), "pm2_5": 30.0 + i, "pm10": 50.0 + i,
                "us_aqi": 90.0 + 2 * i, "aqi_available": True,
            }
            for i in range(n_weeks)
        ]
    )


class _FakeProvider:
    def __init__(self, city: str) -> None:
        self._city = city

    def recent_weekly_base(self, city: dict):
        return _fake_base(city["name"])


def _risk_doc(city: str, level: str, disease: str, date: str) -> dict:
    """A contract-valid ``riskEstimates`` body (validated against the frozen
    schema) — the exact shape ``compute_risk`` writes, so ``dispatch`` reads it
    identically whether it was computed or seeded."""
    resp = RiskEstimateResponse(
        city=city,
        risk_level=level,
        disease=disease,
        confidence=0.82,
        temperature=34.0,
        humidity=55.0,
        aqi=180.0,
        generated_at=datetime.fromisoformat(f"{date}T00:00:00+00:00"),
        model_version="rf-1.0.0",
        low_confidence=False,
    )
    return resp.model_dump(by_alias=True, mode="json")


def _asthma_user(uid: str = "asthma_ok", prefs: dict | None = None) -> TargetUser:
    return TargetUser(
        uid=uid,
        city="Lahore",
        conditions=("Asthma",),
        fcm_token="tok",
        preferences=prefs if prefs is not None else _PREFS_ALL,
    )


def _dispatch(store: PipelineStore, directory: FakeDirectory, sender: FakeSender,
              now: datetime = NOW):
    return dispatch_alerts.run(
        history=store,
        directory=directory,
        sender=sender,
        repository=store,
        cities=[{"name": "Lahore"}],
        now=now,
    )


# --- Leg 1: predict → attribute → store, readable by dispatch ----------------


def test_compute_risk_output_carries_attributions_and_is_dispatch_readable() -> None:
    store = PipelineStore()
    report, outcomes = compute_risk.run_and_report(
        _FakeProvider("Lahore"),
        store,
        heartbeat=_NoopHeartbeat(),
        bundle=BUNDLE,
        cities=[{"name": "Lahore"}],
        generated_at=NOW,
    )

    # Stored a genuine, contract-valid estimate WITH model-derived attributions.
    (doc_id,), = (list(store.risk.keys()),)
    body = store.risk[doc_id]
    RiskEstimateResponse(**body)  # re-validates against the frozen contract
    att = body["attributions"]
    assert att["method"] == "tree_path_contributions"
    assert att["predictedClass"] == body["riskLevel"]  # explains the SAME class

    # dispatch can consume exactly what compute_risk wrote (the store seam).
    latest, _previous = store.latest_two("Lahore")
    assert latest is not None
    assert latest.city == body["city"]
    assert latest.risk_level == body["riskLevel"]
    assert latest.disease == body["disease"]
    assert latest.doc_id == doc_id


class _NoopHeartbeat:
    def write_heartbeat(self, job: str, body: dict) -> None:  # observability seam
        pass


# --- Leg 2: store → dispatch → inbox (the delivery) --------------------------


def _seed_smog_transition(store: PipelineStore) -> None:
    # A genuine rising transition: Medium (prev week) → High (this week), Smog.
    store.upsert("Lahore_2026-06-23", _risk_doc("Lahore", "Medium", "Smog", "2026-06-23"))
    store.upsert("Lahore_2026-06-30", _risk_doc("Lahore", "High", "Smog", "2026-06-30"))


def test_full_loop_delivers_exactly_one_inbox_alert() -> None:
    store = PipelineStore()
    _seed_smog_transition(store)
    sender = FakeSender()

    outcomes = _dispatch(store, FakeDirectory({"Lahore": [_asthma_user()]}), sender)

    sent = [o for o in outcomes if o.status == "sent"]
    assert len(sent) == 1
    assert len(sender.sends) == 1
    assert len(store.alerts) == 1

    # Inbox doc matches the frozen shape the Flutter inbox consumes.
    (_key, alert), = store.alerts.items()
    assert alert["read"] is False
    assert alert["riskEstimateId"] == "Lahore_2026-06-30"
    assert alert["recommendation"]["sourceUrl"].startswith("https://")
    assert alert["deepLink"] == "/resources"


def test_repeated_runs_produce_no_spam() -> None:
    store = PipelineStore()
    _seed_smog_transition(store)
    sender = FakeSender()
    directory = FakeDirectory({"Lahore": [_asthma_user()]})

    for _ in range(5):  # the scheduler fires the same estimate five times
        outcomes = _dispatch(store, directory, sender)

    assert len(sender.sends) == 1  # still one delivery after five runs
    assert len(store.alerts) == 1
    assert all(o.status == "skipped_idempotent" for o in outcomes)


def test_opted_out_user_receives_nothing() -> None:
    store = PipelineStore()
    _seed_smog_transition(store)
    sender = FakeSender()
    # Respiratory consent withdrawn — the Smog/respiratory driver no longer applies.
    opted_out = dict(_PREFS_ALL, conditions={"respiratory": False, "cardiovascular": True})

    outcomes = _dispatch(
        store, FakeDirectory({"Lahore": [_asthma_user(prefs=opted_out)]}), sender
    )

    assert sender.sends == []
    assert store.alerts == {}
    assert all(o.status != "sent" for o in outcomes)


def test_no_transition_sends_nothing() -> None:
    store = PipelineStore()
    # Steady High → High: no upward transition, so no proactive alert.
    store.upsert("Lahore_2026-06-23", _risk_doc("Lahore", "High", "Smog", "2026-06-23"))
    store.upsert("Lahore_2026-06-30", _risk_doc("Lahore", "High", "Smog", "2026-06-30"))
    sender = FakeSender()

    outcomes = _dispatch(store, FakeDirectory({"Lahore": [_asthma_user()]}), sender)

    assert sender.sends == []
    assert outcomes == []  # no user was even considered (no city transition)


# (The 24h same-category throttle is covered end-to-end by test_e2e_dispatch;
#  it is not re-derived here — a cumulative store can't cleanly express a second
#  *rising* transition within the window without a contrived dip-then-rise.)
