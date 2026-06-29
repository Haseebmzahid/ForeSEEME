# ForeSeeMe backend image — serves the real Random Forest and runs the scheduled
# risk-compute job from the SAME image (the entrypoint is selected at run time).
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

# ML serving assets: the feature transforms (Prompt 8), pipeline config, and the
# promoted model artifact. The job also reuses cleaning/merging from ml/pipelines.
# data/ and tests/ are intentionally excluded to keep the image slim; the
# VALIDATION_ONLY disease-reference module is never imported at runtime.
COPY ml/__init__.py ./ml/__init__.py
COPY ml/pipelines ./ml/pipelines
COPY ml/config ./ml/config
COPY ml/artifacts ./ml/artifacts

# Run as a non-root user (security: never run as root).
RUN useradd --create-home --uid 1000 appuser
USER appuser

EXPOSE 8000

# Default entrypoint: the HTTP risk service (Cloud Run service).
# The scheduled batch job (Cloud Run Job / Cloud Scheduler, ADR-002) overrides the
# command with:  python -m app.jobs.compute_risk
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT}"]
