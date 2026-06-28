"""Central filesystem-path resolution for the ForeSeeMe ML pipelines.

Single source of truth for every directory the data pipelines read or write.
No other pipeline module may hardcode a data/config/report path — it imports
from here (Prompt 2 constraint: "no string literals elsewhere").

Roots are overridable via environment variables so the pipelines can run against
a scratch location in tests/CI without code changes; defaults are safe and
repo-relative. No secrets live here.

Env overrides (all optional):
    FORESEEME_ML_DATA_DIR    -> base for data/{raw,interim,processed}
    FORESEEME_ML_CONFIG_DIR  -> base for the *.yaml config files
    FORESEEME_ML_REPORTS_DIR -> base for generated reports

Layout (defaults)::

    backend/ml/
      config/   cities.yaml  sources.yaml  pipeline.yaml
      data/
        raw/        <bulk blobs, git-ignored>  manifest.json (committed)
        interim/    <git-ignored>
        processed/  <git-ignored>
      reports/
"""

from __future__ import annotations

import os
import re
from pathlib import Path

#: ``backend/ml`` — this file lives in ``backend/ml/pipelines/``.
ML_ROOT = Path(__file__).resolve().parents[1]


def _dir_from_env(var: str, default: Path) -> Path:
    """Resolve a directory from an env override, else the repo-relative default."""
    raw = os.getenv(var)
    return Path(raw).expanduser().resolve() if raw else default


# --- Roots (env-overridable) -----------------------------------------------

CONFIG_DIR = _dir_from_env("FORESEEME_ML_CONFIG_DIR", ML_ROOT / "config")
DATA_DIR = _dir_from_env("FORESEEME_ML_DATA_DIR", ML_ROOT / "data")
REPORTS_DIR = _dir_from_env("FORESEEME_ML_REPORTS_DIR", ML_ROOT / "reports")

# --- Data sub-directories ---------------------------------------------------

RAW_DIR = DATA_DIR / "raw"
INTERIM_DIR = DATA_DIR / "interim"
PROCESSED_DIR = DATA_DIR / "processed"

#: The committed provenance manifest (everything else under raw/ is git-ignored).
MANIFEST_PATH = RAW_DIR / "manifest.json"

# --- Config files -----------------------------------------------------------

CITIES_PATH = CONFIG_DIR / "cities.yaml"
SOURCES_PATH = CONFIG_DIR / "sources.yaml"
PIPELINE_PATH = CONFIG_DIR / "pipeline.yaml"


# --- Helpers ----------------------------------------------------------------

_UNSAFE = re.compile(r"[^A-Za-z0-9._-]+")


def slug(token: object) -> str:
    """Filesystem-safe token: collapse anything unusual to ``-``."""
    return _UNSAFE.sub("-", str(token)).strip("-")


def _window_bounds(window: object) -> tuple[str, str]:
    """Pull (start, end) from a dict, a (start, end) pair, or a ``.start/.end`` obj."""
    if isinstance(window, dict):
        return str(window["start"]), str(window["end"])
    if isinstance(window, (tuple, list)):
        return str(window[0]), str(window[1])
    return str(window.start), str(window.end)  # type: ignore[attr-defined]


def raw_relpath(source: str, city: str, window: object, ext: str = "json") -> str:
    """Stable POSIX-relative path (under ``data/``) for one (source, city, window).

    Deterministic, so re-running acquisition resolves to the same file and the
    manifest key is portable across machines. Example::

        raw/open_meteo_weather__Lahore__2022-08-05_2026-06-28.json
    """
    start, end = _window_bounds(window)
    name = f"{slug(source)}__{slug(city)}__{slug(start)}_{slug(end)}.{ext}"
    return f"raw/{name}"


def raw_path(
    source: str,
    city: str,
    window: object,
    ext: str = "json",
    data_dir: Path | None = None,
) -> Path:
    """Absolute raw-file path, rooted at ``data_dir`` (defaults to :data:`DATA_DIR`)."""
    base = data_dir if data_dir is not None else DATA_DIR
    return base / raw_relpath(source, city, window, ext)


def ensure_dir(path: Path) -> Path:
    """Create ``path`` (and parents) if missing; return it."""
    path.mkdir(parents=True, exist_ok=True)
    return path
