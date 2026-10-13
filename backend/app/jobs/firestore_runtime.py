"""Guard compute-risk's Firebase app/client against configuration changes.

Only apps initialized here have known endpoint/credential provenance. Unknown
default apps must be removed by their owner or used in a separate process.
"""

import os
from pathlib import Path
from threading import RLock

_lock = RLock()
_apps = {}  # id -> (app, configuration, credential); retain app to avoid id reuse.


def _file_signature(path):
    if not path:
        return None
    resolved = Path(path).expanduser().resolve()
    try:
        stat = resolved.stat()
        return (str(resolved), stat.st_mtime_ns, stat.st_size)
    except FileNotFoundError:
        return (str(resolved), None, None)


def _configuration():
    projects = {os.getenv(key) for key in
                ("FIREBASE_PROJECT_ID", "GCLOUD_PROJECT", "GOOGLE_CLOUD_PROJECT")
                if os.getenv(key)}
    if len(projects) > 1:
        raise ValueError("Conflicting Firebase/Google Cloud project settings")
    emulator = os.getenv("FIRESTORE_EMULATOR_HOST") or None
    project = next(iter(projects), None) or ("demo-foreseeme" if emulator else None)
    mode = os.getenv("FIRESTORE_AUTH_MODE", "adc")
    if mode not in {"adc", "attached", "emulator"}:
        raise ValueError("Invalid FIRESTORE_AUTH_MODE")
    if mode == "attached" and (not project or emulator or os.getenv("GOOGLE_APPLICATION_CREDENTIALS")):
        raise ValueError("Attached identity requires explicit project and no emulator or credential file")
    if mode == "emulator" and not emulator:
        raise ValueError("Emulator authentication requires FIRESTORE_EMULATOR_HOST")
    if emulator:
        return (project, emulator, None)
    # Inspect metadata only, never read or log credential contents.
    from google.auth import _cloud_sdk

    identity = (
        _file_signature(os.getenv("GOOGLE_APPLICATION_CREDENTIALS")),
        _file_signature(_cloud_sdk.get_application_default_credentials_path()),
        os.getenv("GOOGLE_CLOUD_QUOTA_PROJECT"),
    )
    return (project, None, identity)


def get_firestore_client():
    """Return a compatible client or fail before any Firestore operation."""
    import firebase_admin
    from firebase_admin import credentials, firestore

    with _lock:
        config = _configuration()
        project, emulator, _identity = config
        try:
            app = firebase_admin.get_app()
        except ValueError:
            if emulator:
                class EmulatorCredential(credentials.Base):
                    def get_credential(self):
                        from google.auth.credentials import AnonymousCredentials

                        return AnonymousCredentials()

                credential = EmulatorCredential()
            else:
                credential = credentials.ApplicationDefault()
            app = firebase_admin.initialize_app(
                credential, options={"projectId": project} if project else None,
            )
            # Resolve ADC and construct the client before registering safe reuse.
            db = firestore.client(app=app)
            _apps[id(app)] = (app, config, app.credential)
            return db
        record = _apps.get(id(app))
        if record is None:
            raise ValueError("Firebase default app has unknown Firestore configuration; use a fresh process")
        if project and app.project_id != project:
            raise ValueError("Existing Firebase default app does not match configured project")
        if record[1] != config or record[2] is not app.credential:
            raise ValueError("Firebase endpoint or credential configuration changed; use a fresh process")
        return firestore.client(app=app)
