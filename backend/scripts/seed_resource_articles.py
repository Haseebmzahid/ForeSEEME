"""Seed the trusted Resource Center catalogue into Firestore (Sprint M8.3).

Writes the same catalogue the app ships with
(``lib/features/resources/data/repositories/static_resource_repository.dart``)
into the ``articles`` collection the CMS reads/writes, so a fresh or
previously-unseeded Firestore project has real content instead of relying on
the app's client-side fallback (`FirestoreResourceRepository` degrades to the
bundled catalogue when the collection is empty or unreadable, but that
fallback is not a replacement for actually seeding production/staging — it
exists so a gap never shows a blank Resource Center, not so seeding can be
skipped).

The payload is **generated**, not transcribed: ``resource_articles.json`` next
to this script is emitted straight from ``ResourceArticle.toJson()``, so the
seeded documents and the bundled catalogue cannot drift. Regenerate it after
changing the Dart catalogue rather than hand-editing either file.

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

import json
import logging
import os
import pathlib

import firebase_admin
from firebase_admin import credentials, firestore

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
logger = logging.getLogger("seed_resource_articles")

COLLECTION = "articles"


_PAYLOAD = pathlib.Path(__file__).with_name("resource_articles.json")


def _load() -> dict:
    """The generated catalogue payload, keyed by the article's stable slug id.

    Each value is exactly one ``ResourceArticle.toJson()`` body, so a client
    reading a seeded document round-trips identically to reading an
    admin-authored one — including the production-catalogue fields
    (``authority``, ``categories``, ``publishedAt``, ``lastVerifiedAt``).
    """
    if not _PAYLOAD.exists():
        raise SystemExit(
            f"Missing {_PAYLOAD.name}. Regenerate it from the Dart catalogue "
            "before seeding."
        )
    with _PAYLOAD.open(encoding="utf-8") as handle:
        return json.load(handle)


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
    for doc_id, body in _load().items():
        collection.document(doc_id).set(body)
        count += 1
        logger.info("seeded %s -> %s", doc_id, body["title"])

    logger.info("Done. %d articles document(s) written.", count)
    return count


if __name__ == "__main__":
    seed()
