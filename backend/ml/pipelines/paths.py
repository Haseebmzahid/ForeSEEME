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
      artifacts/  candidate_model.joblib  candidate_metrics.json  evaluation.json
                  model_<version>.joblib  metrics.json  feature_importance.csv  plots/
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


# --- Promoted model artifacts (Prompt 13 / Sprint M6.2) ----------------------
#
# The single definition of the ``model_<semver>.joblib`` naming convention that
# ``ml.training.persist.promote()`` writes and ``app.predict`` discovers, so the
# writer and the reader can never encode the pattern — or the semver rules —
# differently. Previously ``persist.py`` defined its own ``SEMVER_RE``/
# ``is_semver`` and ``app/predict.py`` picked "latest" by sorting filenames as
# plain strings (`model_10.0.0.joblib` sorted *before* `model_2.0.0.joblib`).
# Both now derive from here.

MODEL_ARTIFACT_PREFIX = "model_"
MODEL_ARTIFACT_SUFFIX = ".joblib"
#: Glob pattern for every promoted artifact under an artifacts directory.
MODEL_ARTIFACT_GLOB = f"{MODEL_ARTIFACT_PREFIX}*{MODEL_ARTIFACT_SUFFIX}"

#: Strict semver (major.minor.patch, optional pre-release/build) — the version
#: :func:`~ml.training.persist.promote` validates before writing an artifact.
SEMVER_RE = re.compile(
    r"^(?P<major>0|[1-9]\d*)\.(?P<minor>0|[1-9]\d*)\.(?P<patch>0|[1-9]\d*)"
    r"(?:-(?P<prerelease>[0-9A-Za-z-.]+))?(?:\+(?P<build>[0-9A-Za-z-.]+))?$"
)


def is_semver(version: str) -> bool:
    """Whether ``version`` is a valid semver string."""
    return bool(SEMVER_RE.match(version))


def model_artifact_version(path: Path) -> str | None:
    """The semver string encoded in a ``model_<version>.joblib`` filename.

    Returns ``None`` if ``path`` doesn't match the naming convention or its
    version segment isn't valid semver (a malformed or stray file) — so a caller
    can skip it rather than crash, the same graceful-degradation posture the
    rest of artifact loading uses.
    """
    stem = path.stem  # "model_1.0.0.joblib" -> "model_1.0.0"
    if not stem.startswith(MODEL_ARTIFACT_PREFIX):
        return None
    version = stem[len(MODEL_ARTIFACT_PREFIX):]
    return version if is_semver(version) else None


def semver_sort_key(version: str) -> tuple[int, int, int, int, str]:
    """Numeric ordering key for a semver string.

    ``model_10.0.0`` now correctly outranks ``model_2.0.0`` (Sprint M6.2 — the
    prior lexicographic filename sort did not: ``"10.0.0" < "2.0.0"`` as plain
    strings). A release (no pre-release) sorts after any pre-release of the same
    major.minor.patch, matching real semver precedence for the common case; two
    pre-releases of the same version break ties by string comparison. The full
    semver pre-release-precedence algorithm (numeric vs. alphanumeric identifier
    comparison, per-dot-segment) is not implemented — this project only ever
    releases plain ``major.minor.patch`` versions (``config/model.yaml:
    release.version``), so that complexity has no current use.
    """
    match = SEMVER_RE.match(version)
    if not match:
        raise ValueError(f"{version!r} is not valid semver")
    prerelease = match["prerelease"] or ""
    is_release = 0 if prerelease else 1  # a release outranks its own pre-releases
    return (int(match["major"]), int(match["minor"]), int(match["patch"]),
            is_release, prerelease)


def latest_model_artifact(artifacts_dir: Path | None = None) -> Path | None:
    """The highest-semver promoted ``model_<version>.joblib`` under ``artifacts_dir``.

    Deterministic, semver-aware selection (Sprint M6.2) — never filename string
    order. Filenames that don't parse as ``model_<semver>.joblib`` are ignored
    rather than raising, so one stray or malformed file cannot break discovery
    for everything else. Returns ``None`` if no valid artifact is found. This is
    the single "what is the active production model" lookup — both
    ``app.predict.resolve_artifact_path`` (serving) and any future caller should
    use this rather than re-implementing artifact discovery.
    """
    base = artifacts_dir if artifacts_dir is not None else ARTIFACTS_DIR
    candidates = [
        (semver_sort_key(version), candidate)
        for candidate in base.glob(MODEL_ARTIFACT_GLOB)
        if (version := model_artifact_version(candidate)) is not None
    ]
    if not candidates:
        return None
    return max(candidates, key=lambda item: item[0])[1]


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
