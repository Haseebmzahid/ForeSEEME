"""Coordinate account-wide logout across Firestore and Firebase Auth."""

import time
from uuid import uuid4

from firebase_admin import firestore

LEASE_SECONDS = 600


class LogoutRejected(Exception):
    pass


class LogoutUnconfirmed(Exception):
    pass


def record_revocation(db, uid: str, through_auth_time: int) -> None:
    ref = db.collection("sessionRevocations").document(uid)

    @firestore.transactional
    def record(transaction):
        existing = ref.get(transaction=transaction, timeout=5).to_dict() or {}
        through = max(through_auth_time, existing.get("throughAuthTime", 0))
        transaction.set(ref, {"throughAuthTime": through}, merge=True)

    record(db.transaction(max_attempts=3))


def complete_logout(db, uid, auth_time, *, may_start, read_valid_after, revoke):
    """Return only after both the cutoff and Firebase evidence are durable.

    The account document serializes Firebase mutations. Per-authentication
    receipts permit a retry without allowing a revoked bearer to start work.
    """
    account = db.collection("sessionRevocations").document(uid)
    receipt = account.collection("logoutIntents").document(str(auth_time))
    worker = uuid4().hex

    @firestore.transactional
    def prepare(transaction):
        state = account.get(transaction=transaction, timeout=5).to_dict() or {}
        intent = receipt.get(transaction=transaction, timeout=5).to_dict()
        cutoff = state.get("throughAuthTime", -1)
        now = time.time()
        if intent is None:
            if not may_start or auth_time <= cutoff or auth_time > int(now):
                raise LogoutRejected()
            target = int(now)
        else:
            target = intent["throughAuthTime"]
            if state.get("firebaseConfirmedThrough", -1) >= target:
                return None
        if state.get("logoutLeaseUntil", 0) > now:
            raise LogoutUnconfirmed()
        if intent is None:
            transaction.set(receipt, {
                "throughAuthTime": target, "createdAt": firestore.SERVER_TIMESTAMP,
            })
        transaction.set(account, {
            "throughAuthTime": max(cutoff, target),
            "logoutWorker": worker, "logoutLeaseUntil": now + LEASE_SECONDS,
        }, merge=True)
        return target

    @firestore.transactional
    def update_lease(transaction, valid_after=None):
        state = account.get(transaction=transaction, timeout=5).to_dict() or {}
        now = time.time()
        if state.get("logoutWorker") != worker or state["logoutLeaseUntil"] <= now:
            raise LogoutUnconfirmed()
        if valid_after is None:
            update = {"logoutLeaseUntil": now + LEASE_SECONDS}
        else:
            # Firebase uses whole seconds and the application cutoff is
            # inclusive. Only seconds strictly before validSince are proven.
            update = {
                "throughAuthTime": max(state["throughAuthTime"], valid_after - 1),
                "firebaseConfirmedThrough": max(
                    state.get("firebaseConfirmedThrough", -1), valid_after - 1,
                ),
                "logoutWorker": firestore.DELETE_FIELD,
                "logoutLeaseUntil": firestore.DELETE_FIELD,
            }
        transaction.set(account, update, merge=True)

    target = prepare(db.transaction(max_attempts=3))
    if target is None:
        return
    valid_after = read_valid_after() // 1000
    if valid_after <= target:
        # Same-second authentication must be invalidated by Firebase too.
        time.sleep(max(0, target + 1 - time.time()))
        update_lease(db.transaction(max_attempts=3))
        revoke()
        valid_after = read_valid_after() // 1000
    if valid_after <= target:
        raise LogoutUnconfirmed()
    update_lease(db.transaction(max_attempts=3), valid_after)
