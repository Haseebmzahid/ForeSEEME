# Firestore lifecycle strategy — M7.4 (documentation only, no TTL deployed)

The M7.0 audit (gap G-11) flagged that `alertDispatchLog` and `userAlerts`
have no expiry policy and grow forever. This document designs the retention
strategy and makes the repository **TTL-ready** — it does **not** enable
Firestore's native TTL feature on any collection. That is an irreversible,
project-level configuration change (once a document's TTL field is in the
past, Firestore deletes it — deployment of a policy is explicitly excluded
from this sprint per the M7.4 brief) and should be a deliberate decision made
with the team after the FYP evaluation, not something enabled mid-sprint.

## How Firestore TTL actually works (context for the recommendations below)

A TTL policy is configured **per collection group, per field**
(`gcloud firestore fields ttls update <field> --collection-group=<name>`, or
via the Firebase console) — it is not a per-document setting and is not
expressed in `firestore.rules` or `firestore.indexes.json`. The target field
must be a `Timestamp`. Firestore deletes expired documents in the background
(typically within 24 hours of expiry, not instantly) at no additional write
cost. Enabling a policy is safe to do gradually — it starts affecting only
documents written/updated after the policy is active unless you also backfill
the field on existing docs.

## Per-collection recommendation

| Collection | TTL candidate? | Recommended field | Recommended window | Rationale |
|---|---|---|---|---|
| `alertDispatchLog` | **Yes** | `createdAt` (already present on every doc — see below) | **90 days** | Internal, service-only audit/idempotency ledger (`firestore.rules`: `allow read, write: if false`). No client ever reads it (confirmed in the M7.0 Flutter audit). Nothing in the dispatch/throttle logic needs an entry older than the 24h throttle window; the only reason to keep it longer is operator debugging/incident review. 90 days comfortably covers a semester-length evaluation period plus post-launch triage, then self-cleans. |
| `userAlerts/{uid}/items` | **Conditional — not recommended yet** | `createdAt` (already present) | If enabled: **≥ 1 year**, framed as a cost backstop, not a product feature | This is real, user-facing product data — a user's own notification history, not a log. Auto-deleting it without the user's knowledge is a product decision, not just a storage-cost one. The Notification Center's own query already windows to the 50 most recent (`firestore_user_alerts_repository.dart:24`), so old alerts are already invisible in the UI long before a TTL would ever fire — meaning there's little urgency here at current, pre-launch data volumes. Recommendation: leave TTL **off** for now; if enabled later, set the window generously (a year+) and pair it with the still-missing user-facing archive/delete affordance the M7.0 audit flagged (Sprint 6's territory), so deletion is something the product does *for* the user, not silently *to* them. |
| `riskEstimates` | **Never** | — | — | Source of truth for risk (ADR-001); the app's trend/comparison/history features read historical estimates. |
| `users` (+ `profile`, `medications`, `adherence_logs` subtrees) | **Never** | — | — | Core account data. |
| `overrides/{city}` | **Never** | — | — | Deliberately an audit trail: `docs/admin_override.md` documents that clearing an override sets `active: false` rather than deleting it, specifically so the correction history survives. A TTL would silently defeat that design goal. |
| `jobHeartbeats/{job}` | **N/A — doesn't grow** | — | — | One document per job name, overwritten in place on every run (`observability.emit()`, `id=job name`). Not a candidate: it structurally cannot accumulate, so TTL would do nothing useful here. |

## Making the repository TTL-ready

"TTL-ready" means: the moment the team decides to flip the switch, no code
changes are needed — only the two `gcloud` commands below.

- **`alertDispatchLog`**: every document already carries a top-level
  `createdAt` `Timestamp` in all four write paths —
  `_log_body()`, `_skip_log_body()`, `_crash_log_body()` (M7.4), and the
  transient `claim_dispatch()` placeholder (M7.4, field name `claimedAt` —
  overwritten by `createdAt` within the same call before any external reader
  could observe it; see `docs/dispatch_concurrency.md`). No schema change
  needed.
- **`userAlerts/{uid}/items`**: every document already carries `createdAt`
  (`_alert_body()`). No schema change needed.

When the team is ready (after evaluation, with sign-off on the retention
window):

```bash
# alertDispatchLog — recommended first candidate, 90-day window
gcloud firestore fields ttls update createdAt \
  --collection-group=alertDispatchLog \
  --project=foreseeme-83587 \
  --async

# userAlerts (only if the product decision above is revisited)
gcloud firestore fields ttls update createdAt \
  --collection-group=userAlerts \
  --project=foreseeme-83587 \
  --async
```

The "90 days" (or any window) is enforced by what value the application
writes into `createdAt` plus how the *policy* interprets it — Firestore TTL
does not take a duration parameter; it deletes a document once `createdAt`
(or whichever field) is in the *past* relative to now. To implement "delete
90 days after creation" you point the TTL field at a value that is already
`createdAt + 90 days` at write time, **not** at the raw `createdAt`
timestamp. This repo does not yet write such an `expiresAt`-style field on
`alertDispatchLog`, so enabling TTL as designed above would need one small
additive change first: write `expiresAt = createdAt + timedelta(days=90)`
alongside the existing fields (a single extra dict key, no schema
redesign) at the point TTL is actually adopted. Deliberately not added now,
to avoid shipping a dead field ahead of the actual policy decision — this
paragraph is the "when you do this" instruction for whoever picks it up.

## Summary

| Action taken this sprint | Status |
|---|---|
| Enable Firestore TTL on any collection | **Not done** — explicitly out of scope |
| Design retention windows | Done (table above) |
| Identify never-expire collections | Done: `riskEstimates`, `users`, `overrides`, `jobHeartbeats` (moot) |
| Identify TTL candidates | Done: `alertDispatchLog` (recommended), `userAlerts` (conditional, deferred) |
| Prepare schema for future TTL | Confirmed already-present (`createdAt` on both candidate collections); documented the one small additive step (`expiresAt`) needed only for `alertDispatchLog` at actual-adoption time |
