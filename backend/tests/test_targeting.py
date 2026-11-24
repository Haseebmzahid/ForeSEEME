"""Targeting predicate tests (Sprint 4, Prompt 2) — pure, deterministic.

Covers the four contract conditions independently: transition (up vs steady vs
falling), severity-band consent, vulnerability match, and category consent, plus
the deterministic single-category choice.
"""

from __future__ import annotations

from app.notification_registrations import Registration
from app.jobs.alerting import targeting
from app.jobs.alerting.targeting import CityRisk, TargetUser

_PREFS_ALL = {
    "highRiskAlerts": True,
    "mediumRiskAlerts": True,
    "lowRiskUpdates": False,
    "conditions": {"respiratory": True, "cardiovascular": True},
}


def city(level: str, disease: str = "Smog", doc: str = "Lahore_2026-06-30") -> CityRisk:
    return CityRisk(
        city="Lahore",
        risk_level=level,
        disease=disease,
        generated_at="2026-06-30T00:00:00.000Z",
        model_version="rf-1.0.0",
        doc_id=doc,
    )


def user(conditions, prefs=None, token="tok-1") -> TargetUser:
    return TargetUser(
        uid="u1",
        city="Lahore",
        conditions=tuple(conditions),
        registrations=(Registration("u1", token, 1, "test"),) if token else (),
        preferences=prefs if prefs is not None else _PREFS_ALL,
    )


def test_asthma_into_high_smog_is_targeted() -> None:
    target = targeting.evaluate(user(["Asthma"]), city("High"), city("Medium"))
    assert target is not None
    assert target.category == "respiratory"
    assert target.driver == "Air quality"
    assert target.risk_level == "High"
    assert target.previous_risk_level == "Medium"


def test_no_matching_condition_is_skipped() -> None:
    assert targeting.evaluate(user(["None"]), city("High"), city("Medium")) is None
    assert targeting.evaluate(user([]), city("High"), city("Medium")) is None


def test_disabled_category_is_skipped() -> None:
    prefs = dict(_PREFS_ALL, conditions={"respiratory": False, "cardiovascular": True})
    assert targeting.evaluate(user(["Asthma"], prefs), city("High"), city("Medium")) is None


def test_disabled_severity_is_skipped() -> None:
    prefs = dict(_PREFS_ALL, highRiskAlerts=False)
    assert targeting.evaluate(user(["Asthma"], prefs), city("High"), city("Medium")) is None


def test_steady_risk_is_not_a_transition() -> None:
    assert targeting.evaluate(user(["Asthma"]), city("High"), city("High")) is None


def test_falling_risk_is_skipped() -> None:
    assert targeting.evaluate(user(["Asthma"]), city("Medium"), city("High")) is None


def test_vulnerability_must_match_disease_category() -> None:
    # Heart disease is cardiovascular; a respiratory-only disease does not match.
    target = targeting.evaluate(
        user(["Heart Disease"]), city("High", "Respiratory Illness"), city("Medium")
    )
    assert target is None


def test_missing_token_is_skipped() -> None:
    assert targeting.evaluate(user(["Asthma"], token=None), city("High"), city("Medium")) is None


def test_insufficient_history_is_skipped() -> None:
    assert targeting.evaluate(user(["Asthma"]), city("High"), None) is None
    assert targeting.evaluate(user(["Asthma"]), None, city("Medium")) is None


def test_heart_user_into_high_heat_is_cardiovascular() -> None:
    target = targeting.evaluate(
        user(["Heart Disease"]), city("High", "Heat-Related Illness"), city("Medium")
    )
    assert target is not None
    assert target.category == "cardiovascular"
    assert target.driver == "Heat"


def test_multi_condition_picks_priority_category() -> None:
    # Smog → {respiratory, cardiovascular}; user has both. Respiratory wins.
    target = targeting.evaluate(
        user(["Asthma", "Heart Disease"]), city("High", "Smog"), city("Low")
    )
    assert target is not None
    assert target.category == "respiratory"


def test_dengue_has_no_in_scope_condition() -> None:
    assert targeting.evaluate(
        user(["Asthma", "Heart Disease"]), city("High", "Dengue"), city("Medium")
    ) is None
