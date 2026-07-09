"""Ops helper (Phase 2 verification): inspect dispatch_alerts' audit trail.

`alertDispatchLog` and `userAlerts` are service/owner-only collections
(firestore.rules denies unrelated client reads), so there is no simple
console query for an operator checking a verification run. This reads them
via the same Admin SDK path the job already uses, authenticated with your own
gcloud user credentials (Application Default Credentials).

Usage:
    gcloud auth application-default login   # once, if not already done

    # Most recent dispatch attempts (any user/city):
    python backend/deploy/read_dispatch_audit.py --project foreseeme-83587 log

    # A specific user's in-app inbox (Notification Center) items:
    python backend/deploy/read_dispatch_audit.py --project foreseeme-83587 inbox --uid <uid>
"""

from __future__ import annotations

import argparse


def _print_doc(doc) -> None:
    body = doc.to_dict() or {}
    print(f"-- {doc.id} --")
    for key, value in body.items():
        print(f"  {key:18} {value}")
    print()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", required=True, help="Firebase/GCP project id")
    parser.add_argument("--limit", type=int, default=10, help="Max docs to show (default 10)")
    sub = parser.add_subparsers(dest="mode", required=True)

    sub.add_parser("log", help="Most recent alertDispatchLog entries (any user)")

    inbox = sub.add_parser("inbox", help="A user's userAlerts/{uid}/items (Notification Center)")
    inbox.add_argument("--uid", required=True)

    args = parser.parse_args()

    import firebase_admin
    from firebase_admin import firestore

    if not firebase_admin._apps:
        firebase_admin.initialize_app(options={"projectId": args.project})
    db = firestore.client()

    if args.mode == "log":
        docs = (
            db.collection("alertDispatchLog")
            .order_by("createdAt", direction=firestore.Query.DESCENDING)
            .limit(args.limit)
            .stream()
        )
        count = 0
        for doc in docs:
            _print_doc(doc)
            count += 1
        print(f"{count} alertDispatchLog document(s) shown (limit={args.limit}).")
        return 0 if count > 0 else 1

    if args.mode == "inbox":
        docs = (
            db.collection("userAlerts")
            .document(args.uid)
            .collection("items")
            .order_by("createdAt", direction=firestore.Query.DESCENDING)
            .limit(args.limit)
            .stream()
        )
        count = 0
        for doc in docs:
            _print_doc(doc)
            count += 1
        print(f"{count} userAlerts/{args.uid}/items document(s) shown (limit={args.limit}).")
        return 0 if count > 0 else 1

    return 1


if __name__ == "__main__":
    import sys

    sys.exit(main())
