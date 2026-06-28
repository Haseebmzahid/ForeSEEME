"""Tests for the ForeSeeMe risk-data contract schemas.

Covers, per the contract:
- valid input is accepted by both request and response models;
- each out-of-range field (aqi < 0, temperature > 80, confidence outside
  [0, 1]) raises a ``ValidationError`` (which FastAPI maps to HTTP 422).
"""

from datetime import datetime, timezone

import pytest
from pydantic import ValidationError

from app.schemas import PredictRequest, RiskEstimateResponse


def _valid_request_kwargs() -> dict:
    return {
        "city": "Lahore",
        "temperature": 34.5,
        "humidity": 62.0,
        "rainfall": 12.0,
        "aqi": 180.0,
        "weekOfYear": 26,
    }


def _valid_response_kwargs() -> dict:
    return {
        "city": "Lahore",
        "riskLevel": "High",
        "disease": "Dengue",
        "confidence": 0.87,
        "temperature": 34.5,
        "humidity": 62.0,
        "aqi": 180.0,
        "generatedAt": datetime(2026, 6, 28, tzinfo=timezone.utc),
        "modelVersion": "rf-v1.2",
    }


# ── Happy path ──────────────────────────────────────────────────────────────


def test_valid_request_passes() -> None:
    request = PredictRequest(**_valid_request_kwargs())
    assert request.city == "Lahore"
    assert request.week_of_year == 26


def test_valid_response_passes() -> None:
    response = RiskEstimateResponse(**_valid_response_kwargs())
    assert response.risk_level == "High"
    assert response.confidence == 0.87
    # Optional field defaults to False.
    assert response.low_confidence is False


def test_response_confidence_bounds_are_inclusive() -> None:
    for value in (0.0, 1.0):
        response = RiskEstimateResponse(
            **{**_valid_response_kwargs(), "confidence": value}
        )
        assert response.confidence == value


# ── aqi < 0 rejected (request and response) ─────────────────────────────────


def test_request_rejects_negative_aqi() -> None:
    with pytest.raises(ValidationError):
        PredictRequest(**{**_valid_request_kwargs(), "aqi": -1.0})


def test_response_rejects_negative_aqi() -> None:
    with pytest.raises(ValidationError):
        RiskEstimateResponse(**{**_valid_response_kwargs(), "aqi": -0.1})


# ── temperature > 80 rejected (request and response) ────────────────────────


def test_request_rejects_temperature_above_80() -> None:
    with pytest.raises(ValidationError):
        PredictRequest(**{**_valid_request_kwargs(), "temperature": 80.1})


def test_response_rejects_temperature_above_80() -> None:
    with pytest.raises(ValidationError):
        RiskEstimateResponse(**{**_valid_response_kwargs(), "temperature": 99.0})


# ── confidence outside [0, 1] rejected (response) ───────────────────────────


def test_response_rejects_confidence_below_zero() -> None:
    with pytest.raises(ValidationError):
        RiskEstimateResponse(**{**_valid_response_kwargs(), "confidence": -0.01})


def test_response_rejects_confidence_above_one() -> None:
    with pytest.raises(ValidationError):
        RiskEstimateResponse(**{**_valid_response_kwargs(), "confidence": 1.01})


# ── weekOfYear sanity bounds ────────────────────────────────────────────────


@pytest.mark.parametrize("week", [0, 54])
def test_request_rejects_out_of_range_week(week: int) -> None:
    with pytest.raises(ValidationError):
        PredictRequest(**{**_valid_request_kwargs(), "weekOfYear": week})
