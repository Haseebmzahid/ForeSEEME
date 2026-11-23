"""Aggregate Firebase Auth activity and optionally backfill the admin directory."""
from __future__ import annotations

import argparse
import logging
import os
from collections import Counter
from datetime import datetime, timedelta, timezone

from firebase_admin import auth, firestore
from google.cloud.firestore_v1.base_query import FieldFilter

from app.jobs.firestore_runtime import get_firestore_client

logger = logging.getLogger(__name__)
AUTH_SOURCE = "firebase_auth_sign_in_or_token_refresh"


def account_projection(user) -> dict:
    metadata = user.user_metadata
    return {
        "email": user.email or "",
        "createdAt": datetime.fromtimestamp(
            metadata.creation_timestamp / 1000, timezone.utc
        ).isoformat(),
        "authDisabled": user.disabled,
        **({"name": user.display_name} if user.display_name else {}),
    }


def configured_db():
    auth_emulator = bool(os.getenv("FIREBASE_AUTH_EMULATOR_HOST"))
    firestore_emulator = bool(os.getenv("FIRESTORE_EMULATOR_HOST"))
    if auth_emulator != firestore_emulator:
        raise RuntimeError("Auth and Firestore emulator modes must match")
    if auth_emulator and os.getenv("FIREBASE_PROJECT_ID") != "demo-foreseeme":
        raise RuntimeError("Account job emulators require demo-foreseeme")
    if not auth_emulator and not os.getenv("FIREBASE_PROJECT_ID"):
        raise RuntimeError("Set FIREBASE_PROJECT_ID explicitly")
    return get_firestore_client()


def account_metrics(users, now, days: int) -> dict:
    seen = set()
    active = 0
    cutoff = int((now - timedelta(days=days)).timestamp() * 1000)
    latest = int(now.timestamp() * 1000)
    for user in users:
        if user.uid in seen:
            continue
        seen.add(user.uid)
        metadata = user.user_metadata
        activity = max(metadata.last_sign_in_timestamp or 0, metadata.last_refresh_timestamp or 0)
        active += bool(not user.disabled and cutoff <= activity <= latest)
    return {
        "totalUsers": len(seen), "activeUsers": active, "measurementWindowDays": days,
        "generatedAt": now, "source": AUTH_SOURCE, "aggregationStatus": "ok",
    }


def backfill_record(db, user, *, apply: bool) -> str:
    ref = db.collection("userDirectory").document(user.uid)
    lock = db.collection("adminAccountOperations").document(user.uid)

    @firestore.transactional
    def sync(transaction):
        if lock.get(transaction=transaction, timeout=5).exists:
            return "skipped"
        previous = ref.get(transaction=transaction, timeout=5).to_dict() or {}
        updates = {
            key: value for key, value in account_projection(user).items()
            if not previous.get(key)
        }
        # Existing authoritative disabled state is maintained by the admin API.
        # A backfill may supply it to legacy records that did not have it.
        if "authDisabled" in previous:
            updates.pop("authDisabled", None)
        if previous.get("status") not in ("active", "pending"):
            profile = db.collection("users").document(user.uid).collection("profile").document(user.uid)
            # An empty field mask returns document existence, without profile fields.
            completed = profile.get(field_paths=[], transaction=transaction, timeout=5).exists
            updates["status"] = "active" if completed else "pending"
        updates = {key: value for key, value in updates.items() if previous.get(key) != value}
        if not updates:
            return "skipped"
        if apply:
            transaction.set(ref, updates, merge=True)
        return "updated" if apply else "would_update"

    return sync(db.transaction(max_attempts=3, read_only=not apply))


def backfill(db, users, apply: bool) -> Counter:
    counts = Counter()
    for user in users:
        try:
            counts[backfill_record(db, user, apply=apply)] += 1
        except Exception as exc:
            counts["failed"] += 1
            logger.error("Directory projection failed (%s)", type(exc).__name__)
    return counts


def publish_metric(db, name, now, build):
    ref = db.collection("operationalMetrics").document(name)

    @firestore.transactional
    def publish(transaction, fields):
        previous = ref.get(transaction=transaction, timeout=5).to_dict() or {}
        if previous.get("lastAttemptAt", datetime.min.replace(tzinfo=timezone.utc)) <= now:
            transaction.set(ref, {**fields, "lastAttemptAt": now}, merge=True)

    try:
        data = build()
    except Exception:
        publish(db.transaction(max_attempts=3), {"aggregationStatus": "failed"})
        raise
    publish(db.transaction(max_attempts=3), data)


def run_aggregation(db, days: int) -> bool:
    now = datetime.now(timezone.utc)

    def alert_metrics():
        result = (db.collection("alertDispatchLog")
                  .where(filter=FieldFilter("status", "==", "sent")).count().get(timeout=30))
        return {
            "totalAlerts": result[0][0].value, "generatedAt": now,
            "source": "alertDispatchLog.sent", "aggregationStatus": "ok",
        }

    ok = True
    for name, build in (
        ("accounts", lambda: account_metrics(auth.list_users().iterate_all(), now, days)),
        ("alerts", alert_metrics),
    ):
        try:
            publish_metric(db, name, now, build)
        except Exception as exc:
            logger.error("Metric aggregation failed (%s, %s)", name, type(exc).__name__)
            ok = False
    return ok


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--backfill", action="store_true", help="Preview directory backfill")
    parser.add_argument("--apply", action="store_true", help="Apply directory backfill")
    args = parser.parse_args()
    if args.apply and not args.backfill:
        parser.error("--apply requires --backfill")
    days = int(os.getenv("ADMIN_ACTIVITY_WINDOW_DAYS", "30"))
    if not 1 <= days <= 365:
        parser.error("ADMIN_ACTIVITY_WINDOW_DAYS must be between 1 and 365")
    logging.basicConfig(level=logging.INFO)
    db = configured_db()
    if args.backfill:
        counts = backfill(db, auth.list_users().iterate_all(), args.apply)
        print({key: counts[key] for key in ("updated", "would_update", "skipped", "failed")})
        return int(counts["failed"] > 0)
    return int(not run_aggregation(db, days))


if __name__ == "__main__":
    raise SystemExit(main())
