"""Publish deployment evidence from the reviewed compute image after rollout."""
import argparse
import re

from google.auth.transport.requests import AuthorizedSession

from app.jobs.firestore_runtime import get_firestore_client
from app.predict import load_bundle, resolve_artifact_path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", required=True)
    parser.add_argument("--region", required=True)
    parser.add_argument("--job", required=True)
    parser.add_argument("--image", required=True)
    args = parser.parse_args()
    for value in (args.project, args.region, args.job):
        if not re.fullmatch(r"[a-z][a-z0-9-]{1,62}", value):
            parser.error("Invalid Cloud Run resource name")
    if not re.fullmatch(r"[a-z0-9./_-]+@sha256:[0-9a-f]{64}", args.image):
        parser.error("Provide the reviewed digest-pinned compute image")

    import firebase_admin
    from firebase_admin import firestore

    db = get_firestore_client()
    firebase_app = firebase_admin.get_app()
    if firebase_app.project_id != args.project:
        parser.error("Configured Firebase project must match the Cloud Run project")
    resource = f"projects/{args.project}/locations/{args.region}/jobs/{args.job}"
    with AuthorizedSession(firebase_app.credential.get_credential()) as session:
        response = session.get(f"https://run.googleapis.com/v2/{resource}", timeout=15)
        response.raise_for_status()
    job = response.json()
    containers = job["template"]["template"]["containers"]
    if (job.get("reconciling") or job.get("observedGeneration") != job.get("generation")
            or job.get("terminalCondition", {}).get("state") != "CONDITION_SUCCEEDED"
            or len(containers) != 1 or containers[0]["image"] != args.image
            or containers[0].get("command") != ["python"]
            or containers[0].get("args") != ["-m", "app.jobs.compute_risk"]):
        parser.error("Cloud Run job does not match the reviewed compute deployment")
    version = load_bundle(resolve_artifact_path())["model_version"]
    db.collection("operationalMetrics").document("deployedModel").set({
        "version": version, "verifiedAt": firestore.SERVER_TIMESTAMP,
        "source": "cloud_run_compute_job",
    }, timeout=10)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
