"""FastAPI application for the ForeSeeMe risk service.

Exposes liveness and authenticated inference backed by the promoted model
or its local stub fallback:

- ``GET  /health``  -> liveness + reported model version.
- ``POST /predict`` -> contract-valid risk estimate (internal endpoint, ADR-001;
  never called by the Flutter client).

Pydantic validation failures on the request body surface automatically as HTTP
422 responses. This module writes nothing to Firestore.
"""

from __future__ import annotations

from fastapi import Depends, FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from app.config import Settings, get_settings
from app.inference_auth import require_inference_caller
from app.logging_config import configure_logging
from app.models.risk_model import RiskModel
from app.predict import load_risk_model
from app.schemas import PredictRequest, RiskEstimateResponse


def create_app(
    settings: Settings | None = None,
    model: RiskModel | None = None,
) -> FastAPI:
    """Application factory.

    Args:
        settings: Optional settings override (defaults to env-derived settings).
        model: Optional :class:`RiskModel` override. When omitted, the real
            promoted model is loaded from the artifact path, falling back to the
            deterministic :class:`StubRiskModel` if the artifact is absent or
            corrupt (Sprint 1 graceful-degradation behaviour preserved).

    Returns:
        A configured :class:`FastAPI` instance.
    """
    settings = settings or get_settings()
    configure_logging(settings.log_level)

    if model is not None:
        risk_model: RiskModel = model
        model_loaded = True
        active_version = getattr(model, "model_version", settings.model_version)
    else:
        risk_model, model_loaded, active_version = load_risk_model(settings)

    app = FastAPI(
        title="ForeSeeMe Risk Service",
        version=active_version,
        description="Internal disease-risk service.",
    )
    app.state.settings = settings

    @app.middleware("http")
    async def require_tls(request: Request, call_next):
        # Only the trusted TLS-terminating proxy may set ASGI's scheme.
        # Container health probes also use the non-sensitive liveness endpoint.
        if request.url.path != "/health" and request.url.scheme != "https":
            return JSONResponse(status_code=400, content={"detail": "HTTPS required"})
        return await call_next(request)

    @app.exception_handler(RequestValidationError)
    async def validation_error(_request: Request, exc: RequestValidationError):
        errors = [
            {
                "loc": ("body",) if error["type"] == "extra_forbidden" else error["loc"],
                "type": error["type"],
                "msg": error["msg"],
            }
            for error in exc.errors()
        ]
        return JSONResponse(status_code=422, content={"detail": errors})

    @app.get("/health")
    def health() -> dict[str, object]:
        """Liveness probe: status, active model version, and load state."""
        return {
            "status": "ok",
            "modelVersion": active_version,
            "modelLoaded": model_loaded,
        }

    @app.post(
        "/predict",
        response_model=RiskEstimateResponse,
        dependencies=[Depends(require_inference_caller)],
    )
    def predict(request: PredictRequest) -> RiskEstimateResponse:
        """Compute a risk estimate for one city/week feature vector."""
        return risk_model.predict(request)

    return app


# Module-level ASGI app for uvicorn (`uvicorn app.main:app`).
app = create_app()
