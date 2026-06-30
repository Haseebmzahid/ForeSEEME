"""Throttle + idempotency gate for the dispatch engine (Sprint 4, Prompt 3).

Pure decision logic over the ``alertDispatchLog`` ledger (read seam injected), so
it is deterministic and testable without Firestore. Two guards, in order
(contract §3):

1. **Idempotency** — if a log already exists for this dispatch key (derived from
   the *specific* risk estimate), the job already attempted it → skip. This makes
   a re-run for the same estimate send nothing new.
2. **Throttle** — otherwise, if a ``sent`` alert exists for this ``(uid,
   category)`` within the rolling 24h window → skip. At most one delivered alert
   per user per category per day.
"""

from __future__ import annotations

from datetime import datetime, timedelta
from enum import Enum
from typing import Protocol

THROTTLE_WINDOW = timedelta(hours=24)


class ThrottleDecision(Enum):
    ALLOW = "allow"
    SKIP_IDEMPOTENT = "skipped_idempotent"
    SKIP_THROTTLED = "skipped_throttled"


class DispatchLedger(Protocol):
    """Read side of ``alertDispatchLog`` used by the gate."""

    def has_dispatch(self, log_id: str) -> bool: ...

    def recently_sent(self, uid: str, category: str, since: datetime) -> bool: ...


def evaluate(
    ledger: DispatchLedger,
    *,
    uid: str,
    category: str,
    log_id: str,
    now: datetime,
    window: timedelta = THROTTLE_WINDOW,
) -> ThrottleDecision:
    """Idempotency first, then the 24h throttle; else allow the send."""
    if ledger.has_dispatch(log_id):
        return ThrottleDecision.SKIP_IDEMPOTENT
    if ledger.recently_sent(uid, category, now - window):
        return ThrottleDecision.SKIP_THROTTLED
    return ThrottleDecision.ALLOW
