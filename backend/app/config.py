"""Runtime configuration for the ForeSeeMe risk service.

All configuration comes from environment variables ONLY (GOLDEN_RULES #7: no
secrets or hardcoded paths in source). Defaults are safe, non-secret values
suitable for local development; see ``.env.example`` for the full list.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from functools import lru_cache

# Default model version stamped onto responses by the placeholder stub model.
# Overridable via the MODEL_VERSION env var; never a secret.
_DEFAULT_MODEL_VERSION = "stub-0.0.0"


@dataclass(frozen=True)
class Settings:
    """Immutable, environment-derived service settings.

    Attributes:
        model_version: Fallback version string for the stub model (used when no
            real artifact is loaded). The real model reports its own version.
        log_level: Root log level name (e.g. ``"INFO"``, ``"DEBUG"``).
        model_artifact_path: Optional explicit path to ``model_<version>.joblib``.
            When unset, the load path discovers the latest local artifact under
            ``backend/ml/artifacts/``. Lets tests point at a missing/alternate
            artifact to exercise graceful degradation.
    """

    model_version: str
    log_level: str
    model_artifact_path: str | None = None


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Build :class:`Settings` from the environment.

    Cached so the same instance is reused across requests. The cache can be
    cleared in tests with ``get_settings.cache_clear()``.
    """
    return Settings(
        model_version=os.getenv("MODEL_VERSION", _DEFAULT_MODEL_VERSION),
        log_level=os.getenv("LOG_LEVEL", "INFO"),
        model_artifact_path=os.getenv("MODEL_ARTIFACT_PATH"),
    )
