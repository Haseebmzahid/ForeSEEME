"""Verify Google-issued OIDC tokens for a dedicated inference caller."""

from fastapi import HTTPException, Request
from google.auth import exceptions
from google.auth.transport.requests import Request as GoogleRequest
from google.oauth2 import id_token


def require_inference_caller(request: Request) -> None:
    settings = request.app.state.settings
    audience = settings.inference_audience
    subject = settings.inference_service_account_subject
    if not audience or not subject or not subject.isascii() or not subject.isdecimal():
        raise HTTPException(503, "Inference authorization unavailable")

    scheme, _, token = request.headers.get("authorization", "").partition(" ")
    if scheme.lower() != "bearer" or not token or len(token) > 8192 or token.count(".") != 2:
        raise HTTPException(401, "Invalid service credential")
    try:
        claims = id_token.verify_oauth2_token(token, GoogleRequest(), audience=audience)
    except exceptions.TransportError:
        raise HTTPException(503, "Inference authorization unavailable") from None
    except (ValueError, exceptions.GoogleAuthError):
        raise HTTPException(401, "Invalid service credential") from None
    if claims.get("sub") != subject:
        raise HTTPException(403, "Inference caller not authorized")
