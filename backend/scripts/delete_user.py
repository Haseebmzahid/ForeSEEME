"""Delete a Firebase Auth account, and optionally its Firestore data
(Sprint M8.4, SDS FR8.5).

The admin user-management UI is deliberately read-only (see
docs/user_management.md) — account deletion needs the Firebase Auth Admin
SDK, not a Firestore write, so it is an operator script rather than an in-app
button. Mirrors `set_admin_claim.py`/`set_user_status.py`'s safe-init shape.

Two separate, explicit flags rather than one implicit "delete everything":
- ``--confirm`` (required): the SDS's "Deletion must require confirmation to
  prevent accidental removal" business rule, translated to a CLI — the script
  refuses to do anything without it, so a bare uid/email argument alone is a
  no-op, not an accidental deletion.
- ``--purge-data`` (optional, additive): also deletes their Firestore data
  (``users/{uid}`` and every subcollection, plus ``userDirectory/{uid}``).
  Deleting only the Auth account (no ``--purge-data``) leaves their app data
  in place but makes the account permanently unable to sign back in to it —
  the operator decides which behaviour they want each time; this script never
  silently does more than asked.

Safety / configuration (GOLDEN_RULES #7 — no secrets in source):
- Service-account credentials path is read from ``GOOGLE_APPLICATION_CREDENTIALS``.
- Against the emulators, set ``FIREBASE_AUTH_EMULATOR_HOST`` and
  ``FIRESTORE_EMULATOR_HOST`` instead.

Run:
    GOOGLE_APPLICATION_CREDENTIALS=/path/sa.json python backend/scripts/delete_user.py user@example.com --confirm
    GOOGLE_APPLICATION_CREDENTIALS=/path/sa.json python backend/scripts/delete_user.py user@example.com --confirm --purge-data

See backend/scripts/README.md for the full, safe procedure.
"""

from __future__ import annotations

import logging
import os
import sys

import firebase_admin
from firebase_admin import auth, credentials, firestore

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
logger = logging.getLogger("delete_user")


def _init_app() -> None:
    if firebase_admin._apps:
        return
    cred_path = os.getenv("GOOGLE_APPLICATION_CREDENTIALS")
    emulator = os.getenv("FIREBASE_AUTH_EMULATOR_HOST")
    if cred_path:
        firebase_admin.initialize_app(credentials.Certificate(cred_path))
    elif emulator:
        project_id = (
            os.getenv("FIREBASE_PROJECT_ID")
            or os.getenv("GCLOUD_PROJECT")
            or "demo-foreseeme"
        )
        firebase_admin.initialize_app(options={"projectId": project_id})
    else:
        raise SystemExit(
            "Set GOOGLE_APPLICATION_CREDENTIALS (real project) or "
            "FIREBASE_AUTH_EMULATOR_HOST (emulator) before running this script."
        )


def _resolve_uid(identifier: str) -> str:
    """Accept either a uid or an email; return the uid."""
    if "@" in identifier:
        return auth.get_user_by_email(identifier).uid
    return auth.get_user(identifier).uid


def _delete_recursive(doc_ref) -> int:
    """Deletes [doc_ref] and every document in every subcollection beneath it.

    Firestore never cascade-deletes subcollections on its own, so this walks
    them manually rather than assuming a specific client-library convenience
    method is available. Returns the number of documents deleted (excluding
    [doc_ref] itself).
    """
    count = 0
    for subcollection in doc_ref.collections():
        for sub_doc in subcollection.stream():
            count += _delete_recursive(sub_doc.reference)
    doc_ref.delete()
    return count


def delete_user(identifier: str, *, purge_data: bool) -> None:
    _init_app()
    uid = _resolve_uid(identifier)

    auth.delete_user(uid)
    logger.info("Firebase Auth account deleted for uid=%s (%s)", uid, identifier)

    if purge_data:
        db = firestore.client()
        deleted = _delete_recursive(db.collection("users").document(uid))
        db.collection("userDirectory").document(uid).delete()
        logger.info(
            "Purged Firestore data for uid=%s (%d subcollection document(s) + "
            "the user root + the directory entry).",
            uid,
            deleted,
        )
    else:
        logger.info(
            "Firestore data for uid=%s left in place (pass --purge-data to "
            "remove it too).",
            uid,
        )


def main(argv: list[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    args = [a for a in argv if not a.startswith("--")]
    if len(args) != 1:
        logger.error(
            "usage: python backend/scripts/delete_user.py <uid|email> --confirm "
            "[--purge-data]"
        )
        return 2
    if "--confirm" not in argv:
        logger.error(
            "Refusing to delete without --confirm (SDS FR8.5: deletion must "
            "require confirmation)."
        )
        return 2
    delete_user(args[0], purge_data="--purge-data" in argv)
    return 0


if __name__ == "__main__":
    sys.exit(main())
