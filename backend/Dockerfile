# ForeSeeMe risk service container.
# Stub model only — no ML libraries are installed (ADR-002 gates the real model).
FROM python:3.12-slim

# Predictable, log-friendly Python runtime.
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PORT=8000

WORKDIR /app

# Install pinned dependencies first for better layer caching.
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Application code.
COPY app ./app

# Run as a non-root user (security: never run the service as root).
RUN useradd --create-home --uid 1000 appuser
USER appuser

EXPOSE 8000

# Bind to the container port from $PORT (env-driven, no hardcoded value).
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT}"]
