"""Structured (JSON) logging setup for the risk service.

Emits one JSON object per log record to stdout so logs are machine-parseable by
Cloud Run / Cloud Logging. A small custom formatter is used instead of adding a
third-party logging dependency.
"""

from __future__ import annotations

import json
import logging
from datetime import datetime, timezone

# Standard LogRecord attributes; anything else passed via `extra=` is treated as
# a structured field and merged into the JSON payload.
_RESERVED_ATTRS = frozenset(logging.makeLogRecord({}).__dict__.keys()) | {
    "message",
    "asctime",
    "taskName",
}


class JsonLogFormatter(logging.Formatter):
    """Formats log records as single-line JSON objects."""

    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, object] = {
            "timestamp": datetime.fromtimestamp(
                record.created, tz=timezone.utc
            ).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        # Merge any structured fields supplied via `logger.info(..., extra={...})`.
        for key, value in record.__dict__.items():
            if key not in _RESERVED_ATTRS and not key.startswith("_"):
                payload[key] = value
        if record.exc_info:
            payload["exc_info"] = self.formatException(record.exc_info)
        return json.dumps(payload, default=str)


def configure_logging(level: str = "INFO") -> None:
    """Install the JSON formatter on the root logger.

    Idempotent: replaces existing handlers so repeated calls (e.g. across the
    app factory and tests) do not duplicate log lines.

    Args:
        level: Log level name, e.g. ``"INFO"`` or ``"DEBUG"``.
    """
    handler = logging.StreamHandler()
    handler.setFormatter(JsonLogFormatter())

    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(level.upper())
