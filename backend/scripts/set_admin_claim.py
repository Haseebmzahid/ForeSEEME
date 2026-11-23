"""Grant or revoke the ``admin`` custom claim for a Firebase Auth user (Sprint 5, Prompt 13).

The manual risk-override safety valve is gated on an ``admin`` custom claim, both
in `firestore.rules` (``request.auth.token.admin == true``) and in the app's
guarded admin surface. Custom claims can ONLY be set by the Admin SDK (never by a
client), so this small operator script is the trusted way to designate an operator.

Safety / configuration (GOLDEN_RULES #7 — no secrets in source):
- Service-account credentials path is read from ``GOOGLE_APPLICATION_CREDENTIALS``
  (the JSON is git-ignored, never committed).
- Against the Auth emulator, set ``FIREBASE_AUTH_EMULATOR_HOST`` instead; the
  project id comes from ``FIREBASE_PROJECT_ID`` / ``GCLOUD_PROJECT``.

The user must sign out / refresh their ID token for a new claim to take effect
(the app force-refreshes the token when reading the claim).

Run:
    # grant (by uid or email):
    GOOGLE_APPLICATION_CREDENTIALS=/path/sa.json python backend/scripts/set_admin_claim.py operator@example.com
    # revoke:
    GOOGLE_APPLICATION_CREDENTIALS=/path/sa.json python backend/scripts/set_admin_claim.py operator@example.com --revoke

See backend/scripts/README.md for the full, safe procedure.
"""

from __future__ import annotations

import logging
import os
import sys
from pathlib import Path

import firebase_admin
from firebase_admin import auth, credentials, firestore

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
logger = logging.getLogger("set_admin_claim")


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


def set_admin(identifier: str, *, grant: bool) -> None:
    auth_emulator = bool(os.getenv("FIREBASE_AUTH_EMULATOR_HOST"))
    firestore_emulator = bool(os.getenv("FIRESTORE_EMULATOR_HOST"))
    if not grant and auth_emulator != firestore_emulator:
        raise SystemExit("Revocation requires matching Auth and Firestore environments.")
    _init_app()
    if not grant and auth_emulator and firebase_admin.get_app().project_id != "demo-foreseeme":
        raise SystemExit("Emulator revocation requires demo-foreseeme.")
    uid = _resolve_uid(identifier)
    user = auth.get_user(uid)
    claims = dict(user.custom_claims or {})
    if grant:
        claims["admin"] = True
    else:
        claims.pop("admin", None)
    auth.set_custom_user_claims(uid, claims)
    if not grant:
        auth.revoke_refresh_tokens(uid)
        # Support running this script directly from the repository root.
        sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
        from app.session_revocation import record_revocation

        valid_after = auth.get_user(uid).tokens_valid_after_timestamp
        if firestore_emulator:
            from google.auth.credentials import AnonymousCredentials
            from google.cloud.firestore import Client

            db = Client(project="demo-foreseeme", credentials=AnonymousCredentials())
        else:
            db = firestore.client()
        record_revocation(db, uid, valid_after // 1000)
    action = "granted" if grant else "revoked"
    logger.info("Admin claim %s.", action)
    if grant:
        logger.info("The operator must sign in again with an enrolled factor.")
    else:
        logger.info("Refresh tokens revoked and Firestore session cutoff recorded.")


def main(argv: list[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    args = [a for a in argv if not a.startswith("--")]
    if len(args) != 1:
        logger.error(
            "usage: python backend/scripts/set_admin_claim.py <uid|email> [--revoke]"
        )
        return 2
    grant = "--revoke" not in argv
    set_admin(args[0], grant=grant)
    return 0


if __name__ == "__main__":
    sys.exit(main())
