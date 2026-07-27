"""Manual, billing-free verification of the alert dispatch pipeline (M7.2).

Exercises the REAL Firestore read/write path (`FirestoreRiskHistoryProvider`,
`FirestoreUserDirectory`, `FirestoreDispatchRepository`) and the real targeting
predicate against the Firestore emulator — everything `dispatch_alerts.run()`
does except the actual outbound FCM network call, which needs a live,
credentialed Firebase project. That one seam is swapped for a
`RecordingFcmSender` so the exact payload FCM *would* receive can be inspected
without sending anything.

This is the local, emulator-based counterpart to
`backend/deploy/verify_dispatch_alerts.sh`, which needs `gcloud` + billing
enabled and is intentionally left unrun until then (see that script's
README). Use this one any time you want to confirm the dispatch pipeline
still works end-to-end without touching the live project.

Run (from `backend/`), against the Firestore emulator:

    firebase emulators:exec --only firestore --project demo-foreseeme \\
        "python scripts/verify_dispatch_pipeline.py"

Or, with an emulator already running (`firebase emulators:start --only firestore`):

    FIRESTORE_EMULATOR_HOST=localhost:8080 python scripts/verify_dispatch_pipeline.py

Exits 0 and prints "ALL CHECKS PASSED" iff every assertion below holds; exits
1 and prints the first failure otherwise. Never touches a real FCM token or
FCM project.
"""

from __future__ import annotations

import os
import sys
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from app.jobs import dispatch_alerts as da  # noqa: E402
from app.jobs.alerting.messaging import FcmSender, SendResult  # noqa: E402

CITY = "Lahore"
UID = "verify-m72-user"
TODAY = datetime(2026, 7, 24, tzinfo=timezone.utc)
YESTERDAY = TODAY - timedelta(days=1)


class RecordingFcmSender(FcmSender):
    """Captures the payload instead of calling FCM. Never touches the network."""

    def __init__(self) -> None:
        self.calls: list[dict] = []

    def send(self, *, token, title, body, data) -> SendResult:
        self.calls.append({"token": token, "title": title, "body": body, "data": data})
        return SendResult(status="sent", message_id=f"verify-{len(self.calls)}")


def _fail(msg: str) -> None:
    print(f"FAIL: {msg}")
    sys.exit(1)


def _ok(msg: str) -> None:
    print(f"ok   {msg}")


def seed(db) -> None:
    """A risk transition (Medium -> High Smog) plus one matching, consenting user."""
    risk = db.collection("riskEstimates")
    risk.document(f"{CITY}_2026-07-23").set(
        {
            "city": CITY,
            "riskLevel": "Medium",
            "disease": "Smog",
            "generatedAt": YESTERDAY.isoformat(),
            "modelVersion": "verify-0.0.0",
        }
    )
    risk.document(f"{CITY}_2026-07-24").set(
        {
            "city": CITY,
            "riskLevel": "High",
            "disease": "Smog",
            "generatedAt": TODAY.isoformat(),
            "modelVersion": "verify-0.0.0",
        }
    )

    users = db.collection("users")
    users.document(UID).set(
        {
            "fcmToken": "verify-fake-token-not-a-real-device",
            "notificationPreferences": {
                "highRiskAlerts": True,
                "mediumRiskAlerts": True,
                "lowRiskUpdates": False,
                "conditions": {"respiratory": True, "cardiovascular": False},
            },
        }
    )
    users.document(UID).collection("profile").document(UID).set(
        {"city": CITY, "chronicConditions": ["Asthma"]}
    )
    print(f"seeded: {CITY} Medium->High Smog transition; user {UID} (Asthma, respiratory-consented)")


def cleanup(db) -> None:
    """Best-effort teardown so re-runs start clean (emulator state is ephemeral anyway)."""
    for doc_id in (f"{CITY}_2026-07-23", f"{CITY}_2026-07-24"):
        db.collection("riskEstimates").document(doc_id).delete()
    db.collection("users").document(UID).collection("profile").document(UID).delete()
    db.collection("users").document(UID).delete()
    log_id = da.dispatch_key(UID, f"{CITY}_2026-07-24", "respiratory")
    db.collection("alertDispatchLog").document(log_id).delete()
    (
        db.collection("userAlerts")
        .document(UID)
        .collection("items")
        .document(log_id)
        .delete()
    )


def main() -> int:
    db = da.init_firestore()
    cleanup(db)  # in case a prior interrupted run left state behind
    seed(db)

    history = da.FirestoreRiskHistoryProvider(db)
    directory = da.FirestoreUserDirectory(db)
    repository = da.FirestoreDispatchRepository(db)
    cities = [{"name": CITY}]

    # --- Run 1: should target the seeded user and dispatch -------------------
    sender = RecordingFcmSender()
    outcomes = da.run(
        history=history, directory=directory, sender=sender,
        repository=repository, cities=cities, now=TODAY,
    )
    print(f"\nrun 1: {len(outcomes)} outcome(s)")
    for o in outcomes:
        print(f"  {o.city:8} {o.uid:20} {o.category:12} {o.status}")

    ours = [o for o in outcomes if o.uid == UID]
    if len(ours) != 1:
        _fail(f"expected exactly 1 outcome for {UID}, got {len(ours)}")
    outcome = ours[0]
    if outcome.status != "sent":
        _fail(f"expected status 'sent', got {outcome.status!r}")
    _ok("targeting predicate fired for the seeded (risk transition + Asthma + consent) user")

    # --- FCM payload generation -----------------------------------------------
    if len(sender.calls) != 1:
        _fail(f"expected exactly 1 FCM send, got {len(sender.calls)}")
    call = sender.calls[0]
    print(f"\nFCM payload that would be sent:\n  title: {call['title']!r}\n  body:  {call['body']!r}\n  data:  {call['data']!r}")
    if call["token"] != "verify-fake-token-not-a-real-device":
        _fail("payload targeted the wrong token")
    if CITY not in call["title"]:
        _fail(f"title does not mention the city: {call['title']!r}")
    if "High" not in call["body"] or "Smog" not in call["body"]:
        _fail(f"body does not mention risk level/disease: {call['body']!r}")
    expected_data_keys = {"type", "deepLink", "category", "city", "riskLevel", "riskEstimateId"}
    if set(call["data"].keys()) != expected_data_keys:
        _fail(f"data keys mismatch: {set(call['data'].keys())} != {expected_data_keys}")
    if not all(isinstance(v, str) for v in call["data"].values()):
        _fail("data values must all be strings (FCM requirement)")
    _ok("FCM payload well-formed: city in title, risk level + disease in body, data keys match the contract, all-string values")

    # --- Firestore writes -------------------------------------------------------
    log_id = da.dispatch_key(UID, f"{CITY}_2026-07-24", "respiratory")
    log_doc = db.collection("alertDispatchLog").document(log_id).get()
    if not log_doc.exists:
        _fail(f"alertDispatchLog/{log_id} was not written")
    log_body = log_doc.to_dict()
    if log_body.get("status") != "sent":
        _fail(f"alertDispatchLog status expected 'sent', got {log_body.get('status')!r}")
    _ok(f"alertDispatchLog/{log_id} written with status='sent'")

    alert_doc = (
        db.collection("userAlerts").document(UID).collection("items").document(log_id).get()
    )
    if not alert_doc.exists:
        _fail(f"userAlerts/{UID}/items/{log_id} was not written")
    alert_body = alert_doc.to_dict()
    _ok(f"userAlerts/{UID}/items/{log_id} written (in-app inbox doc)")

    # Cross-check against the exact field set lib/features/alerts/domain/models/
    # user_alert.dart's UserAlertModel.fromJson reads.
    expected_alert_fields = {
        "title", "body", "category", "city", "riskLevel", "disease",
        "recommendation", "deepLink", "riskEstimateId", "createdAt", "read", "readAt",
    }
    if set(alert_body.keys()) != expected_alert_fields:
        _fail(
            f"userAlerts doc field set does not match UserAlertModel.fromJson: "
            f"{set(alert_body.keys())} != {expected_alert_fields}"
        )
    if alert_body["read"] is not False or alert_body["readAt"] is not None:
        _fail("a freshly dispatched alert must start unread")
    rec = alert_body.get("recommendation") or {}
    if not rec.get("source") or not rec.get("sourceUrl", "").startswith("https://"):
        _fail(f"recommendation is not cited: {rec}")
    _ok("userAlerts doc field set matches lib/.../user_alert.dart's UserAlertModel exactly; starts unread; recommendation is cited")

    # --- Run 2: idempotency — must NOT re-send or duplicate-write --------------
    sender2 = RecordingFcmSender()
    outcomes2 = da.run(
        history=history, directory=directory, sender=sender2,
        repository=repository, cities=cities, now=TODAY,
    )
    ours2 = [o for o in outcomes2 if o.uid == UID]
    print(f"\nrun 2 (immediate re-run, same estimate): {[o.status for o in ours2]}")
    if len(ours2) != 1 or ours2[0].status != "skipped_idempotent":
        _fail(f"re-run should be skipped_idempotent, got {[o.status for o in ours2]}")
    if sender2.calls:
        _fail("re-run must not call FCM again")
    _ok("re-run against the same estimate is skipped_idempotent — no duplicate send, no duplicate write")

    print("\nALL CHECKS PASSED")
    cleanup(db)
    return 0


if __name__ == "__main__":
    sys.exit(main())
