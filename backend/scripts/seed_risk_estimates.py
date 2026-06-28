"""Seed sample ``riskEstimates`` documents into Firestore.

Populates ~8 sample documents (Lahore, Islamabad, Karachi, Peshawar across two
dates, varied Low/Medium/High levels) so the Sprint-3 dashboard has data to
render. Each document is validated against the frozen Prompt-1 contract
(:class:`app.schemas.RiskEstimateResponse`) before writing, so seed values
satisfy the contract exactly.

Safety / configuration (GOLDEN_RULES #7 — no secrets in source):
- Service-account credentials path is read from the ``GOOGLE_APPLICATION_CREDENTIALS``
  environment variable; the JSON itself is git-ignored and never committed.
- Against the Firestore emulator, set ``FIRESTORE_EMULATOR_HOST`` instead (no real
  credentials needed); the project id comes from ``FIREBASE_PROJECT_ID`` /
  ``GCLOUD_PROJECT``.
- Writes are idempotent: ``set(..., merge=True)`` keyed by the
  ``{city}_{YYYY-MM-DD}`` document id, so re-running updates rather than duplicates.

Run:
    GOOGLE_APPLICATION_CREDENTIALS=/path/to/sa.json python backend/scripts/seed_risk_estimates.py

See backend/scripts/README.md for the full, safe procedure.
"""

from __future__ import annotations

import logging
import os
import sys
from datetime import datetime, timezone

# Make the sibling `app` package importable so we can reuse the frozen contract.
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import firebase_admin  # noqa: E402
from firebase_admin import credentials, firestore  # noqa: E402

from app.schemas import RiskEstimateResponse  # noqa: E402

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
logger = logging.getLogger("seed_risk_estimates")

COLLECTION = "riskEstimates"

# Two recent dates (UTC) to seed across.
_DATE_A = datetime(2026, 6, 27, tzinfo=timezone.utc)
_DATE_B = datetime(2026, 6, 28, tzinfo=timezone.utc)

# Sample data: (city, generatedAt, riskLevel, disease, confidence, temperature,
# humidity, aqi, lowConfidence). Values chosen to be plausible and to cover all
# three risk levels across cities/dates.
_SAMPLES: list[tuple] = [
    ("Lahore", _DATE_A, "High", "Dengue", 0.91, 39.0, 64.0, 210.0, False),
    ("Islamabad", _DATE_A, "Low", "Respiratory Illness", 0.55, 24.0, 45.0, 55.0, True),
    ("Karachi", _DATE_A, "Medium", "Heat-Related Illness", 0.68, 34.0, 70.0, 130.0, False),
    ("Peshawar", _DATE_A, "High", "Heat-Related Illness", 0.84, 41.0, 38.0, 180.0, False),
    ("Lahore", _DATE_B, "Medium", "Dengue", 0.66, 35.0, 60.0, 140.0, False),
    ("Islamabad", _DATE_B, "Low", "Respiratory Illness", 0.58, 23.0, 47.0, 48.0, True),
    ("Karachi", _DATE_B, "High", "Heat-Related Illness", 0.88, 37.0, 72.0, 200.0, False),
    ("Peshawar", _DATE_B, "Medium", "Respiratory Illness", 0.71, 33.0, 40.0, 120.0, False),
]

MODEL_VERSION = os.getenv("MODEL_VERSION", "stub-0.0.0")


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


def _build_document(sample: tuple) -> tuple[str, dict]:
    """Validate one sample against the contract and return ``(doc_id, body)``."""
    city, generated_at, risk_level, disease, confidence, temperature, humidity, aqi, low = (
        sample
    )
    estimate = RiskEstimateResponse(
        city=city,
        riskLevel=risk_level,
        disease=disease,
        confidence=confidence,
        temperature=temperature,
        humidity=humidity,
        aqi=aqi,
        generatedAt=generated_at,
        modelVersion=MODEL_VERSION,
        lowConfidence=low,
    )
    # `mode="json"` serialises datetime -> ISO-8601 string (the contract form)
    # and `by_alias=True` emits the camelCase contract keys.
    body = estimate.model_dump(by_alias=True, mode="json")
    doc_id = f"{city}_{generated_at.strftime('%Y-%m-%d')}"
    return doc_id, body


def seed() -> int:
    """Write all sample documents idempotently. Returns the count written."""
    db = _init_firestore()
    collection = db.collection(COLLECTION)

    count = 0
    for sample in _SAMPLES:
        doc_id, body = _build_document(sample)
        collection.document(doc_id).set(body, merge=True)
        count += 1
        logger.info("seeded %s -> %s (%s)", doc_id, body["riskLevel"], body["disease"])

    logger.info("Done. %d riskEstimates documents written/merged.", count)
    return count


if __name__ == "__main__":
    seed()
