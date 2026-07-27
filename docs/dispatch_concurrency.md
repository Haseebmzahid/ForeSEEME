# Dispatch concurrency — M7.4

Investigates whether two overlapping executions of `dispatch_alerts.run()`
could both send a duplicate FCM alert for the same `(uid, riskEstimateId,
category)`, and documents the fix. Read this alongside
`docs/alert_dispatch_design.md` (the frozen targeting/throttle contract,
unchanged by this work) and `backend/deploy/README.md` (the production
scheduling posture).

## The race

Before M7.4, `_dispatch()` did:

1. `throttle.evaluate()` → `has_dispatch(log_id)` (a plain read).
2. If absent: build the notification, call `sender.send()` (network I/O —
   the slowest step), **then** `write_dispatch_log(log_id, ...)`.

Steps 1 and 3 are not atomic with each other. If two executions of the job
were running at the same time and reached the same `(uid, riskEstimateId,
category)`, both could observe `has_dispatch(log_id) == False` before either
one's `write_dispatch_log` landed — both would then call FCM, and the user
would receive the alert twice. The final `alertDispatchLog` document would
still look correct (`.set()` is last-write-wins, so only one, valid-looking
entry remains) — the duplicate would be invisible in the audit log even
though it happened. This is why the M7.0 audit flagged it as a real, if
easy-to-miss, gap.

## Is this reachable in production?

Investigated the actual provisioning config (`backend/deploy/`) rather than
assuming worst-case:

- **Cloud Scheduler → Cloud Run Jobs `:run`**: `common.sh`'s
  `create_or_update_scheduler` does not set `--max-retry-attempts`, so the
  Cloud Scheduler default applies (`retryCount: 0` — no automatic retry on a
  failed trigger call). The scheduler itself will not automatically fire a
  second, overlapping execution.
- **Cloud Run Job task retry**: `provision_dispatch_alerts.sh` sets
  `--max-retries=1`. This is Cloud Run's *task*-level retry — it only starts
  a retry attempt after the previous attempt has finished (crashed/failed),
  never in parallel with a still-running attempt. Not a concurrency source.
- **Tasks/parallelism**: no `--tasks` / `--parallelism` flag is set, so the
  job runs Cloud Run's default of one task, no in-execution fan-out.

**Conclusion: nothing in the current automatic scheduling path can trigger
two overlapping executions on its own.** The one realistic way to get two
concurrent executions is a **human** manually re-triggering the job (e.g.
`gcloud run jobs execute` or re-running `deploy/verify_dispatch_alerts.sh`)
while a scheduled or prior manual run is still in flight — plausible during
development, demo rehearsal, or incident response, not something the system
does to itself.

## Why we fixed it anyway, and why the fix is small

Per the M7.4 brief: if the job were airtight-guaranteed single-instance, the
right call would be to document the invariant and rely on monitoring rather
than add transactional complexity. That's *not quite* the situation here —
a manual double-trigger is a plausible operator mistake, not a hypothetical,
and this is a two-person FYP team who will manually re-run this exact job for
demos and debugging throughout the remaining evaluation period. The blast
radius of getting it wrong (a real, duplicate push notification to a real
user) is small but user-visible, and the fix that closes it is genuinely
small — so we implemented it rather than only documenting around it.

**Fix: `DispatchRepository.claim_dispatch(log_id, now) -> bool`** (additive
Protocol method, `backend/app/jobs/dispatch_alerts.py`). Implemented via a
real Firestore transaction in `FirestoreDispatchRepository`:

```python
@firestore.transactional
def _claim(transaction):
    snapshot = doc_ref.get(transaction=transaction)
    if snapshot.exists:
        return False
    transaction.set(doc_ref, {"status": "claimed", "claimedAt": now})
    return True
```

`_dispatch()` calls `claim_dispatch()` immediately after the existing
(unchanged) `throttle.evaluate()` gate and before building/sending the
notification. Only the caller that wins the claim proceeds; a losing caller
returns `skipped_idempotent` — exactly the same outcome a genuinely-later
re-run already produced before this change. `write_dispatch_log()` then
overwrites the placeholder with the real, final body once the send outcome
is known, so the document a reader eventually sees is byte-for-byte the same
shape as before M7.4.

**Crash safety**: if `sender.send()` raises unexpectedly after a successful
claim (the real `FirebaseAdminFcmSender` never raises — see M7.3 — but the
`FcmSender` Protocol doesn't forbid a future implementation from doing so),
`_dispatch()` catches it and writes a terminal `status: "failed"` log entry
via `_crash_log_body()`, so the claim is always finalized. A permanently
"claimed"-but-never-finalized document would otherwise silently block every
future run from ever alerting that `(uid, riskEstimateId, category)` again —
a worse bug than the one being fixed.

## What did NOT change

- `throttle.py` / `throttle.evaluate()` — untouched, same tests, same
  behavior. The cheap `has_dispatch` pre-check it performs is still useful
  as a fast path; `claim_dispatch` is the atomic backstop for the one moment
  it actually matters.
- The idempotency key format (`{uid}__{riskEstimateId}__{category}`) —
  unchanged.
- The final `alertDispatchLog` / `userAlerts` document schemas — unchanged.
  Only a brief, internal, never-externally-read intermediate state
  (`{"status": "claimed", "claimedAt": ...}`) exists between the claim and
  the finalize write within a single `_dispatch()` call.
- The `DispatchRepository` Protocol grew by one additive method, consistent
  with how Sprint 4 Prompt 3 added `has_dispatch` / `recently_sent` /
  `prune_token` the same way. No repository was redesigned.

## Known, deliberately out-of-scope residual gap

`backend/app/jobs/weekly_report.py` has its own, separately-implemented
`_dispatch_one()` with the same shape: `has_dispatch()` check, then send,
then `write_dispatch_log()`, non-atomic. It is **not** fixed by this change
— `weekly_report` runs weekly (far lower overlap probability), was not the
collection/flow the M7.0 audit's G-6 finding cited, and touching it would
widen this sprint's footprint beyond "the dispatch flow." Flagged here for
whoever picks up weekly_report hardening next; the fix would be the same
shape (`claim_dispatch`, reusing the same `DispatchRepository` protocol
method dispatch_alerts.py now defines).

## Recommendation: monitor, don't just trust

The claim mechanism prevents duplicate sends outright, so monitoring is a
secondary safety net rather than the primary control. Still worth knowing if
overlapping executions are actually occurring in production (it would
indicate an operational habit worth correcting, e.g. someone routinely
re-triggering while a run is still active): the existing `jobHeartbeats` /
`alertDispatchLog` observability (`docs/observability.md`) already has
everything needed — two `job_run` log events for `dispatch_alerts` with
overlapping `startedAt`/`finishedAt` windows on the same day would be the
signal. No new observability code is proposed here; this is a "look at logs
if curious" note, not a new alert to build.
