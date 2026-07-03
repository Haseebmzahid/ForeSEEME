# Backend Observability & Failure Alerting (Sprint 5, Prompt 12)

*How an operator knows the scheduled pipeline is alive and healthy — the complement
to the user-facing staleness indicator (Prompt 11).*

## Why

Silent failure of a health pipeline is dangerous (audit **H1**). If `compute_risk`
stops writing, users keep seeing **stale risk with no signal**. Prompt 11 tells the
*user* ("this estimate may be out of date"); this prompt tells the *operator* the
moment a run fails or produces nothing.

## Two signals (no new dependencies)

Every scheduled job — `compute_risk`, `dispatch_alerts`, `weekly_report` — emits two
complementary signals via the shared `app/jobs/observability.py` module. It adds **no
third-party dependency**: it reuses the existing JSON logging (`app/logging_config.py`)
and the Firebase Admin SDK already used by the jobs.

### 1. Heartbeat document — `jobHeartbeats/{job}`

One document per job (id = job name), **overwritten on every scheduled run**:

```jsonc
{
  "job": "compute_risk",
  "status": "ok",            // "ok" | "degraded" | "failed"
  "ok": true,
  "startedAt": <timestamp>,
  "finishedAt": <timestamp>,
  "durationMs": 1483,
  "total": 5,
  "counts": { "written": 5 },   // per-status tally of the run's outcomes
  "error": null                  // "TypeName: message" on a crash; never a secret
}
```

A monitor watches **two** things:

- **Last run unhealthy** — `status != "ok"` (the run failed or was degraded).
- **Dead-man switch** — `finishedAt` has not advanced within the expected cadence
  (e.g. `compute_risk` is weekly → alert if the heartbeat is older than ~9 days,
  matching `kRiskStaleAfter`). This catches the job **not running at all**, which no
  in-process log could report.

The heartbeat is written by the service account (Admin SDK bypasses rules) and is
**operator-only**: `firestore.rules` denies all client read/write to `jobHeartbeats`.
It is telemetry, not user data.

> **Backfill is excluded.** `compute_risk --backfill` is a manual operator operation,
> not the monitored weekly cadence, so it prints its own summary and writes **no**
> heartbeat (it would otherwise pollute the dead-man-switch timing).

### 2. Structured run-summary log — `event="job_run"`

`emit()` logs one JSON record per run to stdout (Cloud Logging), at **INFO** on
success and **ERROR** (with `alert=true`) on a `degraded`/`failed` run:

```jsonc
{ "message": "job_run", "event": "job_run", "job": "compute_risk",
  "status": "failed", "alert": true, "total": 0, "counts": {"error": 5},
  "durationMs": 210, "error": "RuntimeError: ..." }
```

Recommended **log-based alert policy** (no Firestore read needed):

```
resource.type="cloud_run_revision"
jsonPayload.event="job_run"
jsonPayload.alert=true
```

A crash before any outcomes are produced still emits a `failed` heartbeat + log and
then **re-raises**, so the process exits non-zero and Cloud Scheduler/Run flags the
run as well. A heartbeat-*write* failure is itself logged (`heartbeat_write_failed`)
but never raised — the log signal remains as a fallback so telemetry can't crash the
job it observes.

## Run-health grading (and the anti-noise rule)

`status` is graded per job by `classify_run(...)`, because "healthy" differs by job:

| Job | `ok` | `degraded` | `failed` |
|---|---|---|---|
| `compute_risk` | one estimate written per city, no errors | some cities written, others errored/skipped | **zero written though cities exist** (silent/empty run) or a crash |
| `dispatch_alerts` | run completed (**including zero sends**) | an FCM send actually failed | a crash |
| `weekly_report` | run completed (**including zero sends**) | an FCM send actually failed | a crash |

**Why zero sends is `ok` for dispatch/weekly (the "alert noise" risk the prompt
flags):** most dispatch runs have *no* risk transition, and most weekly runs are
mid-week idempotent skips. Alerting on "zero output" there would page the operator on
every normal run. Only `compute_risk` treats zero output as a failure, because it is
*expected* to write one estimate per city every run — that emptiness is the dangerous,
staleness-causing case.

## No secrets

Heartbeats and `job_run` logs carry only: job name, status, per-status counts,
timing, and an error *type/message* string. Never tokens, credentials, FCM payloads,
or user PII (GOLDEN_RULES §7). A test (`test_heartbeat_body_carries_no_secrets`) pins
the heartbeat's key set.

## Tests

`backend/tests/test_observability.py`:

- a successful `compute_risk` run writes an `ok` heartbeat + INFO signal;
- a **simulated failure** (all cities' fetch errors → zero written) writes a
  `failed` heartbeat + ERROR signal with `alert=true`;
- a crash emits a `failed` heartbeat, then re-raises (non-zero exit);
- `dispatch_alerts` / `weekly_report` **zero sends** grade `ok` and still write a
  heartbeat (proving the job ran);
- a heartbeat-sink failure is swallowed (the run log still fires).

## Operator runbook (summary)

1. **Alerted `alert=true` / `status=failed`** → check the `job_run` log's `error`
   and the failing job's per-item logs (`city_fetch_failed`, `users_fetch_failed`).
2. **Heartbeat stale (dead-man switch)** → the scheduled trigger didn't fire or the
   container failed to start; check Cloud Scheduler + Cloud Run job history.
3. **`compute_risk` failed/stale** → users see the Prompt-11 staleness banner; use
   the manual risk override (Prompt 13) if a correction is needed before the next run.
