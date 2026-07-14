# ForeSeeMe — Sprint 6 Engineering Execution Roadmap
### Companion to the Sprint 6 Playbook · Optimized for iterative development with Claude Code
**Rule of the document:** one phase = one Claude Code session = one reviewed commit. No code appears in this roadmap.

---

## 0. How to Use This Roadmap with Claude Code

### 0.1 Session protocol (repeat for every phase)
1. **Start clean:** `git status` clean, on a fresh branch `sprint6/PH-XX-slug` cut from `main`.
2. **Prompt template** (paste, fill brackets):
   > You are implementing Phase PH-XX of the ForeSeeMe Sprint 6 roadmap. Read the following before writing anything: [paste the phase block], plus §4.2 of the Playbook (architecture rules). Constraints: modify ONLY the files listed in "Files expected to change" (create-only where marked NEW); do not touch domain entities, backend code, or any file owned by the other track; use design tokens for all colors/spacing/durations; all async UI renders from a single AsyncValue envelope. When done: run `flutter analyze` and `flutter test`, show me the output, and stop for review before committing.
3. **Review gate (human):** diff inspected against the phase's file list; verification checklist executed; only then commit with the phase's message.
4. **Merge to main immediately** after review. Small, fast-merging phases are the anti-merge-conflict strategy — long-lived branches are forbidden.
5. If a phase balloons: stop, split it, do not "just finish it" in one giant commit.

### 0.2 Guardrails to give Claude Code in every session (the standing constraints)
- Never modify files outside the phase's file list. If a change *seems* required elsewhere, stop and report — that usually means the phase decomposition missed a dependency.
- Never add a package without stopping to ask (Playbook §4.2 rule 6).
- Never introduce `Color(0x`, raw `Duration(milliseconds:` or magic paddings in `lib/features/**` — tokens only.
- Widgets → providers → use cases → repository interfaces. No shortcuts, even for one field.
- Do not reformat or "clean up" files not in scope (that is how merge conflicts are manufactured).

### 0.3 Merge-conflict avoidance by construction (file ownership)
After the Foundation track merges (PH-00…PH-07), the two parallel tracks own **disjoint directories**:

| Track | Owner | Owned paths (exclusive write access) |
|---|---|---|
| Foundation (serial) | Both, paired | `lib/core/**`, `lib/app/**` (router, shell), `tools/**`, platform config |
| Track A — Risk | Dev A | `lib/features/risk/**`, `lib/features/heatmap/**` (or the repo's equivalent) |
| Track B — Notifications | Dev B | `lib/features/notifications/**` |
| Convergence (serial) | Both | Everything, checklist-driven |

The only shared-file phases after foundation are PH-18 (badge touches the shell) and PH-24 (deep links touch the router) — both are Track B phases explicitly scheduled when Track A has no open PR against those files. Every phase below flags shared-file risk where it exists.

### 0.4 Path assumptions (verify in PH-00, then fix globally)
This roadmap assumes a structure like `lib/core/{theme,ui,routing,providers}` and `lib/features/<feature>/{presentation,application,domain,data}`. **PH-00 records the repo's real structure**, and every subsequent phase's file list is interpreted against it. If the repo layers differently (e.g., top-level `lib/domain`, `lib/data`), keep the *layer semantics* of each file list and translate paths — do not restructure the repo to match this document.

### 0.5 Verification standard (applies to every phase, in addition to per-phase checks)
- `flutter analyze`: **0 errors, 0 warnings**; info-level count ≤ baseline recorded in PH-00.
- `flutter test`: all existing tests pass (no deletions/skips without written justification); new tests as specified per phase.
- App boots to home on the physical demo device (smoke run) for any phase touching runtime code.
- Both themes checked for any phase producing visible UI.
- Screenshot captured at merge for any user-visible phase (report material, per Playbook §11).

### 0.6 Commit & rollback conventions
- **Commit format:** `type(scope): PH-XX — summary` (Conventional Commits; types: `feat`, `refactor`, `chore`, `fix`, `test`, `perf`, `docs`).
- **Rollback default:** every phase is a single commit on main ⇒ `git revert <sha>` restores the previous state cleanly. Phases with non-code side effects (Firestore rules, seeded data, platform config) specify an *additional* rollback step. There are **no schema migrations anywhere in this sprint** (additive-only guarantee), so no phase has irreversible data effects.

---

## TRACK 0 — FOUNDATION (serial · both devs · Week 1, days 1–4)

---

### PH-00 · Repo Audit & Baseline
**Objective.** Freeze ground truth before any change: real directory structure, real Firestore schemas (RiskEstimates, notifications, adherence logs — field names copied from deployed backend code, not memory), current lint/test baseline, router and FCM handler inventory (find duplicate handlers now, per Playbook M-4), confirm Firestore offline persistence setting, and record the demo device model.
**Files expected to change.**
- NEW `docs/sprint6/BASELINE.md` (structure map, schema snapshots, analyze/test counts, device, FCM handler locations, Firestore rules excerpt for notification read-state)
- NEW `docs/sprint6/` copies of the Playbook and this Roadmap
**Dependencies.** None. **Blocks everything.**
**Verification checklist.** Schemas verified against backend source ✓ · duplicate FCM handlers listed (or "none") ✓ · rules permit owner update of notification read flag: YES/NO recorded (feeds PH-17) ✓ · analyze/test baseline numbers written down ✓.
**Analyze.** Baseline recorded; nothing may worsen it later. **Tests.** Baseline pass count recorded; no new tests.
**Commit.** `docs(sprint6): PH-00 — repo audit, schema snapshots, quality baseline`
**Rollback.** `git revert` (docs only; zero runtime risk).

---

### PH-01 · Design Tokens
**Objective.** Implement Playbook P0-1 tokens as code: seeded M3 color schemes (light+dark) with semantic risk tokens (`riskLow/Medium/High` + container/on-color variants), type scale, spacing/radius constants, motion durations & curves. No screen consumes them yet — this phase is pure additive foundation.
**Files expected to change.**
- NEW `lib/core/theme/app_colors.dart`, `app_typography.dart`, `app_spacing.dart`, `app_motion.dart`, `risk_semantics.dart` (ThemeExtension for risk tokens)
- NEW `test/core/theme/risk_semantics_test.dart` (both themes resolve all risk tokens; contrast sanity assertions where practical)
**Dependencies.** PH-00.
**Verification checklist.** Contrast ≥ 4.5:1 text / 3:1 graphics for risk tokens in both themes (external checker, values noted in BASELINE.md) ✓ · zero imports from `features/` into `core/theme` ✓ · no existing file modified ✓.
**Analyze.** Clean; no new infos. **Tests.** New token tests pass; total = baseline + new.
**Commit.** `feat(theme): PH-01 — design tokens (color, type, spacing, motion, risk semantics)`
**Rollback.** `git revert`; nothing depends on it yet by construction.

---

### PH-02 · Theme Assembly + Gallery Screen
**Objective.** Build light/dark `ThemeData` entirely from PH-01 tokens; wire into the app root (respecting system theme + any existing user preference); add a debug-only Gallery screen rendering all tokens/components for visual review (grows in PH-03/04).
**Files expected to change.**
- NEW `lib/core/theme/app_theme.dart`
- NEW `lib/core/ui/gallery/gallery_screen.dart` (debug-flag gated)
- MODIFIED app root widget (theme wiring only — single-purpose diff) and route table (one debug route)
**Dependencies.** PH-01. **Shared-file note:** touches app root — schedule before tracks fork.
**Verification checklist.** Runtime theme switch re-renders correctly ✓ · existing screens still render (they inherit the new theme — visually *different* is expected, *broken* is not; note regressions for later phases rather than fixing out-of-scope) ✓ · gallery renders in both themes ✓.
**Analyze.** Clean. **Tests.** Existing pass; smoke widget test that app builds with both themes (NEW `test/core/theme/app_theme_test.dart`).
**Commit.** `feat(theme): PH-02 — M3 theme assembly from tokens + debug gallery`
**Rollback.** `git revert` restores prior theme wiring in one step.

---

### PH-03 · Core Components I (surfaces & structure)
**Objective.** `AppCard`, `StatusChip`, `SectionHeader`, `AppListTile` per Playbook P0-2 — fixed token-derived styling, no call-site restyling. Register each in the gallery.
**Files expected to change.**
- NEW `lib/core/ui/app_card.dart`, `status_chip.dart`, `section_header.dart`, `app_list_tile.dart`
- MODIFIED `gallery_screen.dart`
- NEW `test/core/ui/` widget tests (render both themes; StatusChip renders all three risk levels with icon+text, asserting the "never color alone" rule structurally)
**Dependencies.** PH-02.
**Verification checklist.** Gallery review by both devs ✓ · touch targets ≥ 48 dp where interactive ✓ · no feature imports ✓.
**Analyze.** Clean. **Tests.** New widget tests pass.
**Commit.** `feat(ui): PH-03 — core components: card, status chip, section header, list tile`
**Rollback.** `git revert` (additive; gallery is the only consumer).

---

### PH-04 · Core Components II (state family + connectivity)
**Objective.** `SkeletonLoader` (shape-mirroring shimmer, reduced-motion fallback), `EmptyState`, `ErrorState(onRetry)`, `OfflineBanner` + a single connectivity provider (per Playbook §4.2 judgment note). Gallery entries incl. a reduced-motion toggle demo.
**Files expected to change.**
- NEW `lib/core/ui/skeleton_loader.dart`, `empty_state.dart`, `error_state.dart`, `offline_banner.dart`
- NEW `lib/core/providers/connectivity_provider.dart`
- MODIFIED `gallery_screen.dart`; NEW widget tests (ErrorState retry callback fires; skeleton static under disabled animations)
**Dependencies.** PH-03. If `connectivity_plus` (or equivalent) is absent, this is the sprint's one pre-authorized dependency addition — justify in PR per §4.2 rule 6.
**Verification checklist.** Airplane-mode toggling shows/hides banner live ✓ · skeleton honors `MediaQuery.disableAnimations` ✓ · no infinite-rebuild from connectivity stream (DevTools check) ✓.
**Analyze.** Clean. **Tests.** New widget tests pass.
**Commit.** `feat(ui): PH-04 — state components (skeleton, empty, error, offline) + connectivity provider`
**Rollback.** `git revert`; remove the dependency line if it was added in this phase.

---

### PH-05 · App Shell & Typed Routes
**Objective.** M3 `NavigationBar` (5 destinations per Playbook P0-3), typed/named route table where every detail screen is addressable with ID parameters (deep-link precondition), M3 fade-through tab transitions, badge *slot* on Notifications destination (wired live in PH-18 — render 0/hidden for now).
**Files expected to change.**
- MODIFIED/NEW `lib/app/router.dart` (or repo equivalent), shell scaffold widget
- MODIFIED screens only where their route registration changes (no visual edits)
**Dependencies.** PH-02. **Shared-file note:** last broad-touch phase before tracks fork — merge same day.
**Verification checklist.** Every screen reachable via typed route with params ✓ · Android "Don't keep activities" survival ✓ · tab state preserved per M3 expectations ✓ · smoke run on device ✓.
**Analyze.** Clean. **Tests.** Existing pass; NEW route-table unit test (every declared route resolves; unknown route → fallback).
**Commit.** `feat(app): PH-05 — M3 navigation shell + typed route architecture`
**Rollback.** `git revert`; router is one file, revert is clean.

---

### PH-06 · App Identity (icon, splash, About)
**Objective.** Adaptive icon, themed Android-12 splash (no white flash), app display name, About screen (version/team/supervisor/university) reachable from Profile.
**Files expected to change.**
- Platform config: `android/**` (manifest, res, splash), `ios/**` if applicable, `pubspec.yaml` (assets)
- NEW `lib/features/profile/presentation/about_screen.dart` (+ one route line)
**Dependencies.** PH-05.
**Verification checklist.** Cold start on demo device: splash → home, no white flash, no layout jump ✓ · icon correct on device launcher (OEM check per Playbook P0-3 risk) ✓ · About shows real version from package info ✓.
**Analyze.** Clean. **Tests.** Existing pass (platform-config heavy; widget test for About screen renders).
**Commit.** `feat(app): PH-06 — app icon, themed splash, About screen`
**Rollback.** `git revert` **plus** verify a clean rebuild (`flutter clean`) since platform resources cache; keep pre-phase icon assets in git history, nothing else needed.

---

### PH-07 · Demo Seeding Harness + Demo Script
**Objective.** Playbook M-5 in full: `tools/` seeding script writing schema-exact documents (from PH-00 snapshots) for scenarios `demo-standard`, `edge-stale`, `edge-empty`, `edge-lowconfidence`, plus an "interesting adherence week" preset (feeds PH-30); idempotent; plus the written demo script + pre-demo checklist.
**Files expected to change.**
- NEW `tools/seed/**` (script + scenario fixtures + README)
- NEW `docs/sprint6/DEMO_SCRIPT.md`
- **Zero files under `lib/`** (hard rule — the app must not know seeding exists).
**Dependencies.** PH-00 (schemas). Independent of PH-01…06 — can run in parallel by Dev B.
**Verification checklist.** Each scenario one command ✓ · re-run safe (idempotent upserts) ✓ · seeded docs indistinguishable from backend-written docs (field-by-field diff vs a real doc) ✓ · app renders seeded data with **zero app-code changes** ✓.
**Analyze.** N/A for app (`lib/` untouched — verify with `git diff --stat`). **Tests.** App suite untouched and passing.
**Commit.** `chore(tools): PH-07 — Firestore demo seeding harness (4 scenarios) + demo script`
**Rollback.** `git revert`; data rollback = each scenario writes under the demo account/city namespace only, and the script includes a `--wipe-demo` mode (part of AC) to remove exactly what it created.

**⛳ GATE 1 (end Week 1):** PH-00…07 merged to main. Tracks A and B fork. From here Dev A and Dev B run phases concurrently — their file lists never intersect except where flagged.

---

## TRACK A — RISK EXPERIENCE (Dev A · Week 2 · owns `lib/features/risk/**`, `lib/features/heatmap/**`)

---

### PH-08 · Risk Application Layer Additions
**Objective.** All additive domain/application plumbing for the dashboard, before any UI: value objects (`RiskTrend`, `RiskFactor`, `RiskFreshness`), use cases `GetRiskHistory(city, limit)`, `GetRiskTrend` (derives ↑→↓ from last two estimates), `GetRiskExplanationFactors` (maps stored environmental fields → display factors, per PH-00 schema truth), `GetRecommendationsFor(riskLevel, conditions)`; repository interface methods + data-layer query implementations (additive only). Includes the **honesty-rule handling**: absent probability field ⇒ model exposes `confidence == null`, never a default.
**Files expected to change.**
- MODIFIED risk repository interface (domain) — additive methods only
- MODIFIED risk repository impl (data) — new queries only
- NEW application-layer use case files + domain value objects
- NEW unit tests: trend derivation (all transitions incl. missing-history), factor mapping (incl. missing fields), recommendations rule table
**Dependencies.** PH-00 (schema truth). No UI dependencies.
**Verification checklist.** No existing method signature changed ✓ · no widget imports anywhere in this diff ✓ · null-confidence path unit-tested ✓ · queries verified against seeded data (PH-07) in a scratch run ✓.
**Analyze.** Clean. **Tests.** **This phase is test-heavy by design** — new unit tests are the phase's main deliverable alongside the code; all pass.
**Commit.** `feat(risk): PH-08 — risk trend/factor/recommendation use cases + additive repo queries`
**Rollback.** `git revert`; purely additive, zero consumers yet.

---

### PH-09 · Dashboard View-Model & Notifier
**Objective.** One screen-level Notifier composing PH-08 use cases into a single immutable view-model (`AsyncValue<RiskDashboardViewModel>`) so the screen gets exactly one skeleton→content transition (Playbook M-1 rule). Includes staleness computation (36 h threshold) and a ticking relative-time source.
**Files expected to change.**
- NEW `lib/features/risk/presentation/risk_dashboard_view_model.dart`, `risk_dashboard_notifier.dart` (+ providers file)
- NEW notifier unit tests with mocked use cases (loading→data, error, stale, null-confidence compositions)
**Dependencies.** PH-08.
**Verification checklist.** View-model is a pure data class (no Firestore/DTO types leak into presentation) ✓ · one provider per stream, no duplicate listeners (Riverpod inspector) ✓ · refresh path defined ✓.
**Analyze.** Clean. **Tests.** New notifier tests pass.
**Commit.** `feat(risk): PH-09 — dashboard view-model + notifier (single AsyncValue envelope)`
**Rollback.** `git revert`; old screen still renders from its previous provider until PH-10 swaps it.

---

### PH-10 · Hero Risk Card + Freshness
**Objective.** Rebuild the dashboard's top section: hero risk surface on semantic tokens (city, level, generated headline), live "Updated X h ago" with visible degradation past staleness (Playbook M-1 items 1 & 4). Screen now reads from the PH-09 notifier; sections below remain as-is until their phases.
**Files expected to change.**
- MODIFIED `lib/features/risk/presentation/risk_dashboard_screen.dart` (top section + provider swap)
- NEW `widgets/hero_risk_card.dart`, `freshness_label.dart`
- NEW widget tests: three risk levels × both themes; stale style asserted
**Dependencies.** PH-09; PH-03 components; PH-07 (`edge-stale` scenario for manual verify).
**Verification checklist.** Three levels via seeding ✓ · stale scenario shows warning treatment ✓ · relative time updates on screen without full rebuild storms ✓.
**Analyze.** Clean. **Tests.** New widget tests pass.
**Commit.** `feat(risk): PH-10 — hero risk card + freshness with staleness degradation`
**Rollback.** `git revert` restores prior top section and provider wiring in one step.

---

### PH-11 · Confidence Visualization + Trend Indicator
**Objective.** Segmented confidence arc/bar from the real stored probability with one-line info affordance; trend chip (icon + text + color, never color alone). Honesty rule enforced in UI: `confidence == null` ⇒ element absent entirely.
**Files expected to change.**
- NEW `widgets/confidence_indicator.dart`, `trend_chip.dart`; MODIFIED dashboard screen (insert section)
- NEW widget tests: null-confidence hides element; trend chip exposes text semantics for all three directions
**Dependencies.** PH-10; PH-07 `edge-lowconfidence`.
**Verification checklist.** Real probability displayed (cross-check one seeded doc by hand) ✓ · info affordance readable via TalkBack ✓ · low-confidence scenario reviewed ✓.
**Analyze.** Clean. **Tests.** New tests pass.
**Commit.** `feat(risk): PH-11 — confidence visualization + trend indicator (honesty rule enforced)`
**Rollback.** `git revert`; section is self-contained.

---

### PH-12 · Explanation Rows + Environment Tiles
**Objective.** "Why this risk?" rows from stored factors (section hides when factors empty — no placeholder lies) and AQI/weather tiles with EPA band labels (Playbook M-1 items 5–6).
**Files expected to change.**
- NEW `widgets/risk_factors_section.dart`, `environment_tiles.dart`, small AQI-band mapping in application layer (pure function + unit test)
- MODIFIED dashboard screen
**Dependencies.** PH-10.
**Verification checklist.** Empty-factors seeding hides section cleanly ✓ · AQI band boundaries unit-tested (edge values) ✓ · tiles legible at 1.3× font scale ✓.
**Analyze.** Clean. **Tests.** AQI band unit tests + widget tests pass.
**Commit.** `feat(risk): PH-12 — explanation factors section + AQI/weather tiles`
**Rollback.** `git revert`.

---

### PH-13 · Recommendation Cards + Quick Action
**Objective.** Horizontally scrollable, condition-aware recommendation cards (PH-08 use case); "Take now" quick action wired to the existing adherence use case with optimistic update + revert-with-snackbar (Playbook §4.2 rule 3 pattern — this phase establishes the canonical optimistic pattern Track B will mirror).
**Files expected to change.**
- NEW `widgets/recommendation_cards.dart`, `quick_dose_action.dart`; MODIFIED dashboard screen
- NEW widget test: optimistic flip + simulated failure revert
**Dependencies.** PH-12; existing adherence use case (read-only dependency — Dev A does not modify medication feature files; if a use case is missing there, stop and coordinate, per §0.2 guardrail).
**Verification checklist.** Optimistic take-now reconciles on forced failure (airplane mode) with explanatory snackbar ✓ · recommendations change with seeded chronic-condition profile ✓ · horizontal list has no overflow at 1.3× scale ✓.
**Analyze.** Clean. **Tests.** New tests pass.
**Commit.** `feat(risk): PH-13 — recommendation cards + optimistic quick dose action`
**Rollback.** `git revert`; adherence write path unchanged (pre-existing use case).

---

### PH-14 · Dashboard State Family + Section Skeletons
**Objective.** Full four-state coverage for the dashboard using core components: mirrored skeleton (matching final card layout), error-with-retry, offline banner integration, single-beat skeleton→content transition. This closes Playbook M-1 AC 1/3/5.
**Files expected to change.**
- MODIFIED dashboard screen + NEW `widgets/dashboard_skeleton.dart`
**Dependencies.** PH-10…13 complete (skeleton mirrors final layout — cannot precede it).
**Verification checklist.** All four states switchable via PH-07 scenarios + airplane mode ✓ · one-frame-batch content reveal (no element pop-in) ✓ · DevTools: no red frames on scroll (demo device) ✓ · both themes ✓.
**Analyze.** Clean. **Tests.** Widget test: error state exposes retry; retry triggers notifier refresh.
**Commit.** `feat(risk): PH-14 — dashboard state coverage + mirrored skeleton`
**Rollback.** `git revert`.

---

### PH-15 · Heatmap Visual Polish
**Objective.** Desaturated map style (light+dark variants), risk overlays recolored from semantic tokens at spec opacity, persistent legend chip row, camera-to-profile-city on open (Playbook M-2 — polish existing implementation, don't rebuild).
**Files expected to change.**
- MODIFIED `lib/features/heatmap/presentation/**` (screen + overlay builder)
- NEW map style JSON assets + `pubspec.yaml` asset entries
**Dependencies.** PH-01 tokens; PH-07 multi-city seeding. Requires physical device with Maps key working (verify before starting, per Playbook R8).
**Verification checklist.** Same three risk colors as dashboard, by token import not by value ✓ · dark map style in dark mode ✓ · pan with all overlays: no jank ✓ · legend always visible ✓.
**Analyze.** Clean. **Tests.** Existing pass; overlay-color mapping unit test (level → token).
**Commit.** `feat(heatmap): PH-15 — styled map, token-driven risk overlays, legend`
**Rollback.** `git revert`; style assets removed with the commit.

---

### PH-16 · Heatmap Bottom Sheet + States
**Objective.** Tap zone → M3 bottom sheet (city, level chip, updated time, "View details" → typed risk route); map-region skeleton until overlays ready; "map unavailable" error state (Playbook M-2 remainder).
**Files expected to change.**
- MODIFIED heatmap screen; NEW `widgets/city_risk_sheet.dart`
**Dependencies.** PH-15; PH-05 typed routes.
**Verification checklist.** Tap→sheet < 300 ms ✓ · "View details" lands on correct city ✓ · airplane-mode behavior reviewed (cached tiles + error state) ✓.
**Analyze.** Clean. **Tests.** Widget test for sheet content mapping.
**Commit.** `feat(heatmap): PH-16 — city bottom sheet, loading/error states, detail navigation`
**Rollback.** `git revert`.

---

## TRACK B — NOTIFICATION EXPERIENCE (Dev B · Week 2 · owns `lib/features/notifications/**`)

---

### PH-17 · Notification Application Layer Additions
**Objective.** Mirror of PH-08 for notifications: `MarkNotificationRead`, `MarkAllRead`, `DismissNotification`, `WatchUnreadNotificationCount`, `GetNotificationById`; additive repository interface methods + Firestore implementations; `NotificationCategory`/priority value objects if absent. **Includes the rules decision:** if PH-00 recorded that Security Rules block owner read-flag updates, this phase contains the minimal additive rules change (app-owned field only), isolated in its own file diff and called out in the PR title.
**Files expected to change.**
- MODIFIED notification repository interface (domain, additive) + impl (data)
- NEW use case files + value objects + unit tests (incl. unread-count stream behavior with mocked repo)
- POSSIBLY MODIFIED `firestore.rules` (flagged, reviewed by both devs)
**Dependencies.** PH-00. Parallel-safe with all Track A phases.
**Verification checklist.** No existing signatures changed ✓ · rules change (if any) tested against emulator/console for: owner can update read flag, owner cannot touch backend-owned fields, non-owner denied ✓.
**Analyze.** Clean. **Tests.** New unit tests pass; test-heavy phase by design.
**Commit.** `feat(notifications): PH-17 — read/dismiss/unread use cases + additive repo methods [+ scoped rules change]`
**Rollback.** `git revert` **plus**, if rules changed, redeploy previous `firestore.rules` from the reverted commit (one command; note it in the PR).

---

### PH-18 · Live Unread Badge on Shell
**Objective.** Wire `WatchUnreadNotificationCount` into the PH-05 badge slot; count animates on change; hidden at zero.
**Files expected to change.**
- MODIFIED shell scaffold (badge slot wiring only — **shared file**: coordinate a same-day merge window with Dev A; the diff is ≤ ~15 lines by design because PH-05 pre-built the slot)
- NEW badge widget test with mocked count stream
**Dependencies.** PH-17, PH-05.
**Verification checklist.** Badge updates live when a doc's read flag flips in console ✓ · zero ⇒ hidden ✓ · no rebuild of unrelated tabs on count change (DevTools rebuild counts) ✓.
**Analyze.** Clean. **Tests.** New test passes.
**Commit.** `feat(notifications): PH-18 — live unread badge on navigation shell`
**Rollback.** `git revert`; slot degrades to hidden badge (PH-05 default).

---

### PH-19 · Notification List Redesign + Grouping
**Objective.** Rebuild the Center's list: `AppListTile`-based rows (category accent+icon, title, 2-line preview, relative time, unread treatment), sticky Today/Yesterday/date headers, `ListView.builder`, capped query window per Playbook M-3 item 9 (pagination decision recorded in code comment + BASELINE.md).
**Files expected to change.**
- MODIFIED `notification_center_screen.dart`; NEW `widgets/notification_tile.dart`, `date_header.dart`; NEW/MODIFIED list notifier (single stream → grouped view-model)
- NEW unit test: grouping function (date boundaries, timezone-safe); widget test: unread vs read rendering
**Dependencies.** PH-17; PH-03/04 components; PH-07 seeded inbox (dates/categories/read-states).
**Verification checklist.** 50+ seeded items scroll at 60 fps on device ✓ · grouping correct across a seeded month ✓ · both themes ✓.
**Analyze.** Clean. **Tests.** New tests pass.
**Commit.** `feat(notifications): PH-19 — redesigned notification list with date grouping`
**Rollback.** `git revert` restores previous list wholesale (screen-scoped diff).

---

### PH-20 · Category Filters + Priority Treatment
**Objective.** M3 filter chip row (All/Risk/Medication/System/Unread) as client-side filter over the loaded window; risk-alert tiles inherit risk-level semantics; high-priority container treatment; distinct filtered-empty vs true-empty copy (Playbook M-3 items 3–4).
**Files expected to change.**
- MODIFIED center screen + list notifier (filter state); NEW `widgets/notification_filter_row.dart`
- NEW unit test: filter × grouping composition; widget test: filtered-empty state copy
**Dependencies.** PH-19.
**Verification checklist.** Filter state survives tab-away/return ✓ · empty-filter-result shows its own state ✓ · priority treatment visible in both themes ✓.
**Analyze.** Clean. **Tests.** New tests pass.
**Commit.** `feat(notifications): PH-20 — category filters, priority treatment, filtered-empty state`
**Rollback.** `git revert`.

---

### PH-21 · Swipe Actions, Mark-All, Optimistic Updates
**Objective.** Swipe-to-dismiss + undo snackbar, mark-read swipe, "Mark all read" with undo — all on the canonical optimistic pattern established in PH-13 (mirror it; do not invent a second pattern — Playbook M-3 items 5–7). One documented choice: commit-on-undo-expiry vs immediate-with-rollback, applied to *both* actions.
**Files expected to change.**
- MODIFIED list notifier (optimistic overlay state) + center screen; NEW `widgets/dismissible_notification.dart`
- NEW unit tests: optimistic flip/revert per action; undo restores exact list position
**Dependencies.** PH-20; PH-13 merged (pattern reference — read-only cross-track dependency, no shared files).
**Verification checklist.** Manual matrix executed: {dismiss, mark-read, mark-all} × {online, airplane, forced-failure} — no silent loss, every failure explains itself ✓ · badge stays consistent through undo (with PH-18) ✓.
**Analyze.** Clean. **Tests.** New tests pass.
**Commit.** `feat(notifications): PH-21 — swipe actions + mark-all with optimistic updates and undo`
**Rollback.** `git revert`; repository write methods (PH-17) remain, unused by UI.

---

### PH-22 · Notification States + Motion
**Objective.** Mirrored skeleton tiles, designed empty state, error-with-retry, offline banner; first-load-only staggered entrance (≤ 250 ms), animated removal on dismiss, badge count animation check (Playbook M-3 items 8 & 10; motion per §7.4 spec, reduced-motion honored).
**Files expected to change.**
- MODIFIED center screen; NEW `widgets/notification_skeleton.dart`
**Dependencies.** PH-21 (final layout exists for mirroring).
**Verification checklist.** Four states on command via scenarios ✓ · stagger fires once, not on rebuilds ✓ · reduced-motion setting: static skeleton + no stagger ✓ · 60 fps maintained ✓.
**Analyze.** Clean. **Tests.** Widget test: empty and error states render with correct copy/retry.
**Commit.** `feat(notifications): PH-22 — state coverage + entrance/removal motion`
**Rollback.** `git revert`.

---

### PH-23 · Notification Detail Screen
**Objective.** Detail screen per Playbook M-4 scope: category-colored header, full body, timestamp, related-entity block with contextual CTA (risk → dashboard route; medication → log-dose route), marks itself read on open via PH-17 use case.
**Files expected to change.**
- NEW `notification_detail_screen.dart` + route registration (**touches router — small diff; coordinate merge window**)
- NEW widget tests: CTA mapping per category; read-marking called once on open
**Dependencies.** PH-17; PH-05 routes. (List can navigate to it from PH-19's tiles — wire the `onTap` here.)
**Verification checklist.** Open from list marks read; badge + list update within one stream frame ✓ · CTA lands on correct feature route ✓ · unknown category renders neutral fallback ✓.
**Analyze.** Clean. **Tests.** New tests pass.
**Commit.** `feat(notifications): PH-23 — notification detail screen with contextual CTAs`
**Rollback.** `git revert`; list `onTap` degrades to no-op guard (build the guard in, in this phase).

---

### PH-24 · Deep Linking (highest-risk phase — scheduled with maximum runway)
**Objective.** Single `NotificationRouteResolver` parsing the frozen FCM payload contract → typed route with **Notification Center fallback** for unknown payloads; consolidate FCM handlers to one location (removing duplicates found in PH-00); handle all three app states (foreground / background-tap / terminated via initial message); resolver gated on auth-ready provider (Playbook M-4, risk R1).
**Files expected to change.**
- NEW `lib/features/notifications/presentation/notification_route_resolver.dart`
- MODIFIED the single FCM handler location (+ deletions of duplicates); MODIFIED router (fallback route only — **shared file, small diff**)
- NEW unit tests: resolver payload matrix (both payload types + unknown + missing fields → fallback)
**Dependencies.** PH-23; PH-05; PH-00 handler inventory. **Schedule:** start no later than Week 2 day 4 (two fix-cycles before demo, per Playbook).
**Verification checklist.** Six-cell matrix on physical device: {foreground, background, terminated} × {risk payload, medication payload}, plus logged-out behavior per the documented choice ✓ · unknown payload → Center + debug log ✓ · no double-navigation (duplicate handlers gone) ✓.
**Analyze.** Clean. **Tests.** Resolver unit tests pass (the runtime matrix is manual — record results in BASELINE.md).
**Commit.** `feat(notifications): PH-24 — FCM deep linking via route resolver, handler consolidation`
**Rollback.** `git revert` restores prior handler behavior; because handlers were consolidated *in this same commit*, revert is total — no half-state.

**⛳ GATE 2 (end Week 2):** Demo dry-run #1 off `main` on the demo device using `demo-standard` seeding. All Must-Have playbook items demonstrable. Findings become fix-phases in Week 3, triaged against the MoSCoW cut line.

---

## TRACK C — CONVERGENCE, POLISH & SHOULD-HAVES (Week 3 · serial where files overlap, else split by owner)

---

### PH-25 · State-Matrix Audit & Fix Sweep
**Objective.** Execute Playbook §7.2: spreadsheet of every screen × {loading, data, empty, error, offline} × {light, dark}; walk every cell with PH-07 scenarios + airplane mode; fix or explicitly waive each ✗. May produce several small `fix(...)` commits — treat this phase as a bounded commit *series* under one branch, one per feature area to keep rollback granular.
**Files expected to change.** Any presentation file, one feature area per commit; **no domain/data changes permitted in this phase** (if a fix seems to need one, it's a mis-scoped bug — file it, discuss).
**Dependencies.** GATE 2.
**Verification checklist.** Matrix spreadsheet 100% executed ✓ · Must-Have screens 100% ✓, overall ≥ 90% ✓ · spreadsheet committed to `docs/sprint6/` ✓.
**Analyze.** Clean after each commit. **Tests.** Full suite green after each commit.
**Commits.** `fix(<area>): PH-25 — state-matrix fixes (<n> cells)` per area + `docs(sprint6): PH-25 — state matrix results`
**Rollback.** Per-area `git revert` (this is why the phase is a commit series, not one blob).

---

### PH-26 · Performance Profiling & Fixes
**Objective.** Execute Playbook §7.1 on the demo device: cold start, dashboard scroll, notification scroll (50 items), heatmap pan, theme switch. Fix findings: const audit, builder lists, duplicate stream listeners, map lifecycle decision (keep-alive vs dispose, measured).
**Files expected to change.** Presentation files across features; possibly provider files (listener dedup). Same per-area commit-series rule as PH-25.
**Dependencies.** PH-25 (fix states first — skeletons change frame profiles).
**Verification checklist.** DevTools overlay: no red bars on the five target interactions ✓ · cold-start time recorded before/after in BASELINE.md ✓ · rebuild-count spot checks on badge and freshness ticker ✓.
**Analyze.** Clean. **Tests.** Full suite green; no behavioral test changes (perf-only diffs).
**Commits.** `perf(<area>): PH-26 — <finding>` per fix.
**Rollback.** Per-commit revert; perf commits are behavior-preserving by definition — any test change in a PH-26 diff is a review red flag.

---

### PH-27 · Accessibility Pass
**Objective.** Execute Playbook §9 as a ship-blocking checklist on Must-Have screens: semantic labels (icon-only buttons, swipe actions, legend), 48 dp targets, 1.3× font-scale survival, TalkBack core-journey run, risk announced meaningfully, reduced-motion verified globally.
**Files expected to change.** Presentation files (Semantics wrappers, labels, minor layout fixes for scale). Per-area commit series.
**Dependencies.** PH-25 (stable layouts).
**Verification checklist.** TalkBack completes login → dashboard → notification → mark read ✓ · 1.3× scale: no clipped text/overflow stripes on Must-Have screens ✓ · contrast re-verified post-fixes ✓ · results appended to BASELINE.md ✓.
**Analyze.** Clean. **Tests.** Full suite green; ADD semantics assertions to existing widget tests where cheap (StatusChip, trend chip already have them from PH-03/11).
**Commits.** `fix(a11y): PH-27 — <area> semantics, targets, scale fixes`
**Rollback.** Per-commit revert.

---

### PH-28 · Onboarding & First-Run Polish (S-1)
**Objective.** Playbook S-1: auth screens on the design system (inline validation, loading button states), 3-step profile stepper (city → conditions → notification permission with value pre-prompt), personalized landing confirmation.
**Files expected to change.**
- MODIFIED `lib/features/auth/presentation/**`, `lib/features/profile/presentation/**` (setup flow)
- NEW `widgets/permission_preprompt.dart`, stepper widgets
- NEW widget tests: validation states; stepper back-navigation preserves entered data
**Dependencies.** Foundation only; independent of Tracks A/B — **this is the designated slack phase**: if Week 2 slipped, this absorbs the cut first (it's top of Should-Have, so it's also first to *do* if on schedule).
**Verification checklist.** Fresh-install run < 90 s to personalized dashboard, zero dead ends ✓ · permission pre-prompt precedes OS dialog ✓ · both themes ✓ · journey screen-recorded for report ✓.
**Analyze.** Clean. **Tests.** New tests pass.
**Commit.** `feat(onboarding): PH-28 — design-system auth + profile setup stepper + permission pre-prompt`
**Rollback.** `git revert`; auth logic untouched (presentation-only diff — verify in review).

---

### PH-29 · Health Resource Center Polish (S-2)
**Objective.** Playbook S-2: article cards, reading-typography detail view, tap-to-call emergency contacts, high-risk advisory banner (appears iff user's city risk is High — consumes the risk use case read-only), full state coverage via core components.
**Files expected to change.**
- MODIFIED `lib/features/resources/presentation/**`; NEW card/detail/banner widgets
- NEW widget test: banner visibility rule (mocked risk level)
**Dependencies.** PH-08 (risk read use case), core components.
**Verification checklist.** Tap-to-call fires dialer on device ✓ · banner appears only under seeded High ✓ · states ✓ · both themes ✓.
**Analyze.** Clean. **Tests.** New tests pass.
**Commit.** `feat(resources): PH-29 — resource center redesign + high-risk advisory banner`
**Rollback.** `git revert`.

---

### PH-30 · Weekly Report Aggregation (S-3a — logic only, no UI)
**Objective.** `GetWeeklyReportData(userId, weekStart)` composing existing adherence + risk repositories into a `WeeklyReport` value object (adherence %, per-day taken/missed, 7-day risk strip, rule-based observations). Timezone-pinned week boundaries. **Unit tests are non-negotiable here** (Playbook S-3 risk note) — hand-computed expected values against the PH-07 "interesting week" fixture.
**Files expected to change.**
- NEW application use case + domain value objects; MODIFIED adherence/risk repo interfaces **only if** a ranged query is missing (additive)
- NEW unit test suite: aggregation correctness incl. week boundaries, empty week, partial data, DST-adjacent dates
**Dependencies.** PH-07 fixture; PH-08 risk history query.
**Verification checklist.** Numbers reconcile exactly with hand computation ✓ · empty week returns a typed empty report (not null/throw) ✓ · observation rules deterministic and plainly worded (not labeled "AI") ✓.
**Analyze.** Clean. **Tests.** New suite passes — this phase's primary deliverable.
**Commit.** `feat(insights): PH-30 — weekly report aggregation use case + exhaustive unit tests`
**Rollback.** `git revert`; zero UI consumers yet.

---

### PH-31 · Weekly Report Viewer (S-3b)
**Objective.** Report screen: adherence ring, 7-day bars, risk strip (token colors), observation cards, week-picker history (computed-on-read — no stored reports); custom-painted visuals unless a chart package already exists (Playbook S-3 dependency rule); full state family incl. empty week.
**Files expected to change.**
- NEW `lib/features/insights/presentation/**` (screen, notifier, painted widgets) + route + nav entry point (**router/shell touch — small diff, coordinate**)
- NEW widget tests: renders from a fixed `WeeklyReport`; empty-week state
**Dependencies.** PH-30.
**Verification checklist.** Rendered numbers match PH-30 fixture expectations on screen ✓ · charts use semantic tokens ✓ · 1.3× scale ✓ · both themes ✓.
**Analyze.** Clean. **Tests.** New tests pass.
**Commit.** `feat(insights): PH-31 — weekly report viewer with week history`
**Rollback.** `git revert`; PH-30 logic remains, harmless without UI.

---

### PH-32 · Nice-to-Haves (only if GATE 2 passed on time — each independently committable)
Executed as separate micro-phases in this order, each with the standard verification/commit/rollback pattern:
- **PH-32a** `feat(insights): share-as-image via repaint boundary` (N-1) — AC: crisp shared image, app-name watermark.
- **PH-32b** `feat(admin): read-only system status screen` (N-2) — heartbeat freshness + last N audit entries; RBAC-gated; graceful "no data" for the billing-postponed reality. Owns `lib/features/admin/**` only.
- **PH-32c** `feat(risk): hero transition dashboard→detail` (N-3) — reduced-motion respected; ≤ 400 ms; no frame drops.
- **PH-32d** `feat(app): haptics on dose-taken and mark-all-read` (N-4) — fires once; silent on unsupported devices.
**Rollback.** Each is one revert; none has downstream dependents by design.

---

### PH-33 · Feature Freeze, Rehearsals, Release Tag
**Objective.** Freeze at Week 3 day 5 noon: final `flutter analyze`/`flutter test` runs recorded; demo dry-runs #2 and #3 off `demo-standard` (plus the airplane-mode fallback path once); DEMO_SCRIPT.md finalized with per-screen presenter lines and the three wow-moments; version bump; annotated tag.
**Files expected to change.**
- MODIFIED `pubspec.yaml` (version), `docs/sprint6/DEMO_SCRIPT.md`, BASELINE.md (final quality numbers vs Sprint-Success criteria S1–S8)
- Bug-fix commits only after freeze, each ≤ 1 file-area, each individually revertable
**Dependencies.** Everything above the cut line merged.
**Verification checklist.** Playbook S1–S8 all pass and are recorded ✓ · three rehearsals done, timed ✓ · tag `v0.6.0-sprint6` pushed ✓ · demo device prepared per checklist (charged, seeded, permissions granted, airplane fallback tested) ✓.
**Analyze.** Clean, final numbers recorded. **Tests.** Full suite green, count recorded.
**Commit.** `chore(release): PH-33 — sprint 6 freeze, v0.6.0, demo readiness` + tag
**Rollback.** Tags are immutable pointers; any post-freeze regression rolls back by reverting its own micro-commit — never by re-opening feature work.

---

## Appendix A — Phase Dependency Graph (text form)

```
PH-00 ─┬─ PH-01 ─ PH-02 ─ PH-03 ─ PH-04 ─┐
       │            └───── PH-05 ─ PH-06 ─┤ GATE 1
       └─ PH-07 ──────────────────────────┘
GATE 1 ─┬─ Track A: PH-08→09→10→11→12→13→14, PH-15→16
        └─ Track B: PH-17→18*, 17→19→20→21→22→23*→24*   (* = shared-file touch, coordinate merge window)
Cross-track (read-only): PH-21 mirrors PH-13's pattern; PH-29 consumes PH-08's use case
GATE 2 ─ PH-25 → PH-26 → PH-27 (serial audits) ∥ PH-28, PH-29 (independent)
PH-30 → PH-31 · PH-32a–d (optional) · PH-33 (final)
```

## Appendix B — Standing Definition of Done (every phase, restated once)
Diff limited to the phase's file list · `flutter analyze` 0 errors/0 warnings, infos ≤ baseline · full test suite green + phase-specified new tests · both themes checked for visible UI · smoke boot on demo device for runtime changes · screenshot at merge for user-visible phases · commit message exactly as specified · merged to main same day.

— End of Roadmap —
