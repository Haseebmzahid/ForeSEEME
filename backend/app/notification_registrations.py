"""Server-owned FCM registrations and transactional ownership checks."""

from dataclasses import dataclass, field
from hashlib import sha256
from uuid import uuid4

from firebase_admin import firestore
from google.cloud.firestore_v1.base_query import FieldFilter

COLLECTION = "notificationRegistrations"


def registration_id(token: str) -> str:
    return sha256(token.encode("utf-8")).hexdigest()


@dataclass(frozen=True)
class Registration:
    uid: str
    token: str = field(repr=False)
    auth_time: int
    generation: str


class RegistrationConflict(Exception):
    pass


class InactiveSession(Exception):
    pass


class RegistrationStore:
    def __init__(self, db):
        self._db = db

    def _reference(self, token):
        return self._db.collection(COLLECTION).document(registration_id(token))

    def _cutoff(self, uid, *, transaction=None):
        snapshot = self._db.collection("sessionRevocations").document(uid).get(
            transaction=transaction, timeout=5,
        )
        return snapshot.to_dict()["throughAuthTime"] if snapshot.exists else -1

    def register(self, uid: str, auth_time: int, token: str, previous_token=None):
        ref = self._reference(token)
        previous = (
            self._reference(previous_token)
            if previous_token and previous_token != token else None
        )
        generation = uuid4().hex

        @firestore.transactional
        def apply(transaction):
            if auth_time <= self._cutoff(uid, transaction=transaction):
                raise InactiveSession()
            current = ref.get(transaction=transaction, timeout=5).to_dict() or {}
            if current and (
                auth_time < current["authTime"] or
                (auth_time == current["authTime"] and
                 (uid != current["uid"] or current.get("token") != token))
            ):
                raise RegistrationConflict()
            prior = previous.get(transaction=transaction, timeout=5).to_dict() if previous else None
            user_ref = self._db.collection("users").document(uid)
            user_exists = user_ref.get(transaction=transaction, timeout=5).exists
            if not user_exists:
                transaction.set(user_ref, {})
            if not current or auth_time > current["authTime"]:
                transaction.set(ref, {
                    "uid": uid, "token": token, "authTime": auth_time,
                    "generation": generation, "updatedAt": firestore.SERVER_TIMESTAMP,
                })
            if previous and (not prior or self._owned(prior, uid, auth_time)):
                self._retire(transaction, previous, uid, auth_time)

        apply(self._db.transaction(max_attempts=3))

    @staticmethod
    def _owned(data, uid, auth_time):
        return data.get("uid") == uid and data.get("authTime") == auth_time

    @staticmethod
    def _retire(transaction, ref, uid, auth_time):
        # Keep ordering evidence without retaining a retired raw token.
        transaction.set(ref, {
            "uid": uid, "authTime": auth_time, "updatedAt": firestore.SERVER_TIMESTAMP,
        })

    def unregister(self, uid: str, auth_time: int, token: str):
        ref = self._reference(token)

        @firestore.transactional
        def apply(transaction):
            if auth_time <= self._cutoff(uid, transaction=transaction):
                raise InactiveSession()
            current = ref.get(transaction=transaction, timeout=5).to_dict() or {}
            if not current or (self._owned(current, uid, auth_time) and current.get("token") == token):
                self._retire(transaction, ref, uid, auth_time)

        apply(self._db.transaction(max_attempts=3))

    @staticmethod
    def _matches(data, registration):
        return (
            data.get("uid") == registration.uid and
            data.get("token") == registration.token and
            data.get("authTime") == registration.auth_time and
            data.get("generation") == registration.generation
        )

    def for_user(self, uid: str) -> tuple[Registration, ...]:
        cutoff = self._cutoff(uid)
        registrations = []
        for snapshot in self._db.collection(COLLECTION).where(
            filter=FieldFilter("uid", "==", uid),
        ).stream(timeout=10):
            data = snapshot.to_dict() or {}
            token, auth_time, generation = (
                data.get("token"), data.get("authTime"), data.get("generation"),
            )
            if (isinstance(token, str) and token and type(auth_time) is int
                    and auth_time > cutoff and isinstance(generation, str)
                    and snapshot.id == registration_id(token)):
                registrations.append(Registration(uid, token, auth_time, generation))
        return tuple(registrations)

    def is_current(self, registration: Registration) -> bool:
        current = self._reference(registration.token).get(timeout=5).to_dict() or {}
        return (
            self._matches(current, registration) and
            registration.auth_time > self._cutoff(registration.uid)
        )

    def prune(self, registration: Registration) -> bool:
        ref = self._reference(registration.token)

        @firestore.transactional
        def apply(transaction):
            current = ref.get(transaction=transaction, timeout=5).to_dict() or {}
            if not self._matches(current, registration):
                return False
            self._retire(transaction, ref, registration.uid, registration.auth_time)
            return True

        return apply(self._db.transaction(max_attempts=3))
