"""Scheduled-job observability: heartbeats + a monitorable failure signal (Sprint 5, Prompt 12).

Silent failure of a health pipeline is dangerous (audit H1): if ``compute_risk``
stops writing, users would keep seeing stale risk with no operator signal. This
module gives every scheduled job (``compute_risk``, ``dispatch_alerts``,
``weekly_report``) two complementary, dependency-free signals an operator can watch:

* a **heartbeat document** at ``jobHeartbeats/{job}``, overwritten on every scheduled
  run with the run's status, timing and per-status counts. A monitor watches two
  things:
    - a run whose ``status != "ok"`` (the last run failed or was degraded), and
    - a heartbeat whose ``finishedAt`` has not advanced within the expected cadence
      (a **dead-man switch**: the job did not run at all).
* a **structured run-summary log** (``event="job_run"``) emitted at INFO on success and
  ERROR (with ``alert=true``) on a failed/degraded run, so a Cloud Logging log-based
  alert policy can fire without reading Firestore.

The user-facing complement is the Prompt-11 staleness indicator: this tells the
*operator*; that tells the *user*.

No secrets are logged or written — only the job name, status, per-status counts,
timing, and an error *type/message* string (never credentials, tokens, or payloads).
This module never imports Flutter and adds no third-party dependency (it reuses the
existing :mod:`app.logging_config` JSON logging).
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any, Protocol

#: One monitored document per job, keyed by the job name (latest run overwrites).
HEARTBEAT_COLLECTION = "jobHeartbeats"

# Run health, in increasing severity.
#   ok       — completed as expected.
#   degraded — completed, but with per-item errors/skips worth a look (not paging).
#   failed   — produced nothing it should have, or crashed; the operator must act.
STATUS_OK = "ok"
STATUS_DEGRADED = "degraded"
STATUS_FAILED = "failed"


class HeartbeatSink(Protocol):
    """Overwrites the single monitored heartbeat document for a job."""

    def write_heartbeat(self, job: str, body: dict[str, Any]) -> None: ...


@dataclass
class RunReport:
    """The outcome of one scheduled run — the heartbeat body + the alert signal."""

    job: str
    status: str
    started_at: datetime
    finished_at: datetime
    counts: dict[str, int] = field(default_factory=dict)
    error: str | None = None

    @property
    def total(self) -> int:
        return sum(self.counts.values())

    @property
    def ok(self) -> bool:
        return self.status == STATUS_OK

    @property
    def duration_ms(self) -> int:
        return max(0, int((self.finished_at - self.started_at).total_seconds() * 1000))

    def to_document(self) -> dict[str, Any]:
        """The heartbeat document body (no secrets — safe, structured fields only)."""
        return {
            "job": self.job,
            "status": self.status,
            "ok": self.ok,
            "startedAt": self.started_at,
            "finishedAt": self.finished_at,
            "durationMs": self.duration_ms,
            "total": self.total,
            "counts": dict(self.counts),
            "error": self.error,
        }


def count_by_status(outcomes: list[Any]) -> dict[str, int]:
    """Tally a list of ``*Outcome`` objects (each with a ``.status``) by status."""
    counts: dict[str, int] = {}
    for outcome in outcomes:
        counts[outcome.status] = counts.get(outcome.status, 0) + 1
    return counts


def failed_report(
    job: str, started_at: datetime, finished_at: datetime, error: str
) -> RunReport:
    """A ``failed`` report for a run that crashed before producing outcomes."""
    return RunReport(job, STATUS_FAILED, started_at, finished_at, error=error)


def emit(report: RunReport, *, sink: HeartbeatSink, logger: logging.Logger) -> None:
    """Write the heartbeat document and the structured run-summary log.

    A heartbeat-write failure marks the caller's report failed and emits an
    alert. The fallback log still fires; the stored document shape is unchanged.
    """
    try:
        sink.write_heartbeat(report.job, report.to_document())
    except Exception as exc:  # retain the fallback signal and expose failure
        report.status = STATUS_FAILED
        report.error = f"heartbeat_write_failed: {type(exc).__name__}"
        logger.error(
            "heartbeat_write_failed",
            extra={"job": report.job, "error": type(exc).__name__},
        )

    level = logging.INFO if report.ok else logging.ERROR
    logger.log(
        level,
        "job_run",
        extra={
            "event": "job_run",
            "startedAt": report.started_at.isoformat(),
            "finishedAt": report.finished_at.isoformat(),
            "heartbeatWritten": report.error is None or not report.error.startswith("heartbeat_write_failed:"),
            "job": report.job,
            "status": report.status,
            "alert": not report.ok,  # log-based alert policies match alert==true
            "total": report.total,
            "counts": report.counts,
            "durationMs": report.duration_ms,
            "error": report.error,
        },
    )


# --- Firestore sink (service account; lazy firebase import) -----------------


class FirestoreHeartbeatSink:
    """Writes ``jobHeartbeats/{job}`` via the Admin SDK (service account bypasses
    rules; clients are denied by ``firestore.rules``)."""

    def __init__(self, db: Any) -> None:
        self._db = db

    def write_heartbeat(self, job: str, body: dict[str, Any]) -> None:
        self._db.collection(HEARTBEAT_COLLECTION).document(job).set(body)


def init_firestore_heartbeat_sink() -> FirestoreHeartbeatSink:
    """Build a :class:`FirestoreHeartbeatSink` from the already-initialised Admin
    SDK app (the job initialises Firebase before calling this)."""
    from app.jobs.firestore_runtime import get_firestore_client

    return FirestoreHeartbeatSink(get_firestore_client())
