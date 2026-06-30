"""Deterministic, cited recommendation lookup (Sprint 4, Prompt 2).

A fixed table keyed by `(category, driver)` — the engine **never generates**
medical text (Rule 11). Mirrors `docs/recommendation_rules.md`; every entry has a
cited source, and lookup is total via [DEFAULT].
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Recommendation:
    id: str
    category: str
    driver: str
    text: str
    source: str
    source_url: str
    deep_link: str
    escalation: str


_RESP_AIR = Recommendation(
    id="rec-resp-air",
    category="respiratory",
    driver="Air quality",
    text=(
        "Limit prolonged or heavy outdoor exertion; keep windows closed during "
        "peak smog; a well-fitted N95/FFP2 mask reduces fine-particle exposure; "
        "run a HEPA purifier indoors."
    ),
    source="WHO — Air pollution",
    source_url="https://www.who.int/health-topics/air-pollution",
    deep_link="/resources",
    escalation=(
        "If breathing worsens (frequent wheeze/breathlessness), seek medical "
        "care; emergency → Rescue 1122."
    ),
)

_RESP_SEASONAL = Recommendation(
    id="rec-resp-seasonal",
    category="respiratory",
    driver="Respiratory",
    text=(
        "Keep your reliever inhaler with you and follow your asthma action "
        "plan; avoid crowded indoor spaces during peak respiratory season."
    ),
    source="CDC — Asthma",
    source_url="https://www.cdc.gov/asthma/",
    deep_link="/resources",
    escalation="Seek care promptly if symptoms escalate; emergency → Rescue 1122.",
)

_CARDIO_AIR = Recommendation(
    id="rec-cardio-air",
    category="cardiovascular",
    driver="Air quality",
    text=(
        "On high-AQI days, reduce strenuous outdoor activity; sensitive groups "
        "(heart/lung conditions) should limit prolonged exertion and keep "
        "medications on hand."
    ),
    source="US EPA — AirNow AQI",
    source_url="https://www.airnow.gov/aqi/aqi-basics/",
    deep_link="/resources",
    escalation=(
        "Chest discomfort/shortness of breath → seek urgent care; emergency → "
        "Rescue 1122."
    ),
)

_CARDIO_HEAT = Recommendation(
    id="rec-cardio-heat",
    category="cardiovascular",
    driver="Heat",
    text=(
        "Drink water regularly, avoid the hottest hours, and keep cool. Heart "
        "disease, hypertension or diabetes reduce heat tolerance — watch for "
        "dizziness, headache or nausea."
    ),
    source="WHO — Heatwaves",
    source_url="https://www.who.int/health-topics/heatwaves",
    deep_link="/nearby-hospitals",
    escalation=(
        "Heat exhaustion not improving, or chest pain/confusion → seek help "
        "immediately; emergency → Rescue 1122."
    ),
)

DEFAULT = Recommendation(
    id="rec-default",
    category="*",
    driver="*",
    text=(
        "Check your local Air Quality Index and follow official guidance for "
        "your area. This is general information, not personal medical advice."
    ),
    source="US EPA — AirNow AQI",
    source_url="https://www.airnow.gov/aqi/aqi-basics/",
    deep_link="/resources",
    escalation=(
        "For personal guidance consult a healthcare professional; emergency → "
        "Rescue 1122."
    ),
)

_TABLE: dict[tuple[str, str], Recommendation] = {
    ("respiratory", "Air quality"): _RESP_AIR,
    ("respiratory", "Respiratory"): _RESP_SEASONAL,
    ("cardiovascular", "Air quality"): _CARDIO_AIR,
    ("cardiovascular", "Heat"): _CARDIO_HEAT,
}


def lookup(category: str, driver: str) -> Recommendation:
    """Total lookup: an exact `(category, driver)` row, else the cited default."""
    return _TABLE.get((category, driver), DEFAULT)
