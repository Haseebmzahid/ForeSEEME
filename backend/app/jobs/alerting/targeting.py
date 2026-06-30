"""Targeting predicate for the alert dispatch engine (Sprint 4, Prompt 2).

Pure, deterministic, no I/O. Implements the frozen contract
(`docs/alert_dispatch_design.md` §2 + §5): a user is alerted iff the city risk
**transitioned up into a severity band they enabled**, the disease's risk-driver
category intersects one of the user's chronic-condition categories, that category
is **consented**, and a delivery token exists.

The condition→category, disease→category, and disease→driver maps below mirror
the contract §5 exactly — do not redesign them here.
"""

from __future__ import annotations

from dataclasses import dataclass

# --- Frozen contract maps (alert_dispatch_design.md §5) ---------------------

BAND: dict[str, int] = {"Low": 1, "Medium": 2, "High": 3}

# disease -> the condition categories made vulnerable by its risk driver.
DISEASE_CATEGORIES: dict[str, frozenset[str]] = {
    "Smog": frozenset({"respiratory", "cardiovascular"}),
    "Respiratory Illness": frozenset({"respiratory"}),
    "Influenza": frozenset({"respiratory"}),
    "Heat-Related Illness": frozenset({"cardiovascular"}),
    "Dengue": frozenset(),  # vector-borne: no in-scope chronic-condition driver
}

# disease -> human risk-driver label (used to pick the cited recommendation).
DISEASE_DRIVER: dict[str, str] = {
    "Smog": "Air quality",
    "Respiratory Illness": "Air quality",
    "Influenza": "Respiratory",
    "Heat-Related Illness": "Heat",
    "Dengue": "Vector-borne",
}

# chronic condition (kChronicConditions) -> notificationPreferences category.
CONDITION_CATEGORY: dict[str, str] = {
    "Asthma": "respiratory",
    "Heart Disease": "cardiovascular",
    "Hypertension": "cardiovascular",
    "Diabetes": "cardiovascular",
}

# When a user matches more than one category, pick deterministically (one alert).
CATEGORY_PRIORITY: tuple[str, ...] = ("respiratory", "cardiovascular")

# risk level -> the notificationPreferences severity toggle that enables it.
SEVERITY_PREF_KEY: dict[str, str] = {
    "High": "highRiskAlerts",
    "Medium": "mediumRiskAlerts",
    "Low": "lowRiskUpdates",
}


# --- Inputs / output --------------------------------------------------------


@dataclass(frozen=True)
class CityRisk:
    """A riskEstimates document, parsed to what targeting needs."""

    city: str
    risk_level: str
    disease: str
    generated_at: str  # ISO-8601 UTC string (contract)
    model_version: str
    doc_id: str  # {city}_{YYYY-MM-DD}


@dataclass(frozen=True)
class TargetUser:
    uid: str
    city: str
    conditions: tuple[str, ...]
    fcm_token: str | None
    preferences: dict  # the user's notificationPreferences map


@dataclass(frozen=True)
class Target:
    """A qualifying (user, estimate) pairing ready to dispatch."""

    uid: str
    city: str
    category: str
    driver: str
    disease: str
    risk_level: str
    previous_risk_level: str


# --- Predicate pieces (each independently testable) -------------------------


def band(level: str) -> int:
    return BAND.get(level, 0)


def risk_rose(previous: CityRisk, latest: CityRisk) -> bool:
    """City-level transition: the band strictly increased this cycle."""
    return band(latest.risk_level) > band(previous.risk_level)


def severity_enabled(level: str, preferences: dict) -> bool:
    key = SEVERITY_PREF_KEY.get(level)
    return bool(preferences.get(key, False)) if key else False


def user_categories(conditions: tuple[str, ...]) -> set[str]:
    return {CONDITION_CATEGORY[c] for c in conditions if c in CONDITION_CATEGORY}


def disease_categories(disease: str) -> frozenset[str]:
    return DISEASE_CATEGORIES.get(disease, frozenset())


def driver_for_disease(disease: str) -> str:
    return DISEASE_DRIVER.get(disease, "Air quality")


def choose_category(categories: set[str]) -> str | None:
    for category in CATEGORY_PRIORITY:
        if category in categories:
            return category
    return None


def evaluate(
    user: TargetUser,
    latest: CityRisk | None,
    previous: CityRisk | None,
) -> Target | None:
    """Returns a [Target] iff all four contract conditions hold, else None."""
    if latest is None or previous is None:
        return None
    # 1. transition UP into an enabled severity band
    if not risk_rose(previous, latest):
        return None
    if not severity_enabled(latest.risk_level, user.preferences):
        return None
    # 4. deliverable
    if not user.fcm_token:
        return None
    # 2 + 3. vulnerability ∩ disease category, then consent for that category
    matched = user_categories(user.conditions) & disease_categories(latest.disease)
    consented_prefs = user.preferences.get("conditions", {}) or {}
    consented = {c for c in matched if bool(consented_prefs.get(c, False))}
    category = choose_category(consented)
    if category is None:
        return None

    return Target(
        uid=user.uid,
        city=latest.city,
        category=category,
        driver=driver_for_disease(latest.disease),
        disease=latest.disease,
        risk_level=latest.risk_level,
        previous_risk_level=previous.risk_level,
    )
