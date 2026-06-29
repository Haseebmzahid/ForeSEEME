"""Risk model interface and a deterministic, non-ML placeholder implementation.

IMPORTANT (sprint scope): This module contains **no machine learning**. The real
Random Forest model and the scheduled batch job (ADR-002) are a separate, gated
sprint. :class:`StubRiskModel` exists ONLY so integration can proceed before the
real model is available: it returns contract-valid output from a simple,
transparent, fully deterministic rule. Do NOT train, load, or import any real
model here.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from datetime import datetime, timezone

from app.schemas import PredictRequest, RiskEstimateResponse

# Stub classification thresholds (transparent, documented, non-ML). A combined
# score is computed from the air-quality index and temperature features.
_AQI_WEIGHT = 0.6
_TEMP_WEIGHT = 0.4
_AQI_SCALE = 300.0  # AQI value mapped to ~1.0 contribution.
_TEMP_SCALE = 50.0  # Temperature (C) mapped to ~1.0 contribution.
_HIGH_THRESHOLD = 0.66
_MEDIUM_THRESHOLD = 0.33
# Confidence below this is flagged as low; chosen so the stub exercises the
# `lowConfidence` path for benign inputs.
_LOW_CONFIDENCE_THRESHOLD = 0.6


def _clamp(value: float, low: float = 0.0, high: float = 1.0) -> float:
    """Clamp ``value`` into the closed interval ``[low, high]``."""
    return max(low, min(high, value))


class RiskModel(ABC):
    """Abstract risk model: maps a :class:`PredictRequest` to a response.

    Concrete implementations (the stub now, a Random Forest later) own the
    classification logic. Callers depend on this interface, never on a concrete
    class, so the real model can be swapped in without touching the API layer.
    """

    @abstractmethod
    def predict(self, request: PredictRequest) -> RiskEstimateResponse:
        """Return a contract-valid risk estimate for ``request``."""
        raise NotImplementedError


class StubRiskModel(RiskModel):
    """Deterministic, rule-based placeholder — **not** a machine-learning model.

    The classification is a transparent threshold over a weighted ``aqi`` /
    ``temperature`` score, so the same input always yields the same risk level
    and confidence. ``generatedAt`` is the wall-clock generation time (UTC); the
    risk *classification* is what is deterministic.
    """

    def __init__(self, model_version: str) -> None:
        """Create the stub.

        Args:
            model_version: Version string stamped onto responses. Supplied from
                configuration (defaults to ``"stub-0.0.0"``), never hardcoded as
                a secret.
        """
        self._model_version = model_version

    @property
    def model_version(self) -> str:
        """Version string stamped onto responses (reported by ``/health``)."""
        return self._model_version

    def predict(self, request: PredictRequest) -> RiskEstimateResponse:
        """Classify risk from a transparent threshold rule."""
        score = _clamp(
            (request.aqi / _AQI_SCALE) * _AQI_WEIGHT
            + (request.temperature / _TEMP_SCALE) * _TEMP_WEIGHT
        )

        if score >= _HIGH_THRESHOLD:
            risk_level = "High"
        elif score >= _MEDIUM_THRESHOLD:
            risk_level = "Medium"
        else:
            risk_level = "Low"

        # Confidence rises with the score but stays strictly within [0, 1].
        confidence = round(_clamp(0.5 + score / 2.0), 4)

        # Placeholder "disease" derived from the dominant driver, purely for a
        # human-readable, deterministic value — not a clinical claim.
        aqi_contribution = (request.aqi / _AQI_SCALE) * _AQI_WEIGHT
        temp_contribution = (request.temperature / _TEMP_SCALE) * _TEMP_WEIGHT
        disease = (
            "Respiratory Illness"
            if aqi_contribution >= temp_contribution
            else "Heat-Related Illness"
        )

        return RiskEstimateResponse(
            city=request.city,
            risk_level=risk_level,
            disease=disease,
            confidence=confidence,
            temperature=request.temperature,
            humidity=request.humidity,
            aqi=request.aqi,
            generated_at=datetime.now(timezone.utc),
            model_version=self._model_version,
            low_confidence=confidence < _LOW_CONFIDENCE_THRESHOLD,
        )
