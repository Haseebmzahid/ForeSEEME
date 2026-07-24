"""Real-model serving load path (Sprint 2, Prompt 14).

Loads the promoted ``model_<version>.joblib`` (Prompt 13) and serves it behind the
**unchanged** Sprint 1 :class:`~app.models.risk_model.RiskModel` abstraction, so
the API layer and the frozen contract are untouched.

A request carries one city/week point but the model covers three disease
families; ``/predict`` returns the **dominant** environmental risk (most severe
level, ties broken by confidence) as the single contract ``disease`` / ``riskLevel``
— matching the one-disease-per-(city, day) Firestore document the batch job writes
(Prompt 15) and the awareness-dashboard intent.

Graceful degradation (Sprint 1 behaviour preserved): if the artifact is missing or
fails to load, :func:`load_risk_model` falls back to the deterministic
:class:`StubRiskModel` and reports ``modelLoaded: false`` — the service stays up
and contract-valid rather than 500-ing.

Configuration (Sprint M6.1): the ``lowConfidence`` reliability threshold is a
training-time value (``config/model.yaml: evaluation.low_confidence_threshold``)
baked into the artifact as ``bundle["low_confidence_threshold"]``. Nothing here
hardcodes that business value — :func:`resolve_low_confidence_threshold` is the
single place that reads it, with a documented fallback for artifacts trained
before this field existed. :mod:`app.explain` and :mod:`app.jobs.compute_risk`
reuse the same resolver so training and every inference path agree by
construction rather than by three separately-maintained copies.

Artifact resolution (Sprint M6.2): "latest" is chosen by semver-aware numeric
ordering, never filename string order, via the single shared
:func:`ml.pipelines.paths.latest_model_artifact` — the same naming convention
:func:`ml.training.persist.promote` writes. See :func:`resolve_artifact_path`.
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import joblib
import numpy as np

from app.feature_builder import build_request_features
from app.models.risk_model import RiskModel, StubRiskModel
from app.schemas import PredictRequest, RiskEstimateResponse
from ml.pipelines import paths as ml_paths

logger = logging.getLogger("foreseeme.risk.predict")

#: ``backend/ml/artifacts``. Sprint M6.2: reuses the single, env-overridable
#: definition in ``ml.pipelines.paths`` (``FORESEEME_ML_ARTIFACTS_DIR``) instead
#: of an independently hardcoded path — previously this module silently ignored
#: that override while every other artifact-writing/reading module honoured it.
ARTIFACTS_DIR = ml_paths.ARTIFACTS_DIR

#: Fallback reliability threshold (RISK_SCHEMA.md: confidence below this flags
#: ``lowConfidence``), used ONLY when a loaded artifact predates Sprint M6.1's
#: ``bundle["low_confidence_threshold"]`` field. Every artifact trained after
#: M6.1 carries its own value (sourced from ``config/model.yaml``); this is not
#: a second source of truth, it is what a pre-M6.1 artifact was actually
#: evaluated/served against, preserved for backward compatibility.
DEFAULT_LOW_CONFIDENCE_THRESHOLD = 0.55

_SEVERITY = {"Low": 0, "Medium": 1, "High": 2}

#: Human-readable disease names for the contract ``disease`` field.
_DISPLAY = {"dengue": "Dengue", "smog": "Smog", "influenza": "Influenza"}


def display_disease(disease_key: str) -> str:
    """Human-readable disease name for the contract ``disease`` field."""
    return _DISPLAY.get(disease_key, disease_key.title())


def resolve_low_confidence_threshold(bundle: dict[str, Any]) -> float:
    """The ``lowConfidence`` reliability threshold for a loaded bundle.

    Single source of truth (Sprint M6.1): reads ``bundle["low_confidence_threshold"]``
    — the value trained into the artifact from ``config/model.yaml`` — falling back
    to :data:`DEFAULT_LOW_CONFIDENCE_THRESHOLD` only for an artifact promoted before
    this field existed. Every inference component (:class:`RealRiskModel`,
    :mod:`app.explain`, :mod:`app.jobs.compute_risk`) calls this instead of keeping
    its own copy of the threshold.
    """
    return float(bundle.get("low_confidence_threshold", DEFAULT_LOW_CONFIDENCE_THRESHOLD))


def resolve_artifact_path(explicit: str | None = None) -> Path | None:
    """Resolve the model artifact: an explicit override, else the latest promoted one.

    Sprint M6.2: "latest" is semver-aware (``model_10.0.0.joblib`` correctly
    outranks ``model_2.0.0.joblib``), delegated to the single shared
    :func:`ml.pipelines.paths.latest_model_artifact` rather than a locally
    sorted filename glob — the prior implementation sorted filenames as plain
    strings, which is not semver-safe past a two-digit version component.
    """
    if explicit:
        return Path(explicit)
    return ml_paths.latest_model_artifact(ARTIFACTS_DIR)


def load_bundle(path: Path) -> dict[str, Any]:
    """Load the promoted bundle (a plain dict — no custom class needed)."""
    return joblib.load(path)


def classify_dominant(
    bundle: dict[str, Any], features: Any
) -> tuple[str, str, float]:
    """Return the dominant ``(disease_key, risk_level, confidence)`` for one feature row.

    Runs every disease Pipeline on the single-row ``features`` frame and selects the
    most severe risk level, breaking ties by confidence. Shared by the ``/predict``
    endpoint and the batch job so the selection logic has one definition.
    """
    best: tuple[tuple[int, float], str, str, float] | None = None
    for disease in bundle["diseases"]:
        pipeline = bundle["models"][disease]
        proba = pipeline.predict_proba(features)[0]
        classes = list(pipeline.classes_)
        idx = int(np.argmax(proba))
        level = str(classes[idx])
        confidence = float(proba[idx])
        rank = (_SEVERITY[level], confidence)
        if best is None or rank > best[0]:
            best = (rank, disease, level, confidence)
    assert best is not None  # diseases is non-empty by construction
    return best[1], best[2], best[3]


class RealRiskModel(RiskModel):
    """Serves the trained per-disease Random Forest Pipelines behind the contract."""

    def __init__(self, bundle: dict[str, Any]) -> None:
        self._bundle = bundle
        self._version: str = bundle["model_version"]
        self._feature_names: list[str] = bundle["feature_names"]
        self._diseases: list[str] = bundle["diseases"]
        self._low_confidence_threshold = resolve_low_confidence_threshold(bundle)

    @property
    def model_version(self) -> str:
        return self._version

    def predict(self, request: PredictRequest) -> RiskEstimateResponse:
        """Classify the dominant environmental risk for one city/week request."""
        features = build_request_features(request, self._feature_names)
        disease, risk_level, confidence = classify_dominant(self._bundle, features)
        confidence = round(confidence, 4)

        return RiskEstimateResponse(
            city=request.city,
            risk_level=risk_level,
            disease=display_disease(disease),
            confidence=confidence,
            temperature=request.temperature,
            humidity=request.humidity,
            aqi=request.aqi,
            generated_at=datetime.now(timezone.utc),
            model_version=self._version,
            low_confidence=confidence < self._low_confidence_threshold,
        )


def load_risk_model(settings: Any) -> tuple[RiskModel, bool, str]:
    """Return ``(model, model_loaded, active_version)``.

    Tries the real artifact; on any failure (missing or corrupt) falls back to the
    Sprint 1 stub so the service degrades gracefully instead of failing to start.
    """
    explicit = getattr(settings, "model_artifact_path", None)
    path = resolve_artifact_path(explicit)
    if path is None or not path.exists():
        logger.warning("model artifact not found (path=%s); serving stub", path)
        return StubRiskModel(settings.model_version), False, settings.model_version
    try:
        model = RealRiskModel(load_bundle(path))
        logger.info("real model loaded", extra={"path": str(path),
                                                 "modelVersion": model.model_version})
        return model, True, model.model_version
    except Exception as exc:  # corrupt artifact, version mismatch, etc.
        logger.error("failed to load model artifact %s; serving stub: %s", path, exc)
        return StubRiskModel(settings.model_version), False, settings.model_version
