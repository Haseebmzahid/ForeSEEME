"""Pydantic v2 schemas for the ForeSeeMe risk-data contract.

These models describe the SAME shape shared by three artifacts
(see docs/RISK_SCHEMA.md):

1. This module's :class:`PredictRequest` / :class:`RiskEstimateResponse`.
2. The Dart ``RiskEstimateModel`` (lib/features/risk/domain/models/).
3. The Firestore document ``riskEstimates/{city}_{YYYY-MM-DD}``.

This module is contract-only: it defines the request/response shapes and their
validation rules for a *future* internal ``POST /predict`` endpoint. It contains
no model inference, no endpoint body, and no Firestore writes (ADR-001: the
``/predict`` endpoint is internal to the backend and is never called by the app).

When these models are bound to a FastAPI route, a :class:`ValidationError` raised
during request parsing is surfaced automatically by FastAPI as an HTTP ``422
Unprocessable Entity`` response.
"""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

#: Allowed risk classifications. Mirrors the Dart ``RiskLevel`` enum's contract
#: strings exactly ("Low" | "Medium" | "High").
RiskLevel = Literal["Low", "Medium", "High"]

# Shared upper bound for the temperature feature, in degrees Celsius. Values
# above this are physically implausible for a city reading and are rejected.
_MAX_TEMPERATURE_C: float = 80.0


class PredictRequest(BaseModel):
    """Request body for the internal ``POST /predict`` endpoint.

    Carries the environmental features for one city/week from which the backend
    batch job computes a :class:`RiskEstimateResponse`.

    Attributes:
        city: City the prediction is requested for.
        temperature: Temperature feature in degrees Celsius (must be <= 80).
        humidity: Relative humidity feature in percent.
        rainfall: Rainfall feature in millimetres.
        aqi: Air-quality-index feature (must be >= 0).
        week_of_year: ISO week number in ``[1, 53]``. Serialised as
            ``weekOfYear`` to match the camelCase contract.
    """

    model_config = ConfigDict(populate_by_name=True)

    city: str
    temperature: float
    humidity: float
    rainfall: float
    aqi: float
    week_of_year: int = Field(..., ge=1, le=53, alias="weekOfYear")

    @field_validator("aqi")
    @classmethod
    def _validate_aqi(cls, value: float) -> float:
        """Reject a negative air-quality index."""
        if value < 0:
            raise ValueError("aqi must be >= 0")
        return value

    @field_validator("temperature")
    @classmethod
    def _validate_temperature(cls, value: float) -> float:
        """Reject a physically implausible temperature (> 80 C)."""
        if value > _MAX_TEMPERATURE_C:
            raise ValueError(f"temperature must be <= {_MAX_TEMPERATURE_C}")
        return value


class RiskEstimateResponse(BaseModel):
    """Response shape for ``POST /predict`` and the ``riskEstimates`` document.

    This is the canonical risk-data shape the Flutter app reads from Firestore.

    Attributes:
        city: City the estimate was computed for.
        risk_level: Classified risk level ("Low" | "Medium" | "High"). Serialised
            as ``riskLevel``.
        disease: Disease the estimate refers to.
        confidence: Model confidence in ``[0.0, 1.0]``.
        temperature: Temperature feature in degrees Celsius (must be <= 80).
        humidity: Relative humidity feature in percent.
        aqi: Air-quality-index feature (must be >= 0).
        generated_at: UTC timestamp the estimate was generated. Serialised as
            ``generatedAt`` (ISO-8601).
        model_version: Version of the model that produced the estimate.
            Serialised as ``modelVersion``.
        low_confidence: True when ``confidence`` is below the reliability
            threshold. Optional, defaults to ``False``. Serialised as
            ``lowConfidence``.
    """

    model_config = ConfigDict(populate_by_name=True)

    city: str
    risk_level: RiskLevel = Field(..., alias="riskLevel")
    disease: str
    confidence: float
    temperature: float
    humidity: float
    aqi: float
    generated_at: datetime = Field(..., alias="generatedAt")
    model_version: str = Field(..., alias="modelVersion")
    low_confidence: bool = Field(default=False, alias="lowConfidence")

    @field_validator("confidence")
    @classmethod
    def _validate_confidence(cls, value: float) -> float:
        """Reject a confidence outside the closed interval ``[0.0, 1.0]``."""
        if value < 0.0 or value > 1.0:
            raise ValueError("confidence must be in [0.0, 1.0]")
        return value

    @field_validator("aqi")
    @classmethod
    def _validate_aqi(cls, value: float) -> float:
        """Reject a negative air-quality index."""
        if value < 0:
            raise ValueError("aqi must be >= 0")
        return value

    @field_validator("temperature")
    @classmethod
    def _validate_temperature(cls, value: float) -> float:
        """Reject a physically implausible temperature (> 80 C)."""
        if value > _MAX_TEMPERATURE_C:
            raise ValueError(f"temperature must be <= {_MAX_TEMPERATURE_C}")
        return value
