# Alert Dispatch — Design & Contract (Sprint 4, Prompt 1)

**Status: FROZEN.** The dispatch engine (P2–P3), in-app handling (P4), and inbox
(P5) build against this. Nothing here is engine code; this is the contract.

The engine is a **backend scheduled Cloud Run job** (`backend/app/jobs/dispatch_alerts.py`,
sibling of `compute_risk`) using the firebase-admin service account. **Flutter never
runs dispatch logic.** Risk comes only from Firestore `riskEstimates` (ADR-001).

---

## 1. Inputs (all read via Admin SDK)

| Source | Path | Used for |
|---|---|---|
| Latest + previous risk | `riskEstimates/{city}_{YYYY-MM-DD}` (two most recent per city) | transition detection, disease/driver |
| Health profile | `users/{uid}/profile/{uid}` → `city`, `chronicConditions` | city match + vulnerability (playbook's "healthProfiles") |
| Token + preferences | `users/{uid}` → `fcmToken`, `notificationPreferences` | delivery + consent |
| Throttle/idempotency ledger | `alertDispatchLog/{logId}` | dedupe + 24h throttle |

> The risk **driver** is taken from the estimate's `disease` (see the
> disease→category map in §5), not re-derived, so targeting is deterministic.

---

## 2. Targeting predicate

A user `u` (in city `c`) is alerted for the latest estimate `e` (new level
`L_new`, disease `D`) **iff all four hold**:

1. **Transition into an enabled band.** A previous estimate `e_prev` exists with
   level `L_prev`, and `band(L_new) > band(L_prev)` **and** the severity of
   `L_new` is enabled in the user's preferences:
   - `band`: `Low=1 < Medium=2 < High=3`.
   - severity enabled: `High → highRiskAlerts`, `Medium → mediumRiskAlerts`,
     `Low → lowRiskUpdates`.
   - i.e. risk **rose** this cycle to a level the user opted into. Steady risk
     (`band(L_new) == band(L_prev)`) or a drop never triggers. *(No daily spam.)*
2. **Vulnerability.** `D` maps to a **risk-driver category** `cat` (§5) and `u`
   has a chronic condition in `cat` (condition→category map, §5). The matched
   `cat` is the alert's `category`.
3. **Category consent.** `notificationPreferences.conditions[cat] == true`.
4. **Deliverable.** `users/{uid}.fcmToken` is present and non-empty.

If any fails → **skip** (audited with the reason). A user with no matching
condition, a disabled category, a disabled severity, or steady/falling risk
receives nothing.

---

## 3. Throttle & idempotency

Two independent gates, checked **before** sending:

- **Idempotency (per estimate).** The dispatch is keyed to the *specific* risk
  estimate so a job re-run for the same estimate never re-sends:

  ```
  logId = "{uid}__{riskEstimateId}__{category}"
        = "{uid}__{city}_{YYYY-MM-DD}__{category}"
  ```

  where `riskEstimateId` is the estimate's document id (`{city}_{date}`). If an
  `alertDispatchLog/{logId}` already exists → **skip (idempotent)**. The log is
  written for every attempt (sent *or* skipped), so re-runs short-circuit.

- **Throttle (per user × category).** Even across different estimates, at most
  **one delivered alert per `(uid, category)` per rolling 24h**. Before sending,
  query `alertDispatchLog` for a `status == "sent"` entry with the same `uid` +
  `category` and `createdAt >= now − 24h`; if found → **skip (throttled)**.

`throttleWindowEnd = createdAt + 24h` is stored to make the window query simple.

Ordering: transition → vulnerability → consent → **idempotency** → **throttle** →
send. The send and the two writes (`alertDispatchLog`, `userAlerts`) are the only
mutations; everything before is read-only.

---

## 4. Schemas (every field)

### 4.1 `alertDispatchLog/{logId}` — ops audit + throttle ledger (service-only)

`logId` = the idempotency key from §3.

| Field | Type | Notes |
|---|---|---|
| `uid` | string | recipient |
| `city` | string | estimate city |
| `category` | string | matched condition category (`respiratory` \| `cardiovascular`) |
| `riskEstimateId` | string | `{city}_{YYYY-MM-DD}` (the specific estimate) |
| `generatedAt` | string (ISO-8601 UTC) | estimate's `generatedAt` |
| `previousRiskLevel` | string | `Low`\|`Medium`\|`High` (`L_prev`) |
| `riskLevel` | string | `L_new` |
| `disease` | string | from the estimate |
| `driver` | string | risk-driver category label (e.g. `Air quality`, `Heat`) |
| `modelVersion` | string | estimate's `modelVersion` |
| `status` | string | `sent` \| `skipped_no_transition` \| `skipped_no_match` \| `skipped_disabled` \| `skipped_idempotent` \| `skipped_throttled` \| `failed` \| `token_invalid` |
| `reason` | string | short human explanation |
| `recommendationId` | string \| null | cited advisory id used (see `recommendation_rules.md`) |
| `fcmMessageId` | string \| null | FCM message id on success |
| `createdAt` | timestamp (server) | attempt time |
| `throttleWindowEnd` | timestamp | `createdAt + 24h` |

### 4.2 `userAlerts/{uid}/items/{alertId}` — in-app inbox (service write, owner read)

`alertId` = the same idempotency key (`{uid}__{riskEstimateId}__{category}`) so an
inbox entry is 1:1 with a delivered alert.

| Field | Type | Notes |
|---|---|---|
| `title` | string | calm, e.g. "Air quality rising in Lahore" |
| `body` | string | one-line summary |
| `category` | string | `respiratory` \| `cardiovascular` |
| `city` | string | |
| `riskLevel` | string | `L_new` |
| `disease` | string | |
| `recommendation` | map | `{ id, text, source, sourceUrl }` — a **cited** lookup (`recommendation_rules.md`), never generated |
| `deepLink` | string | in-app route, e.g. `/risk-map`, `/resources`, `/nearby-hospitals` |
| `riskEstimateId` | string | `{city}_{date}` |
| `createdAt` | timestamp (server) | |
| `read` | bool | default `false` |
| `readAt` | timestamp \| null | set when marked read |

Only the engine creates these (Admin SDK). The owner may **read** and **mark read**
(update `read`/`readAt` only); never create, delete, or edit content.

---

## 5. Condition → risk-driver mapping (targeting)

Maps the estimate's `disease` to a **risk-driver category**, and the user's
chronic conditions to the same categories. Categories align with the Sprint 3
`notificationPreferences.conditions` keys (`respiratory`, `cardiovascular`).
Citations: see `docs/recommendation_rules.md`.

**Disease → category**

| `disease` (riskEstimates) | Driver | Category |
|---|---|---|
| `Smog` | Air quality (PM2.5/PM10) | `respiratory`, `cardiovascular` |
| `Respiratory Illness` | Air quality | `respiratory` |
| `Influenza` | Respiratory (seasonal) | `respiratory` |
| `Heat-Related Illness` | Heat | `cardiovascular` |
| `Dengue` | Vector-borne | *(no chronic-condition driver in scope — not condition-targeted)* |

**Chronic condition → category** (`kChronicConditions`)

| Condition | Category | Basis |
|---|---|---|
| `Asthma` | `respiratory` | air-pollution trigger (WHO/CDC) |
| `Heart Disease` | `cardiovascular` | PM2.5 + heat cardiovascular risk (EPA/WHO) |
| `Hypertension` | `cardiovascular` | heat + air-pollution cardiovascular risk (WHO) |
| `Diabetes` | `cardiovascular` | impaired heat tolerance (CDC extreme heat) |
| `None` | — | no vulnerability mapping |

A user is **vulnerable** to estimate `e` when the disease's category set
intersects the user's conditions' category set. `Dengue` maps to no in-scope
chronic condition, so it is not condition-targeted in Sprint 4 (documented gap).

---

## 6. Firestore rules (additive — both new collections)

```
// alertDispatchLog — service-only (Admin SDK bypasses rules). No client access:
match /alertDispatchLog/{logId} {
  allow read, write: if false;
}

// userAlerts — engine writes (Admin); owner reads; owner may only mark-read:
match /userAlerts/{userId}/{document=**} {
  allow read:   if request.auth != null && request.auth.uid == userId;
  allow create, delete: if false;
  allow update: if request.auth != null
                && request.auth.uid == userId
                && request.resource.data.diff(resource.data)
                     .affectedKeys().hasOnly(['read', 'readAt']);
}
```

Existing rules (`riskEstimates` read, `users/{uid}` owner subtree) are untouched.
Rule tests: `test_rules/firestore_rules.test.mjs` (run on the Firestore emulator).

---

## 7. Sprint 1–3 invariants preserved

- No `riskEstimates` / ML / `compute_risk` / prediction-contract changes.
- No client-side dispatch; engine is backend + service account.
- No new client collections beyond `userAlerts` reads; `alertDispatchLog` is
  never client-visible.
- Additive rules only; deployed file is root `firestore.rules`.
