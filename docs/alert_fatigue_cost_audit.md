# Alert Fatigue & Cost Audit — Sprint 4 (Prompt 9)

**Purpose.** Prove the dispatch engine is *respectful* (no alert fatigue) and
*cheap* (bounded, predictable FCM volume) before it is scheduled. This note is
the engagement-safeguard record for the Sprint 4 exit criteria; every claim below
is backed by a test named in the "evidence" column.

---

## 1. Fatigue safeguards (why the app won't spam)

The engine only ever sends on a **rising transition into an enabled band**, to a
**vulnerable + consenting** user, at most **once per (user, category) per 24h**,
and **once per specific estimate** (idempotent). Four independent gates must all
pass before a single push is sent.

| Safeguard | Rule | Effect on volume | Evidence |
|---|---|---|---|
| Transition-triggering | send only if `band(new) > band(prev)` | steady/falling risk → **0** sends (no daily drip) | `test_targeting`, `test_e2e_dispatch::…targets_only_vulnerable_consenting_users` |
| Vulnerability match | disease driver category ∩ user chronic-condition category | non-matching users → **0** | `test_targeting`, e2e |
| Consent | `notificationPreferences.conditions[cat]` **and** severity toggle | disabled category/severity → **0** | `test_dispatch_alerts::disabled_category…`, e2e |
| Deliverable | non-empty `fcmToken` | tokenless users → **0** | e2e (`no_token` user) |
| Idempotency (per estimate) | key `{uid}__{riskEstimateId}__{category}` checked before send | job re-runs → **0 extra** | `test_e2e_dispatch::repeated_runs_produce_no_spam…` (5 runs → 2 sends) |
| 24h throttle (per user×category) | one `sent` per rolling 24h | second within-window event → **0** | `test_e2e_dispatch::second_event_within_24h_is_throttled…` |

**Repeated-run spam check (headline result).** Running the identical schedule
**5×** over a 3-city / 6-user fixture yields exactly **2** deliveries and **2**
inbox docs — every re-run is short-circuited as `skipped_idempotent`. No
duplicates, no spam.

## 2. Cost / volume review

FCM sends are free at Google's current pricing; the real cost is Cloud Run
compute per run and the risk of unbounded fan-out. Both are bounded by design:

- **Upper bound per run:** ≤ `1 send per (targeted user)`, and targeting narrows
  recipients to *(users in a transitioning city) ∩ vulnerable ∩ consenting ∩
  tokened*. Cities without a rising transition are skipped before any user is
  read.
- **Per-user ceiling:** the 24h throttle caps a user at **1 alert per category
  per day** regardless of how many estimates land.
- **Idempotency:** partial failures / retries never double-charge a send.
- **Token hygiene:** unregistered tokens are pruned on the first `token_invalid`
  response (`test_e2e_dispatch::invalid_token_pruned_once…`), so dead tokens stop
  consuming send attempts and stop skewing delivery metrics.
- **Audit ledger:** every attempt (sent *or* skipped) writes one
  `alertDispatchLog` doc — O(attempts) writes, the analytics source for volume.

**Worst-case estimate (FYP scale).** With ~5 supported cities and a small user
base, a single run's fan-out is at most the number of consenting vulnerable users
in cities that rose this cycle — realistically tens, hard-capped by the 24h
throttle. Well within Cloud Run's free tier.

## 3. Engagement measurement

Deep-link opens are recorded via the `AlertAnalytics` seam
(`logAlertOpened(route, source)`) from **both** entry points — a push tap
(`source: push`) and an inbox tap (`source: inbox`). Read against
`alertDispatchLog` send volume, this gives an open-rate signal to tune targeting
later. The default sink logs to the debug console; production can swap it via
`alertAnalyticsProvider` without touching call sites.

## 4. Residual risks / follow-ups

- **Cross-device duplicate delivery** (same user, multiple devices) is out of
  scope — Sprint 4 stores a single `fcmToken`. Multi-token fan-out is future work.
- **Timezone of the 24h window** uses UTC `createdAt`; acceptable for the weekly
  batch cadence.
- **Manual verification remaining:** on-device delivery in all three app states,
  and API-key/service-account restriction (tracked in `architecture.md`).

**Conclusion.** Under repeated runs and within-window events the engine produces
**no spam and no duplicates**, prunes dead tokens, and keeps fan-out bounded and
cheap — the engagement safeguards for the Sprint 4 exit criteria are met.
