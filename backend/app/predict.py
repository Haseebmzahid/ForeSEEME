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

logger = logging.getLogger("foreseeme.risk.predict")

#: ``backend/ml/artifacts`` — predict.py lives in ``backend/app/``.
ARTIFACTS_DIR = Path(__file__).resolve().parents[1] / "ml" / "artifacts"

#: Reliability threshold from the frozen contract (RISK_SCHEMA.md): confidence
#: below this flags ``lowConfidence``.
LOW_CONFIDENCE_THRESHOLD = 0.55

_SEVERITY = {"Low": 0, "Medium": 1, "High": 2}

#: Human-readable disease names for the contract ``disease`` field.
_DISPLAY = {"dengue": "Dengue", "smog": "Smog", "influenza": "Influenza"}


def resolve_artifact_path(explicit: str | None = None) -> Path | None:
    """Resolve the model artifact: an explicit override, else the latest local one."""
    if explicit:
        return Path(explicit)
    candidates = sorted(ARTIFACTS_DIR.glob("model_*.joblib"))
    return candidates[-1] if candidates else None


def load_bundle(path: Path) -> dict[str, Any]:
    """Load the promoted bundle (a plain dict — no custom class needed)."""
    return joblib.load(path)


class RealRiskModel(RiskModel):
    """Serves the trained per-disease Random Forest Pipelines behind the contract."""

    def __init__(self, bundle: dict[str, Any]) -> None:
        self._bundle = bundle
        self._version: str = bundle["model_version"]
        self._feature_names: list[str] = bundle["feature_names"]
        self._diseases: list[str] = bundle["diseases"]

    @property
    def model_version(self) -> str:
        return self._version

    def predict(self, request: PredictRequest) -> RiskEstimateResponse:
        """Classify the dominant environmental risk for one city/week request."""
        features = build_request_features(request, self._feature_names)

        best: tuple[tuple[int, float], str, str, float] | None = None
        for disease in self._diseases:
            pipeline = self._bundle["models"][disease]
            proba = pipeline.predict_proba(features)[0]
            classes = list(pipeline.classes_)
            idx = int(np.argmax(proba))
            level = str(classes[idx])
            confidence = float(proba[idx])
            rank = (_SEVERITY[level], confidence)
            if best is None or rank > best[0]:
                best = (rank, disease, level, confidence)

        assert best is not None  # diseases is non-empty by construction
        _, disease, risk_level, confidence = best
        confidence = round(confidence, 4)

        return RiskEstimateResponse(
            city=request.city,
            risk_level=risk_level,
            disease=_DISPLAY.get(disease, disease.title()),
            confidence=confidence,
            temperature=request.temperature,
            humidity=request.humidity,
            aqi=request.aqi,
            generated_at=datetime.now(timezone.utc),
            model_version=self._version,
            low_confidence=confidence < LOW_CONFIDENCE_THRESHOLD,
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
