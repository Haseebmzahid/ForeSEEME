# Manual Risk Override / Admin Fallback (Sprint 5, Prompt 13)

*The long-flagged safety valve (audit H2): when the scheduled pipeline lags or
errs, an authorised operator can transparently correct a city's displayed risk.*

## Principles

- **Never fabricate or overwrite genuine data.** Overrides live in a **separate**
  `overrides` collection; the model's `riskEstimates` documents and history are
  never mutated. When an override is cleared, the genuine estimate shows again.
- **Always indicate.** An active override is surfaced with a clear "Operator-set"
  label, the reason, the author, and — for honesty — the automated model estimate
  it supersedes. It is never applied silently (the risk the prompt flags).
- **Restricted to an admin role.** Writes require an `admin` custom claim,
  enforced server-side by Firestore rules; the in-app admin surface only reveals
  itself to admins and additionally fails closed.
- **Minimal internal surface.** One guarded screen (city, level, disease, reason,
  submit/clear) — no dashboards or batch tooling.

## Data model — `overrides/{city}`

One document per city (id = city name); a new write supersedes the previous one.

| Field | Type | Notes |
|---|---|---|
| `city` | string | = document id |
| `riskLevel` | `"Low"｜"Medium"｜"High"` | the operator-set level shown |
| `disease` | string | kept consistent with the risk surfaces |
| `reason` | string | **required**; shown to users (audit) |
| `authorUid` | string | audit — from the signed-in operator, never client-supplied |
| `authorEmail` | string | audit |
| `createdAt` | ISO-8601 UTC string | audit |
| `active` | bool | `false` when cleared (record preserved as an audit trail) |
| `expiresAt` | ISO-8601 UTC string｜null | optional safety auto-expiry |

An override is applied only when `active == true` **and** it has not passed
`expiresAt` (`RiskOverride.isActive`) — a forgotten override cannot mask a
recovered pipeline forever.

## Security rules

```
match /overrides/{city} {
  allow read: if request.auth != null;                              // indicate to users
  allow write: if request.auth != null && request.auth.token.admin == true;  // operators only
}
```

Verified by the emulator harness (`test_rules/firestore_rules.test.mjs`): admin
(claim) create succeeds; authenticated read succeeds; non-admin write/update and
unauthenticated read are denied.

## Granting operator access

Custom claims can only be set by the Admin SDK:

```bash
GOOGLE_APPLICATION_CREDENTIALS=/path/sa.json python backend/scripts/set_admin_claim.py operator@example.com
```

The user refreshes their token (the app force-refreshes when reading the claim).

## Where it surfaces

- **Dashboard `RiskCard`** — the operator value replaces the at-a-glance headline,
  labelled "Operator-set", with the reason and the superseded automated estimate.
- **Risk Details** — a prominent `RiskOverrideNotice` banner above the (still
  visible, still labelled) automated model detail.
- **Admin surface** — `/admin/risk-override`, reachable from Profile only for
  admins; shows the current override for the selected city with a **Clear** action.

The override overlay is **best-effort**: if the override read fails, the risk
surfaces fall back to the genuine estimate rather than erroring.

## Architecture

- Model + read/write repository live in the **risk** feature
  (`RiskOverride`, `RiskOverrideRepository` / `FirestoreRiskOverrideRepository`),
  since the risk surfaces consume the read path; read providers in
  `risk_override_provider.dart`.
- The **admin** feature holds the gate (`AdminRepository.isCurrentUserAdmin` via
  the `admin` claim), the write controller (`AdminOverrideController`), and the
  guarded screen. No Firebase in the UI (GOLDEN_RULES §3).

## Relation to other Sprint-5 work

The override is the operator's *corrective* fallback; the Prompt-11 **staleness
indicator** is the user-facing signal that an estimate is old, and Prompt-12
**observability** is how an operator learns a run failed in the first place.
