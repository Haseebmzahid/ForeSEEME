"""Suspend or reactivate a Firebase Auth account (Sprint M8.4, SDS FR8.5).

The admin user-management UI is deliberately read-only (see
docs/user_management.md): the SDS's "Suspend/Block" and "Reactivate" rows need
the account to actually stop being able to sign in, which only the Firebase
Auth Admin SDK's `disabled` flag does — a Firestore-only status field would be
a label nobody's account respects. This script is the trusted way an operator
performs that action, mirroring `set_admin_claim.py`'s exact shape.

Safety / configuration (GOLDEN_RULES #7 — no secrets in source):
- Service-account credentials path is read from ``GOOGLE_APPLICATION_CREDENTIALS``
  (the JSON is git-ignored, never committed).
- Against the Auth emulator, set ``FIREBASE_AUTH_EMULATOR_HOST`` instead; the
  project id comes from ``FIREBASE_PROJECT_ID`` / ``GCLOUD_PROJECT``.

A disabled user is immediately signed out of any active session the next time
Firebase validates their token (typically within an hour, or immediately if
the app re-authenticates) and cannot sign in again until re-enabled.

Run:
    # suspend (by uid or email):
    GOOGLE_APPLICATION_CREDENTIALS=/path/sa.json python backend/scripts/set_user_status.py user@example.com --disable
    # reactivate:
    GOOGLE_APPLICATION_CREDENTIALS=/path/sa.json python backend/scripts/set_user_status.py user@example.com --enable

See backend/scripts/README.md for the full, safe procedure.
"""

from __future__ import annotations

import logging
import os
import sys

import firebase_admin
from firebase_admin import auth, credentials

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
logger = logging.getLogger("set_user_status")


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


def set_status(identifier: str, *, disable: bool) -> None:
    _init_app()
    uid = _resolve_uid(identifier)
    auth.update_user(uid, disabled=disable)
    action = "suspended" if disable else "reactivated"
    logger.info("account %s for uid=%s (%s)", action, uid, identifier)


def main(argv: list[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    args = [a for a in argv if not a.startswith("--")]
    if len(args) != 1 or ("--disable" in argv) == ("--enable" in argv):
        logger.error(
            "usage: python backend/scripts/set_user_status.py <uid|email> "
            "(--disable | --enable)"
        )
        return 2
    set_status(args[0], disable="--disable" in argv)
    return 0


if __name__ == "__main__":
    sys.exit(main())
