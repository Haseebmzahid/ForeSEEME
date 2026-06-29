"""Central filesystem-path resolution for the ForeSeeMe ML pipelines.

Single source of truth for every directory the data pipelines read or write.
No other pipeline module may hardcode a data/config/report path — it imports
from here (Prompt 2 constraint: "no string literals elsewhere").

Roots are overridable via environment variables so the pipelines can run against
a scratch location in tests/CI without code changes; defaults are safe and
repo-relative. No secrets live here.

Env overrides (all optional):
    FORESEEME_ML_DATA_DIR      -> base for data/{raw,interim,processed}
    FORESEEME_ML_CONFIG_DIR    -> base for the *.yaml config files
    FORESEEME_ML_REPORTS_DIR   -> base for generated reports
    FORESEEME_ML_ARTIFACTS_DIR -> base for trained-model artifacts (Phase C)

Layout (defaults)::

    backend/ml/
      config/   cities.yaml  sources.yaml  pipeline.yaml  model.yaml
      data/
        raw/        <bulk blobs, git-ignored>  manifest.json (committed)
        interim/    <git-ignored>
        processed/  <git-ignored>
      artifacts/  candidate_model.joblib  metrics.json  feature_importance.csv  plots/
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
ARTIFACTS_DIR = _dir_from_env("FORESEEME_ML_ARTIFACTS_DIR", ML_ROOT / "artifacts")

# --- Data sub-directories ---------------------------------------------------

RAW_DIR = DATA_DIR / "raw"
INTERIM_DIR = DATA_DIR / "interim"
PROCESSED_DIR = DATA_DIR / "processed"

#: The committed provenance manifest (everything else under raw/ is git-ignored).
MANIFEST_PATH = RAW_DIR / "manifest.json"

#: VALIDATION_ONLY disease-seasonality reference (Prompt 5). Path-only constant so
#: evaluation (Prompt 12) can read the committed JSON yardstick directly. NOTE: the
#: Python loader in ``acquire_disease_reference`` guards against import by any
#: module named ``*feature*``/``*label*``/``*train*`` — and ``ml.training.evaluate``
#: trips that substring heuristic — so the reference is consumed here as a data
#: file (its sanctioned validation use), never as a model input.
DISEASE_REFERENCE_DIR = RAW_DIR / "disease_reference"
SEASONALITY_REFERENCE_PATH = DISEASE_REFERENCE_DIR / "seasonality.json"

#: Frozen modeling datasets (Prompt 10). Training reads ``train.parquet`` ONLY;
#: ``test.parquet`` is untouched until evaluation (Prompt 12).
TRAIN_PATH = PROCESSED_DIR / "train.parquet"
TEST_PATH = PROCESSED_DIR / "test.parquet"
SPLIT_MANIFEST_PATH = PROCESSED_DIR / "split_manifest.json"

# --- Artifact sub-directories (Phase C, Prompt 11) --------------------------

PLOTS_DIR = ARTIFACTS_DIR / "plots"

# --- Config files -----------------------------------------------------------

CITIES_PATH = CONFIG_DIR / "cities.yaml"
SOURCES_PATH = CONFIG_DIR / "sources.yaml"
PIPELINE_PATH = CONFIG_DIR / "pipeline.yaml"
MODEL_PATH = CONFIG_DIR / "model.yaml"


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


def raw_relpath(
    source: str,
    city: str,
    window: object,
    ext: str = "json",
    *,
    subdir: str | None = None,
    name: str | None = None,
) -> str:
    """Stable POSIX-relative path (under ``data/``) for one (source, city, window).

    Two layouts:

    * Default (Prompt 2): flat, window-stamped — deterministic and self-describing::

          raw/open_meteo_weather__Lahore__2022-08-05_2026-06-28.json

    * Per-source subdir (adapters, e.g. Prompt 3): a tidy ``raw/<subdir>/<name>``
      grouping with a stable, human-friendly filename (defaults to the city)::

          raw/weather/Lahore.json

    The window is always recorded in the manifest entry, so the per-source layout
    loses no provenance even when it is absent from the filename.
    """
    if subdir is not None:
        stem = slug(name) if name is not None else slug(city)
        return f"raw/{slug(subdir)}/{stem}.{ext}"
    start, end = _window_bounds(window)
    fname = f"{slug(source)}__{slug(city)}__{slug(start)}_{slug(end)}.{ext}"
    return f"raw/{fname}"


def raw_path(
    source: str,
    city: str,
    window: object,
    ext: str = "json",
    data_dir: Path | None = None,
    *,
    subdir: str | None = None,
    name: str | None = None,
) -> Path:
    """Absolute raw-file path, rooted at ``data_dir`` (defaults to :data:`DATA_DIR`)."""
    base = data_dir if data_dir is not None else DATA_DIR
    return base / raw_relpath(source, city, window, ext, subdir=subdir, name=name)


def ensure_dir(path: Path) -> Path:
    """Create ``path`` (and parents) if missing; return it."""
    path.mkdir(parents=True, exist_ok=True)
    return path
