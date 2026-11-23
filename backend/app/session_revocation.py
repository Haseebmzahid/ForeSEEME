"""Persist the Firebase Auth revocation boundary for Firestore clients."""

from firebase_admin import firestore


def record_revocation(db, uid: str, through_auth_time: int) -> None:
    ref = db.collection("sessionRevocations").document(uid)

    @firestore.transactional
    def record(transaction):
        existing = ref.get(transaction=transaction, timeout=5).to_dict() or {}
        through = max(through_auth_time, existing.get("throughAuthTime", 0))
        transaction.set(ref, {"throughAuthTime": through})

    record(db.transaction(max_attempts=3))
