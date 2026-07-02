# Proactive Dispatch Engine — Gap Audit (Sprint 5, Prompt 1)

*Read-only investigation. No production code was modified. Every conclusion below is traced through the actual execution path and cited to file:line.*

**Audit question (SPRINT_5_AUDIT §0):** Does a scheduled engine that pushes personalized, transition-triggered, throttled alerts to users *without them opening the app* exist and work?

**Headline answer:** The proactive loop is **built, wired end-to-end, and covered by tests** — substantially more complete than SPRINT_5_AUDIT §0 assumed. The audit's premise ("the alert engine appears to have been displaced in the reshuffle") is **incorrect for this codebase**: Sprint 4 shipped the full dispatch engine (`backend/app/jobs/dispatch_alerts.py`) plus in-app foreground/background/terminated handling and an inbox. The genuine remaining gaps are **operational, not architectural**: the scheduled *trigger* is not committed as infrastructure-as-code, and real-device end-to-end delivery is unproven.

**Therefore Sprint 5 Prompt 2 should take the HARDEN path, not the BUILD path.**

---

## 1. Verdict Summary Table

| Capability | Status | Primary evidence |
|---|:---:|---|
| Scheduled dispatch job (code) | **PRESENT** | `backend/app/jobs/dispatch_alerts.py:102` (`run`), `:474` (`main`) |
| Scheduled dispatch job (live trigger / IaC) | **NOT VERIFIED** | No committed Cloud Scheduler/cron/Terraform; only `compose.yaml:39` intent |
| Transition detection | **PRESENT** | `targeting.py:102` `risk_rose`; gate at `dispatch_alerts.py:130` |
| Targeting by vulnerability + preference | **PRESENT** | `targeting.py:131` `evaluate` |
| 24h throttle | **PRESENT** | `throttle.py:38`; ledger read `dispatch_alerts.py:417` `recently_sent` |
| Idempotency (per-estimate) | **PRESENT** | `dispatch_alerts.py:228` `dispatch_key`; check `throttle.py:48` |
| Audit log (`alertDispatchLog`) | **PRESENT** | `dispatch_alerts.py:199,234,290`; rules `firestore.rules:36` |
| Token pruning | **PRESENT** | `dispatch_alerts.py:208–211,433` `prune_token` |
| In-app foreground handling | **PRESENT** | `fcm_message_handler.dart:42`; `firebase_push_messaging_service.dart:29` |
| In-app background-tap handling | **PRESENT** | `onMessageOpenedApp` → `fcm_message_handler.dart:45` |
| In-app terminated-launch handling | **PRESENT** | `getInitialMessage` → `fcm_message_handler.dart:47` |
| In-app **background data-only** handler | **ABSENT** | No `FirebaseMessaging.onBackgroundMessage` registered anywhere in `lib/` |
| Alert inbox (`userAlerts`) | **PRESENT** | `alert_inbox_screen.dart`; `firestore_user_alerts_repository.dart`; rules `firestore.rules:44` |
| Real-device end-to-end delivery | **NOT VERIFIED** | No device e2e; Sprint 3 close-out still lists device e2e as outstanding |

Acceptance-criteria mapping (Prompt 1 requires an explicit PRESENT/ABSENT for each): scheduled dispatch job **PRESENT (code) / NOT VERIFIED (live trigger)**; transition detection **PRESENT**; targeting by vulnerability + preference **PRESENT**; 24h throttle **PRESENT**; idempotency **PRESENT**; audit log **PRESENT**; token pruning **PRESENT**; in-app foreground/background/terminated **PRESENT** (background-tap + terminated-launch; background *data-only* processing **ABSENT**); alert inbox **PRESENT**.

---

## 2. Capability-by-Capability Findings

### 2.1 Scheduled dispatch job — PRESENT (code) / NOT VERIFIED (live trigger)

- **Files:** `backend/app/jobs/dispatch_alerts.py`, `backend/compose.yaml:33–48`, `backend/app/jobs/__init__.py`.
- **Execution path:** `main()` (`:474`) → `init_firestore()` (`:441`, service-account **or** emulator, mirroring `compute_risk`) → `run(...)` (`:102`) over `clean.load_cities()`. It is a standalone module entrypoint (`python -m app.jobs.dispatch_alerts`, `:495`), a true sibling of Sprint 2's `compute_risk`, and has its own Docker Compose job entry `dispatch-alerts-job` (`compose.yaml:39`, `profiles: ["jobs"]`).
- **Fully implemented?** The **job** is Fully Implemented and matches ADR-002's scheduled-compute pattern. Flutter never dispatches (Admin SDK only) — architectural invariant upheld.
- **Production gap:** the **actual schedule** is not in the repository. `compose.yaml:36` documents "the Cloud Scheduler → Cloud Run Job entrypoint" as *intent*, but there is **no committed Cloud Scheduler config, Terraform, `gcloud` script, cron file, or GitHub Actions workflow** (`.github/workflows` does not exist; no `*.tf`; `backend/scripts/` holds only a seed script). Identical posture to `compute_risk`, so this is a pre-existing convention rather than a new regression — but it means the loop does **not fire on its own** without out-of-repo cloud configuration, which cannot be verified from the codebase.

### 2.2 Transition detection — PRESENT

- **Files:** `targeting.py:98–104`, invoked `dispatch_alerts.py:130`.
- **Path:** per city, `history.latest_two(name)` (`:120`) returns the two newest estimates; `targeting.risk_rose(previous, latest)` (`:130`) requires the severity band to have **strictly increased** (`BAND` = Low 1 / Medium 2 / High 3, `targeting.py:19`). A city with no upward transition is skipped (`:131 city_skipped_no_transition`); insufficient history (`< 2` docs) is skipped (`:127`). This is genuine transition-triggering, not per-run resend — the central anti-spam mechanism.

### 2.3 Targeting by vulnerability + preference — PRESENT

- **File:** `targeting.py:131–163` (`evaluate`), a pure predicate.
- **Path (all four contract conditions must hold):** (1) `risk_rose` transition; (2) `severity_enabled(level, preferences)` — the matching `highRiskAlerts`/`mediumRiskAlerts`/`lowRiskUpdates` toggle must be on (`:107`, `:51`); (3) vulnerability ∩ disease category **and** per-category consent — `user_categories(conditions) & disease_categories(disease)`, then filtered by `preferences["conditions"][category]` (`:148–152`); (4) a delivery token exists (`:145`). Multi-category users collapse to one deterministic alert via `CATEGORY_PRIORITY` (`:48`, `:124`). Condition→category, disease→category, and disease→driver maps are frozen from the contract (`targeting.py:19–55`).

### 2.4 24-hour throttle — PRESENT

- **Files:** `throttle.py`, `dispatch_alerts.py:167`, `:417` (`recently_sent`), `firestore.indexes.json` (composite index).
- **Path:** `throttle.evaluate` (`throttle.py:38`) returns `SKIP_THROTTLED` when a `status == "sent"` log exists for `(uid, category)` within the rolling 24h window (`recently_sent`, `dispatch_alerts.py:417`, backed by the `(uid, category, status, createdAt)` composite index at `firestore.indexes.json:12`). `THROTTLE_WINDOW = timedelta(hours=24)` (`throttle.py:21`). A throttled attempt is **audited but not delivered** and writes no inbox doc (`dispatch_alerts.py:182–191`, `_skip_log_body:290`).

### 2.5 Idempotency (keyed to the specific estimate) — PRESENT

- **Files:** `dispatch_alerts.py:228` (`dispatch_key`), `throttle.py:48` (`has_dispatch`).
- **Path:** the log id is `f"{uid}__{risk_estimate_id}__{category}"` (`:231`) — derived from the *specific* `riskEstimates` doc id (`{city}_{YYYY-MM-DD}`). `throttle.evaluate` checks `has_dispatch(log_id)` **first** (`throttle.py:48`) and returns `SKIP_IDEMPOTENT`, leaving the original log intact and sending nothing (`dispatch_alerts.py:174–181`). A re-run over identical estimates therefore re-sends **nothing**. This is the decisive spam-safety guarantee and it is proven by test (§3).

### 2.6 Audit log (`alertDispatchLog`) — PRESENT

- **Files:** `dispatch_alerts.py:199,234` (`_log_body`), `:290` (`_skip_log_body`), `:402` (Firestore writer), `firestore.rules:33–39`.
- **Path:** every **send attempt** writes a log doc keyed by `log_id` (sent / token_invalid / failed, `:199`); every **throttled** attempt writes a suppressed-audit doc (`:183`). The log captures uid, city, category, `riskEstimateId`, previous→current level, disease, driver, model version, status, reason, recommendationId, `fcmMessageId`, `createdAt`, `throttleWindowEnd` (`:241–258`). Rules make it **service-account-only** — no client read/write (`firestore.rules:36–38`), correct because it holds cross-user targeting data.
- **Nuance (by design, not a gap):** an **idempotent-skip does not write a new log** (`:174–181`) — intentional, to preserve the original attempt record. Only `sent`/`failed`/`token_invalid`/`throttled` produce log writes.

### 2.7 Token pruning — PRESENT

- **Files:** `dispatch_alerts.py:208–211` + `:433` (`prune_token`); classification `messaging.py:82–88`.
- **Path:** `FirebaseAdminFcmSender.send` maps `messaging.UnregisteredError` (and "token…invalid" errors) to `SendResult(status="token_invalid")` (`messaging.py:82–88`); the engine then calls `repository.prune_token(uid)` which deletes the `fcmToken` field via `firestore.DELETE_FIELD` (`:436`). Proven pruned-exactly-once across re-runs by test (§3).

### 2.8 In-app foreground / background / terminated handling — PRESENT (with one narrow gap)

- **Files:** `lib/features/alerts/presentation/services/fcm_message_handler.dart`, `.../data/services/firebase_push_messaging_service.dart`, `main.dart:53–57`, `alerts_providers.dart:53–62`.
- **Wiring:** `main.dart:56` calls `ref.read(fcmMessageHandlerProvider).start()` in a post-first-frame callback (so a terminated-launch tap can route once the GoRouter is ready). `start()` (`fcm_message_handler.dart:38`) is idempotent and subscribes all three states:
  - **Foreground:** `onForegroundMessage` (`FirebaseMessaging.onMessage`) → `AlertPresenter.showForegroundAlert` (`fcm_message_handler.dart:42`; `firebase_push_messaging_service.dart:29`).
  - **Background tap:** `onMessageOpened` (`FirebaseMessaging.onMessageOpenedApp`) → `_route` → `AlertDeepLinkRouter.resolve` → `navigate` (`fcm_message_handler.dart:45,53`).
  - **Terminated launch tap:** `getInitialMessage` (`FirebaseMessaging.getInitialMessage`) → `_route` (`fcm_message_handler.dart:47`).
- **Gap — background *data-only* handler ABSENT:** there is **no top-level `FirebaseMessaging.onBackgroundMessage(...)` handler** registered anywhere in `lib/` (verified by grep). This is **low-impact** because the engine sends **notification** messages (`messaging.Notification`, `messaging.py:76`), which Android/iOS render in the system tray automatically while backgrounded/terminated — the tap is then handled by the paths above, and `POST_NOTIFICATIONS` is present in the merged manifest. The absent handler only matters for silent/data-only background processing (e.g. pre-fetching inbox state before the user taps), which the current design does not require. Note: `firebase_push_messaging_service.dart:7–9` still carries a **stale docstring** ("registers no message handlers… receiving is Sprint 4") that contradicts the now-implemented streams — cosmetic only.

### 2.9 Alert inbox (`userAlerts`) — PRESENT

- **Files:** `alert_inbox_screen.dart`, `firestore_user_alerts_repository.dart`, `alerts_providers.dart:64–117`, `firestore.rules:40–52`, `firestore.indexes.json`.
- **Path:** the backend writes `userAlerts/{uid}/items/{logId}` on a successful send (`dispatch_alerts.py:203,405`, shape `_alert_body:261`). The app reads via `FirestoreUserAlertsRepository.watchAlerts` (live snapshot, newest-first) → `userAlertsStreamProvider` (auth-scoped, `alerts_providers.dart:81`) → `AlertInboxScreen`. `markRead` updates only `read`/`readAt` (`firestore_user_alerts_repository.dart:37`). Unread badge via `unreadAlertCountProvider` (`:97`). Rules enforce **owner-read + mark-read-only** and forbid client create/delete (`firestore.rules:44–52`). The inbox renders full unhappy paths — `BrandLoading` / `OfflineState` / `ErrorState` / `EmptyState` (`alert_inbox_screen.dart:48–63`).

---

## 3. Existing Test Coverage of Dispatch

Dispatch is **well covered**, including the decisive repeated-run spam test that Sprint 5 Prompt 2 names as its acceptance guard.

**Backend (`backend/tests/`):**
- `test_e2e_dispatch.py` — full multi-city/multi-user pipeline. Asserts **only vulnerable+consenting users are alerted** (`test_pipeline_targets_only_vulnerable_consenting_users`), **five back-to-back runs still send exactly 2** (`test_repeated_runs_produce_no_spam_and_no_duplicates`, all re-runs `skipped_idempotent`), **a new within-24h estimate is throttled** (`test_second_event_within_24h_is_throttled_end_to_end`), and **an invalid token is pruned exactly once** (`test_invalid_token_pruned_once_across_reruns`). This is precisely the SPRINT_5 Prompt 2 acceptance test — **already implemented**.
- `test_dispatch_alerts.py` — engine orchestration units.
- `test_throttle.py` — idempotency-first-then-throttle decision matrix.
- `test_targeting.py` — the four-condition predicate.
- `test_recommendation_lookup.py` — deterministic cited lookup (no generated medical text).

**Flutter (`test/features/alerts/`, `test/integration/`):**
- `test/integration/alert_pipeline_e2e_test.dart` — seeds the **exact backend `_alert_body` shape** into a fake Firestore and drives the **real** read path (repository → provider → `AlertInboxScreen`): inbox appearance, user-scoping, unread→read persistence, and the deep-link engagement hook.
- `fcm_message_handler_test.dart` — foreground/opened/terminated routing with fakes.
- `alert_deep_link_router_test.dart`, `alert_analytics_test.dart`, `user_alerts_test.dart`, `alerts_test.dart`, `notification_preferences_test.dart`.

**Not covered by any test:** the live scheduled trigger, real-device FCM transport, and the absent background data-only handler.

---

## 4. Production Gaps & Missing Safeguards

1. **No committed scheduled trigger (operational).** The job runs only when invoked; there is no in-repo Cloud Scheduler/Terraform/cron/CI to fire it weekly. Until that exists (or is verified in the cloud console), the "proactive without opening the app" claim is **unproven in production**. *(Same convention as `compute_risk`.)*
2. **Real-device end-to-end delivery NOT VERIFIED.** All e2e proof is offline (fakes/emulator). Device FCM delivery, notification-channel behaviour, and iOS APNs config are untested — consistent with Sprint 3's still-open "device e2e" item.
3. **No background data-only handler** (`onBackgroundMessage`). Low impact given notification-type payloads, but note it if any future feature needs silent background processing.
4. **No observability/failure alerting on the dispatch job** (SPRINT_5 Phase 5 / Prompt 12 — explicitly out of Prompt 1 scope). A silent scheduler failure would leave users un-alerted with no operator signal; the audit log records attempts but nothing watches for *absence* of a run.
5. **Stale docstring** in `firebase_push_messaging_service.dart:7–9` (says it registers no handlers). Cosmetic; fix opportunistically during the harden pass.

---

## 5. Additional Observations (outside Prompt 1 scope — not to be fixed here)

- **Expired Firestore catch-all rule.** `firestore.rules` ends with `match /{document=**} { allow read, write: if request.time < timestamp.date(2026, 6, 1); }`. That date has **passed** (today is 2026-07-02), so the wildcard now **denies** by default. The explicit `alertDispatchLog` and `userAlerts` matchers precede it and govern those collections, so dispatch is unaffected — but any collection relying on the wildcard is now locked. This matches the previously-recorded "expired-wildcard caveat" and warrants a project-wide rules review (not a dispatch task).
- **`progress.md` is stale** (reports "60–70% features complete") and contradicts the shipped Sprint 4 code; treat code + tests as ground truth, not `progress.md`.
- **`compute_risk` shares the same un-committed-scheduler posture** — if Sprint 5 hardens the dispatch trigger, apply the same treatment to the risk-compute job for consistency.

---

## 6. Recommended Sprint 5 Action per Capability

| Capability | Status | Sprint 5 action |
|---|:---:|:---:|
| Dispatch job (code) | PRESENT | **No Action** |
| Dispatch live trigger / IaC | NOT VERIFIED | **Harden** (commit the schedule or document the verified cloud config) |
| Transition detection | PRESENT | **No Action** |
| Targeting (vulnerability + preference) | PRESENT | **No Action** |
| 24h throttle | PRESENT | **No Action** |
| Idempotency | PRESENT | **No Action** |
| Audit log | PRESENT | **No Action** |
| Token pruning | PRESENT | **No Action** |
| Foreground / background-tap / terminated-launch | PRESENT | **No Action** |
| Background data-only handler | ABSENT | **Harden** (add only if a data-only use case emerges; else document as intentional) |
| Alert inbox | PRESENT | **No Action** |
| Real-device e2e delivery | NOT VERIFIED | **Harden** (device smoke test on a real project) |
| Job observability / failure alerting | ABSENT | **Build** — but this is **Phase 5 / Prompt 12**, not Prompt 2 |

**Net for Prompt 2:** take the **HARDEN** branch, not BUILD. The dispatch prompts in `docs/SPRINT_4.md` are already executed and green. The hardening pass should: (a) commit or verify the scheduled trigger; (b) run one real-device delivery smoke test; (c) fix the stale docstring; (d) optionally decide on the background data-only handler. The spam-safety two-run test that Prompt 2 mandates **already exists** (`test_e2e_dispatch.py::test_repeated_runs_produce_no_spam_and_no_duplicates`) — re-running it satisfies the acceptance criterion immediately.

---

## 7. Overall Audit Confidence

**High** for all logic that is unit/integration-tested and traceable end-to-end in-repo: the engine, targeting, throttle, idempotency, audit log, token pruning, in-app routing, and inbox are demonstrably present, wired, and tested. Confidence rests on read code + passing-by-construction tests, not on a live run.

**Areas requiring manual verification (cannot be confirmed from the codebase):**
1. **Is the job actually scheduled in the cloud?** — inspect the deployed Cloud Scheduler / Cloud Run Job (no IaC in-repo to confirm).
2. **Does a real device receive an alert?** — perform a device smoke test; confirm APNs/iOS config and the Android notification channel.
3. **Are the Firestore composite index and current rules deployed to the live project** (not just present in `firestore.indexes.json` / `firestore.rules`)? The expired catch-all rule (§5) especially warrants a console check.

*No production code was created or modified during this audit. This document is the only deliverable for Prompt 1.*
