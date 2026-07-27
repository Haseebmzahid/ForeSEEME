"""Seed the curated Resource Center articles into Firestore (Sprint M8.3).

Writes the same 8 articles the app used to ship statically
(``lib/features/resources/data/repositories/static_resource_repository.dart``)
into the ``articles`` collection the CMS now reads/writes, so a fresh or
previously-unseeded Firestore project has real content instead of relying on
the app's client-side fallback (`FirestoreResourceRepository` degrades to the
static list when the collection is empty, but that fallback is not a
replacement for actually seeding production/staging — it exists so a momentary
gap never shows a blank Resource Center, not so seeding can be skipped).

Field shapes mirror ``ResourceArticle.toJson()`` exactly (Dart is the source
of truth this was transcribed from) so a client reading a seeded document
round-trips identically to reading an admin-authored one.

Safety / configuration (GOLDEN_RULES #7 — no secrets in source):
- Service-account credentials path is read from ``GOOGLE_APPLICATION_CREDENTIALS``;
  the JSON itself is git-ignored and never committed.
- Against the Firestore emulator, set ``FIRESTORE_EMULATOR_HOST`` instead.
- Writes are idempotent: ``set()`` keyed by the article's stable slug id, so
  re-running updates rather than duplicates.

Run:
    GOOGLE_APPLICATION_CREDENTIALS=/path/to/sa.json python backend/scripts/seed_resource_articles.py

See backend/scripts/README.md for the full, safe procedure.
"""

from __future__ import annotations

import logging
import os

import firebase_admin
from firebase_admin import credentials, firestore

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
logger = logging.getLogger("seed_resource_articles")

COLLECTION = "articles"

_WHO = "World Health Organization (WHO)"
_WHO_AIR_URL = "https://www.who.int/health-topics/air-pollution"
_WHO_HEAT_URL = "https://www.who.int/health-topics/heatwaves"
_CDC = "U.S. Centers for Disease Control and Prevention (CDC)"
_CDC_ASTHMA_URL = "https://www.cdc.gov/asthma/"
_EPA = "U.S. EPA — AirNow"
_EPA_URL = "https://www.airnow.gov/aqi/aqi-basics/"


def _h(text: str) -> dict:
    return {"kind": "heading", "text": text}


def _p(text: str) -> dict:
    return {"kind": "paragraph", "text": text}


def _tip(text: str) -> dict:
    return {"kind": "tip", "text": text}


def _warn(text: str) -> dict:
    return {"kind": "warning", "text": text}


# (doc_id, body) — body shape mirrors ResourceArticle.toJson() (no "id" key;
# the doc id IS the id).
_ARTICLES: list[tuple[str, dict]] = [
    (
        "lungs-smog",
        {
            "title": "Protecting your lungs on smog days",
            "summary": "Cut your exposure to fine particles when air quality is poor.",
            "topic": "lungs",
            "sourceName": _WHO,
            "sourceUrl": _WHO_AIR_URL,
            "verified": True,
            "content": [
                _h("Before you go outside"),
                _p(
                    "Check your local Air Quality Index before heading out, and limit "
                    "prolonged or heavy outdoor exertion when it is high."
                ),
                _p(
                    "Keep windows and doors closed during peak smog hours to reduce "
                    "indoor particle levels."
                ),
                _h("If you must be outside"),
                _tip(
                    "A well-fitted N95/FFP2 mask reduces the fine particles you "
                    "inhale during heavy smog."
                ),
                _p("Indoors, a HEPA air purifier can lower fine-particle concentrations."),
                _warn(
                    "Avoid adding indoor smoke — cigarettes, incense, or unventilated "
                    "cooking — on top of outdoor smog."
                ),
            ],
        },
    ),
    (
        "lungs-indoor-air",
        {
            "title": "Indoor air quality on polluted days",
            "summary": "Keep the air inside cleaner while outdoor smog is high.",
            "topic": "lungs",
            "sourceName": _WHO,
            "sourceUrl": _WHO_AIR_URL,
            "verified": True,
            "content": [
                _h("Reduce indoor sources"),
                _p(
                    "Most indoor air pollution comes from combustion — cooking smoke, "
                    "candles, incense and tobacco — so cutting these sources matters as "
                    "much as sealing out the smog outside."
                ),
                _tip(
                    "Use an extractor fan or open a window briefly while cooking, then "
                    "reseal the room once smoke has cleared."
                ),
                _h("When outdoor air improves"),
                _p(
                    "Ventilate during the cleanest part of the day (check your AQI "
                    "trend) rather than leaving windows open continuously."
                ),
                _warn(
                    "Never use an unvented gas or charcoal appliance indoors — it can "
                    "raise indoor pollution and carbon-monoxide risk sharply."
                ),
            ],
        },
    ),
    (
        "asthma-poor-air",
        {
            "title": "Managing asthma when air quality is poor",
            "summary": "Stay ahead of flare-ups on high-pollution days.",
            "topic": "asthma",
            "sourceName": _CDC,
            "sourceUrl": _CDC_ASTHMA_URL,
            "verified": True,
            "content": [
                _h("Stay ahead of a flare-up"),
                _p(
                    "Keep your reliever (rescue) inhaler with you and follow your "
                    "written asthma action plan."
                ),
                _tip(
                    "Move exercise indoors or to cleaner-air times of day when the "
                    "Air Quality Index is high."
                ),
                _h("At home"),
                _p(
                    "Reduce indoor triggers: no smoking indoors, manage dust, and keep "
                    "indoor air as clean as possible."
                ),
                _warn(
                    "If symptoms worsen — frequent coughing, wheezing or "
                    "breathlessness — seek medical care promptly."
                ),
            ],
        },
    ),
    (
        "asthma-action-plan",
        {
            "title": "Building your asthma action plan",
            "summary": "A written plan turns a bad day into a manageable one.",
            "topic": "asthma",
            "sourceName": _CDC,
            "sourceUrl": _CDC_ASTHMA_URL,
            "verified": True,
            "content": [
                _h("What a plan covers"),
                _p(
                    "A written asthma action plan sets out your daily medicines, the "
                    "early warning signs of a flare-up, and exactly what to do at each "
                    "stage — agreed in advance with your clinician."
                ),
                _tip(
                    "Keep a copy where you can find it quickly, and share one with a "
                    "family member or housemate."
                ),
                _h("Reviewing it"),
                _p(
                    "Revisit the plan with your clinician after any flare-up, or at "
                    "least once a year, so it stays matched to how your asthma is "
                    "behaving."
                ),
                _warn(
                    "A plan is guidance, not a diagnosis — always follow your own "
                    "clinician's instructions over general guidance like this."
                ),
            ],
        },
    ),
    (
        "when-to-stay-indoors",
        {
            "title": "When to stay indoors (Air Quality Index)",
            "summary": "What each AQI band means for outdoor activity.",
            "topic": "airQuality",
            "sourceName": _EPA,
            "sourceUrl": _EPA_URL,
            "verified": True,
            "content": [
                _h("Reading the bands"),
                _p("AQI 0–50 (Good): air quality is satisfactory; no precautions needed."),
                _p(
                    "AQI 51–100 (Moderate): unusually sensitive people should consider "
                    "limiting prolonged outdoor exertion."
                ),
                _p(
                    "AQI 101–150 (Unhealthy for Sensitive Groups): sensitive groups "
                    "(children, older adults, heart/lung conditions) should reduce "
                    "prolonged outdoor exertion."
                ),
                _h("When it gets serious"),
                _tip(
                    "AQI 151–200 (Unhealthy): everyone should reduce prolonged "
                    "outdoor exertion; sensitive groups should avoid it."
                ),
                _warn(
                    "AQI 201+ (Very Unhealthy/Hazardous): avoid outdoor activity and "
                    "stay indoors with clean air where possible."
                ),
            ],
        },
    ),
    (
        "aqi-pm-sizes",
        {
            "title": "Understanding PM2.5 vs PM10",
            "summary": "The two particle sizes behind most AQI readings, explained.",
            "topic": "airQuality",
            "sourceName": _EPA,
            "sourceUrl": _EPA_URL,
            "verified": True,
            "content": [
                _h("What the numbers mean"),
                _p(
                    "PM2.5 (particles under 2.5 micrometres) travel deepest into the "
                    "lungs and bloodstream and drive most health guidance; PM10 "
                    "(under 10 micrometres) affects the upper airway more."
                ),
                _tip(
                    "On a smoggy day, PM2.5 is usually the number worth checking — it "
                    "is the more sensitive signal."
                ),
                _h("Where they come from"),
                _p(
                    "Vehicle exhaust, industrial smoke and burning are common PM2.5 "
                    "sources; dust and pollen contribute more to PM10."
                ),
            ],
        },
    ),
    (
        "extreme-heat",
        {
            "title": "Staying safe in extreme heat",
            "summary": "Reduce heat-illness risk during hot spells.",
            "topic": "heat",
            "sourceName": _WHO,
            "sourceUrl": _WHO_HEAT_URL,
            "verified": True,
            "content": [
                _h("Through the day"),
                _p("Drink water regularly through the day, even before you feel thirsty."),
                _p("Avoid the sun during the hottest hours and limit strenuous activity."),
                _tip("Keep your living space cool — shade windows, ventilate at night."),
                _h("Warning signs"),
                _warn(
                    "Watch for heat exhaustion (dizziness, headache, nausea); move to "
                    "a cool place, rest and rehydrate, and seek help if it does not "
                    "improve. Never leave children or pets in a parked vehicle."
                ),
            ],
        },
    ),
    (
        "heat-exhaustion-vs-stroke",
        {
            "title": "Recognizing heat exhaustion vs heat stroke",
            "summary": "Know the difference — one of them is a medical emergency.",
            "topic": "heat",
            "sourceName": _WHO,
            "sourceUrl": _WHO_HEAT_URL,
            "verified": True,
            "content": [
                _h("Heat exhaustion"),
                _p(
                    "Heavy sweating, dizziness, headache, nausea and cool clammy skin. "
                    "Move to shade or air conditioning, loosen clothing, and rehydrate "
                    "with water."
                ),
                _h("Heat stroke"),
                _p(
                    "Hot, dry or flushed skin, confusion, or loss of consciousness are "
                    "signs the body has stopped regulating its temperature."
                ),
                _warn(
                    "Heat stroke is a medical emergency. Call for emergency help "
                    "immediately and cool the person while waiting — do not wait to "
                    "see if it improves."
                ),
            ],
        },
    ),
]


def _init_firestore() -> firestore.firestore.Client:
    """Initialise the Admin SDK from the environment and return a client.

    Prefers a real service account (``GOOGLE_APPLICATION_CREDENTIALS``); falls
    back to the emulator (``FIRESTORE_EMULATOR_HOST``) which needs no credentials.
    Never hardcodes credentials or a project id.
    """
    if not firebase_admin._apps:
        cred_path = os.getenv("GOOGLE_APPLICATION_CREDENTIALS")
        emulator = os.getenv("FIRESTORE_EMULATOR_HOST")
        if cred_path:
            logger.info("Using service-account credentials from env.")
            firebase_admin.initialize_app(credentials.Certificate(cred_path))
        elif emulator:
            project_id = (
                os.getenv("FIREBASE_PROJECT_ID")
                or os.getenv("GCLOUD_PROJECT")
                or "demo-foreseeme"
            )
            logger.info("Using Firestore emulator at %s (project=%s).", emulator, project_id)
            firebase_admin.initialize_app(options={"projectId": project_id})
        else:
            raise SystemExit(
                "Set GOOGLE_APPLICATION_CREDENTIALS (real project) or "
                "FIRESTORE_EMULATOR_HOST (emulator) before running."
            )
    return firestore.client()


def seed() -> int:
    """Write all articles idempotently (upsert by slug id). Returns the count."""
    db = _init_firestore()
    collection = db.collection(COLLECTION)

    count = 0
    for doc_id, body in _ARTICLES:
        collection.document(doc_id).set(body)
        count += 1
        logger.info("seeded %s -> %s", doc_id, body["title"])

    logger.info("Done. %d articles document(s) written.", count)
    return count


if __name__ == "__main__":
    seed()
