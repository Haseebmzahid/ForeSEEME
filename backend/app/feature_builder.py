"""Serving-time feature construction (Sprint 2, Prompt 14).

Maps a :class:`~app.schemas.PredictRequest` to the exact feature vector the
trained Random Forest expects — by **delegating to the Prompt 8 feature
engineering** (`ml.pipelines.features`). That delegation is deliberate: the same
transform builds features at train time and at serving time, so the two can never
diverge (the parity test in ``tests/test_api.py`` proves it for a fixed input).

The single-point ``/predict`` contract carries no history, so the history-derived
families (lags, rolling means, seasonal anomalies) are produced as NaN by the
engineering step and imputed inside the saved Pipeline exactly as in training. The
scheduled batch job (Prompt 15) supplies a trailing window so those features carry
real signal; the feature logic it uses is this same module.

This module performs no model inference and writes nothing. It does not import the
VALIDATION_ONLY disease reference (only the Prompt 8 transforms), so its
``*feature*`` name does not trip that module's guard.
"""

from __future__ import annotations

from functools import lru_cache

import pandas as pd

from app.schemas import PredictRequest
from ml.pipelines import features as feat

#: Placeholder ISO year for a single-point serving frame. ``iso_year`` is only
#: used by the engineering step for chronological ordering and is NOT a model
#: feature, so its value never reaches the feature vector.
_SERVING_ISO_YEAR = 2000


@lru_cache(maxsize=1)
def _feature_config() -> dict:
    """Cached Prompt 8 feature config (avoids re-reading YAML per request)."""
    return feat.load_feature_config()


@lru_cache(maxsize=1)
def _city_vocab() -> tuple[str, ...]:
    """Cached fixed city vocabulary (same one-hot order as training)."""
    return tuple(feat.load_city_vocab())


def request_to_base(request: PredictRequest) -> pd.DataFrame:
    """Map a request to a one-row weekly base table (the Prompt 7 schema).

    ``pm2_5`` / ``pm10`` are absent from the single-point contract and are left
    NaN (imputed by the Pipeline); ``aqi_available`` is True because an AQI value
    was supplied.
    """
    return pd.DataFrame([{
        "city": request.city,
        "iso_year": _SERVING_ISO_YEAR,
        "week_of_year": int(request.week_of_year),
        "temperature": float(request.temperature),
        "humidity": float(request.humidity),
        "precipitation": float(request.rainfall),
        "pm2_5": float("nan"),
        "pm10": float("nan"),
        "us_aqi": float(request.aqi),
        "aqi_available": True,
    }])


def engineer_serving_features(
    base: pd.DataFrame, feature_names: list[str]
) -> pd.DataFrame:
    """Engineer features via the Prompt 8 pipeline; keep keys + the model columns.

    The single source of truth: this calls the same ``engineer_features`` used to
    build the training set, so serving features cannot drift from training
    features. Any model column the engineering step does not produce is added as
    NaN (defensive; should not happen for the documented feature set).
    """
    engineered, _families = feat.engineer_features(
        base, _feature_config(), list(_city_vocab())
    )
    for col in feature_names:
        if col not in engineered.columns:
            engineered[col] = float("nan")
    keep = list(feat.KEY) + [c for c in feature_names if c not in feat.KEY]
    return engineered[[c for c in keep if c in engineered.columns]]


def build_request_features(
    request: PredictRequest, feature_names: list[str]
) -> pd.DataFrame:
    """Build the single-row, model-ordered feature frame for one request.

    History-dependent features are NaN here (no trailing window in the
    single-point contract) and are imputed inside the Pipeline, identically to
    training.
    """
    engineered = engineer_serving_features(request_to_base(request), feature_names)
    return engineered[feature_names].astype(float)
