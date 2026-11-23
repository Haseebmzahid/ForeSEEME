"""Reconcile a reserved account operation after privileged writers are drained.

Run from backend with python -m scripts.reconcile_admin_account. Never repeats
a destructive Auth action. The final event records the state observed now.
"""
import argparse
import hashlib
import re

from firebase_admin import auth, firestore

from app.admin_api import audit, valid_key
from app.jobs.account_metrics import account_projection, configured_db


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("uid")
    parser.add_argument("request_id")
    parser.add_argument("--writers-drained", action="store_true", required=True)
    args = parser.parse_args()
    if not args.uid or len(args.uid) > 128 or "/" in args.uid:
        parser.error("Invalid Firebase UID")
    valid_key(args.uid)
    if not re.fullmatch(r"[a-f0-9]{32}", args.request_id):
        parser.error("Invalid request ID")
    db = configured_db()
    lock = db.collection("adminAccountOperations").document(args.uid)
    directory = db.collection("userDirectory").document(args.uid)
    reservation = lock.get(timeout=5).to_dict() or {}
    if reservation.get("requestId") != args.request_id or reservation.get("deleted"):
        parser.error("No pending reservation for the supplied request")
    try:
        account = auth.get_user(args.uid)
    except auth.UserNotFoundError:
        account = None

    if reservation.get("invitationKey"):
        return reconcile_invitation(db, lock, directory, reservation, account)
    action = reservation["action"]
    if action == "user_suspend" and account is not None and account.disabled:
        # Complete session revocation before recording confirmed suspension.
        auth.revoke_refresh_tokens(args.uid)
    achieved = (account is None if action == "user_delete"
                else account is not None and account.disabled == (action == "user_suspend"))
    actor = {"uid": reservation["authorUid"], "email": reservation["authorEmail"]}
    event_ref, event = audit(
        db, actor, action, args.uid, args.request_id,
        "reconciled_success" if achieved else "reconciled_failure",
        "Account state verified during operator reconciliation",
    )

    @firestore.transactional
    def finalize(transaction):
        if lock.get(transaction=transaction, timeout=5).to_dict() != reservation:
            raise ValueError("Reservation changed")
        if account is None:
            transaction.delete(directory)
            transaction.set(lock, {"deleted": True, "requestId": args.request_id})
        else:
            projection = account_projection(account)
            projection.pop("name", None)
            transaction.set(directory, projection, merge=True)
            transaction.delete(lock)
        transaction.create(event_ref, event)

    finalize(db.transaction(max_attempts=3))
    print("Reconciliation recorded:", "confirmed" if achieved else "desired state absent")
    return 0 if achieved else 1


def reconcile_invitation(db, lock, directory, reservation, account):
    key = reservation["invitationKey"]
    request_id = reservation["requestId"]
    actor = {"uid": reservation["authorUid"], "email": reservation["authorEmail"]}
    invite = (db.collection("adminAccountOperations").document("invitations")
              .collection("requests").document(key))
    if account is not None and (
        not account.email or hashlib.sha256(account.email.lower().encode()).hexdigest() != key
        or account.disabled or (account.custom_claims or {}).get("admin")
    ):
        raise ValueError("Observed account is no longer eligible for the invitation")

    ref, event = audit(
        db, actor, "user_provision", lock.id, request_id, "reconciled",
        "Invitation cleared; no account observed" if account is None
        else "Account verified; invitation can be requested again",
    )

    @firestore.transactional
    def finalize(transaction):
        current = (invite.get(transaction=transaction, timeout=5).to_dict() or {})
        if (lock.get(transaction=transaction, timeout=5).to_dict() != reservation
                or current.get("requestId") != request_id or current.get("uid") != lock.id):
            raise ValueError("Invitation reservation changed")
        if account is None:
            transaction.delete(invite)
        else:
            projection = account_projection(account)
            projection.pop("name", None)
            transaction.set(directory, projection, merge=True)
            transaction.update(invite, {"state": "retry"})
        transaction.delete(lock)
        transaction.create(ref, event)

    finalize(db.transaction(max_attempts=3))
    print("Invitation reservation reconciled.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
