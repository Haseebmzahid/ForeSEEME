"""FastAPI application for the ForeSeeMe risk service.

Exposes two endpoints backed by a placeholder stub model (ADR-002 will later add
the real model and the scheduled batch job):

- ``GET  /health``  -> liveness + reported model version.
- ``POST /predict`` -> contract-valid risk estimate (internal endpoint, ADR-001;
  never called by the Flutter client).

Pydantic validation failures on the request body surface automatically as HTTP
422 responses. This module writes nothing to Firestore and calls no external API.
"""

from __future__ import annotations

import logging

from fastapi import FastAPI

from app.config import Settings, get_settings
from app.logging_config import configure_logging
from app.models.risk_model import RiskModel, StubRiskModel
from app.schemas import PredictRequest, RiskEstimateResponse

logger = logging.getLogger("foreseeme.risk")


def create_app(
    settings: Settings | None = None,
    model: RiskModel | None = None,
) -> FastAPI:
    """Application factory.

    Args:
        settings: Optional settings override (defaults to env-derived settings).
        model: Optional :class:`RiskModel` override. Defaults to the
            deterministic :class:`StubRiskModel`. Injectable so the real model
            can be substituted later without changing the API layer.

    Returns:
        A configured :class:`FastAPI` instance.
    """
    settings = settings or get_settings()
    configure_logging(settings.log_level)
    risk_model: RiskModel = model or StubRiskModel(
        model_version=settings.model_version
    )

    app = FastAPI(
        title="ForeSeeMe Risk Service",
        version=settings.model_version,
        description="Internal disease-risk service (stub model).",
    )

    @app.get("/health")
    def health() -> dict[str, str]:
        """Liveness probe with the active model version."""
        return {"status": "ok", "modelVersion": settings.model_version}

    @app.post("/predict", response_model=RiskEstimateResponse)
    def predict(request: PredictRequest) -> RiskEstimateResponse:
        """Compute a risk estimate for one city/week feature vector.

        Logs the input feature vector as structured JSON before classifying.
        """
        logger.info(
            "predict_request",
            extra={"features": request.model_dump(by_alias=True)},
        )
        return risk_model.predict(request)

    return app


# Module-level ASGI app for uvicorn (`uvicorn app.main:app`).
app = create_app()
