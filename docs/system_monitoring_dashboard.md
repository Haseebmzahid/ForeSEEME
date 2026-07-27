# System Monitoring Dashboard (Sprint M8.1)

*The first surface of Module 8 (Admin & Analytics Panel) — SDS FR8.1.*

## What it shows

**Profile → Admin Panel → Dashboard** (`/admin/dashboard`, admins only):

| Metric | SDS FR8.1 item | Source | Honesty note |
|---|---|---|---|
| Model version + recency | "model version" | The most recently written `riskEstimates` document across all cities | Reflects the model that produced the *last computed estimate*, not a live deployment probe — see below |
| Per-job status + last run | "last run time" | `jobHeartbeats/{job}` for `compute_risk`, `dispatch_alerts`, `weekly_report` | A job that has never run shows "No data yet", never a fabricated status |
| Total alerts dispatched | "alerts count" | `alertDispatchLog` (exact `count()` aggregation) | — |
| Active users | "active users" | **None — not implemented** | Shown as an explicit "Not tracked yet" state rather than an invented number (see `docs/MODULE_8_AUDIT.md` §5, deferred deliberately) |

## Why model version comes from `riskEstimates`, not `/health`

The backend's `GET /health` endpoint does report `modelVersion`, but the app
never calls the FastAPI service directly for anything risk-related (ADR-001,
GOLDEN_RULES §4 — the app reads `riskEstimates` from Firestore only). Rather
than open a new client→backend network path just for this one field, the
dashboard reads the `modelVersion` already stamped on every risk estimate.
In practice these agree: the batch job always uses whichever model is
currently deployed. The one gap this doesn't cover — a model deployed but not
yet run — is out of scope at this project's scale.

## A deliberate Firestore-rules change

`jobHeartbeats` and `alertDispatchLog` were previously **fully service-account
only** (`allow read, write: if false`), and the emulator test suite
(`test_rules/firestore_rules.test.mjs`) explicitly asserted that the `admin`
custom claim granted no exception to this. This sprint changes that on purpose:
both collections now grant `allow read: if isAdmin()`, added as a shared
`isAdmin()` helper in `firestore.rules` (previously inlined only in the
`overrides` rule). Writes remain sealed to the service account either way — a
non-admin's access is unchanged. The updated tests (`admin (claim) may read`,
replacing the old `admin claim does not grant read` assertions) pin the new,
intended behaviour.

## The admin shell

`/admin/dashboard` and `/admin/risk-override` (Sprint 5 P13) are now both
branches of one `AdminShell` (`lib/features/admin/presentation/admin_shell.dart`)
— a `StatefulShellRoute` providing one shared app bar (title follows the active
branch) and bottom nav, so a future admin module (content management, user
management, activity log — SDS FR8.3/8.4/8.5) plugs in by adding:

1. a route + `StatefulShellBranch` in `lib/core/routes/app_router.dart`, and
2. one entry in `kAdminDestinations` (`lib/features/admin/presentation/widgets/admin_nav_destination.dart`),

without touching the shell itself. Each hosted screen still individually gates
its own content on `isAdminProvider` (unchanged from the Sprint 5 pattern) —
the shell supplies chrome only; the authoritative gate stays server-side in
`firestore.rules`.

## Architecture

- Domain: `JobHeartbeat`/`JobRunStatus`, `ModelStatus` — framework-free models
  mirroring `RiskEstimateModel`. `SystemStatusRepository` is the abstract
  interface (mirrors `RiskOverrideRepository`).
- Data: `FirestoreSystemStatusRepository` — reads only, no write path exists or
  is needed (the dashboard never mutates telemetry).
- Presentation: `system_status_providers.dart` (plain `FutureProvider`s, no
  combined view-model — each metric card independently loads/errors, matching
  how the Dashboard/RiskCard compose several independent providers rather than
  one aggregate).

## Tests

- `test_rules/firestore_rules.test.mjs` — the widened admin-read grants, and
  that non-admins/writes remain exactly as before.
- `test/features/admin/system_status_repository_test.dart` — heartbeat parsing
  (including the "never run" placeholder and a failed-run case), the alert
  count, and the latest-model-status query, against a fake Firestore.
- `test/features/admin/admin_dashboard_screen_test.dart` — the admin gate
  (shared `NotAuthorizedView`, extracted from the override screen in this
  sprint) and the honest empty/never-run states.

## What this sprint deliberately does not do

- No active-user counter (no aggregation job or counter document exists yet —
  a real design decision, not an oversight; see `docs/MODULE_8_AUDIT.md`).
- No user management (SDS FR8.5) — planned as a separate sprint in
  `docs/MODULE_8_AUDIT.md` §15, built on the shell this sprint introduces.
  (The admin activity log, FR8.4, followed in Sprint M8.2 — see
  `docs/admin_activity_log.md`; content management, FR8.3, in Sprint M8.3 —
  see `docs/resource_content_management.md`.)
