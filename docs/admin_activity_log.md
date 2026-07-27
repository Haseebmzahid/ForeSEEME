# Admin Activity Log (Sprint M8.2)

*Closes the FR8.2 business rule "All override actions must be logged" and
implements FR8.4's activity-log requirement.*

## What it is

An append-only, immutable audit trail of admin actions — `adminActivityLog/{entryId}`
— viewable at **Profile → Admin Panel → Logs** (`/admin/activity-log`, admins
only). Currently records risk-override set/clear (Sprint 5 P13); future admin
modules (content management, user management — SDS FR8.3/FR8.5) append to the
same collection via the same repository, with no change needed to the log
screen itself.

## Data model — `adminActivityLog/{entryId}` (auto-id)

| Field | Type | Notes |
|---|---|---|
| `action` | string | A short, open-ended code, e.g. `"override_set"` / `"override_clear"` — not a closed enum, so new admin modules add new codes freely |
| `target` | string | What was acted on, e.g. the city name for an override |
| `summary` | string | Human-readable one-liner shown in the log viewer, e.g. `"Set Lahore risk to High (Smog)"` |
| `authorUid` / `authorEmail` | string | Audit — from the signed-in operator, same trust model as `overrides` (client-asserted, gated by the admin claim) |
| `createdAt` | ISO-8601 UTC string | Audit |

## Security rules

```
match /adminActivityLog/{entryId} {
  allow read: if isAdmin();
  allow create: if isAdmin();
  allow update, delete: if false;
}
```

Create and read require the `admin` custom claim (same gate as `overrides`).
**Update and delete are denied unconditionally — even to an admin** — so the
trail cannot be edited or erased after the fact (SDS FR8.4 "Logs must be
immutable and securely stored"). Verified by the emulator harness
(`test_rules/firestore_rules.test.mjs`): admin create/read succeed; non-admin
create/read and unauthenticated read fail; admin update/delete on an existing
entry both fail.

## How entries get written

`AdminOverrideController` (`lib/features/admin/presentation/admin_providers.dart`)
appends one entry after each successful `submit`/`clear`, via
`AdminActivityLogRepository.append`. The append is **best-effort**: a failure
is caught and swallowed rather than surfaced, because the override write has
already succeeded by that point and the operator's safety-valve action must
never be blocked by a logging outage — the same principle the backend already
applies to job heartbeats (`backend/app/jobs/observability.py`: "telemetry
must never crash the job it observes"). A dedicated test
(`AdminOverrideController a logging failure never fails the underlying
override write`) pins this.

## Where it surfaces

- **Admin Logs screen** (`AdminActivityLogScreen`) — a third branch of
  `AdminShell` (alongside Dashboard and Override), newest-first, capped at the
  100 most recent entries (a conscious bounded-list choice, not paginated —
  matches the project's existing precedent for other admin-facing lists at
  this scale). Empty state reads "No admin actions yet" rather than an error.

## Architecture

- Domain: `AdminActivityLogEntry` — framework-free, mirrors `RiskOverride` /
  `JobHeartbeat`. `AdminActivityLogRepository` is the abstract interface
  (append + recent only — no update/delete method exists at any layer, mirroring
  the rules' immutability).
- Data: `FirestoreAdminActivityLogRepository` — `add()` (auto-id) for append,
  `orderBy(createdAt desc).limit(n)` for recent.
- Presentation: `activity_log_providers.dart` (repository provider +
  `recentActivityLogProvider`); `AdminOverrideController` invalidates that
  provider after a successful append so the Logs screen reflects a just-taken
  action without a manual refresh.

## Tests

- `test/features/admin/admin_activity_log_repository_test.dart` — append/read
  round-trip, newest-first ordering, the `limit` parameter, the empty case,
  and Timestamp normalisation.
- `test/features/admin/admin_activity_log_screen_test.dart` — the admin gate
  (shared `NotAuthorizedView`), the empty state, and rendering multiple
  entries newest-first.
- `test/features/admin/risk_override_test.dart` (`AdminOverrideController`
  group) — submit/clear each append a correctly-stamped entry, and a logging
  failure never fails the underlying override write.
- `test_rules/firestore_rules.test.mjs` — the full rule surface above,
  including both immutability assertions.

## Relation to other Module 8 work

See `docs/MODULE_8_AUDIT.md` §15 for the full roadmap. This sprint also
positions FR8.3 (content management) and FR8.5 (user management) to log to
this same collection when they're built — no schema or rule change will be
needed for them, only new `action` codes.
