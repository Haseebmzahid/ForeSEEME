"""Ops helper (Phase 1 verification): print jobHeartbeats/compute_risk.

`jobHeartbeats` is service-only (firestore.rules denies all client read/write),
so there is no in-app or console-simple way to inspect it. This script reads it
via the same Admin SDK path the jobs already use, authenticated with your own
gcloud user credentials (Application Default Credentials) rather than the
service account -- for a human operator checking after a manual verification
run, not for use by any job or the app.

Usage:
    gcloud auth application-default login   # once, if not already done
    python backend/deploy/read_heartbeat.py --project foreseeme-83587
    python backend/deploy/read_heartbeat.py --project foreseeme-83587 --job compute_risk
"""

from __future__ import annotations

import argparse
import json


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", required=True, help="Firebase/GCP project id")
    parser.add_argument(
        "--job", default="compute_risk",
        help="Job name / heartbeat doc id (default: compute_risk)",
    )
    args = parser.parse_args()

    import firebase_admin
    from firebase_admin import firestore

    if not firebase_admin._apps:
        firebase_admin.initialize_app(options={"projectId": args.project})

    doc = firestore.client().collection("jobHeartbeats").document(args.job).get()
    if not doc.exists:
        print(f"No jobHeartbeats/{args.job} document found yet.")
        return 1

    body = doc.to_dict() or {}
    for key in ("job", "status", "ok", "startedAt", "finishedAt", "durationMs",
                "total", "counts", "error"):
        if key in body:
            print(f"{key:12} {body[key]}")
    print()
    print(json.dumps(body, default=str, indent=2))
    return 0 if body.get("status") == "ok" else 1


if __name__ == "__main__":
    import sys

    sys.exit(main())
