# ForeSeeMe — Sprint 6 Implementation Playbook
### "Production Polish" Sprint · Presentation-Layer Excellence
**Team:** SP23-BSE-034 (Muhammad Haseeb) · SP23-BSE-040 (Saim Zulfiqar)
**Prepared as:** Staff-level engineering plan. Reference document for all subsequent implementation prompts.
**Scope law:** No code in this document. No architecture changes. No backend redesign.

---

## 0. Executive Summary (read this first)

Sprint 6 converts a functionally complete system into a product that *feels* engineered. Two people, one sprint, five proposed modules — that is over-scoped, and the proposed module list has three structural problems this playbook corrects:

1. **It is missing the foundation.** You cannot "redesign the Notification Center" and "redesign the Risk Dashboard" as independent efforts without first freezing a **design system** (tokens, typography scale, spacing, elevation, motion durations, color semantics). Doing screens first and a system later produces two visual dialects and rework. **Phase 0 of this sprint is the design system.** Every screen redesign then becomes cheap.

2. **It is missing the SDS's marquee feature.** Your SDS commits to a **geospatial risk heatmap** (FR3.1–FR3.4, CON-8: Google Maps SDK mandatory, mockups M7/M8) and a **Health Resource Center** (Module 4). Neither appears in the Sprint 6 module list. Evaluators grade against the SDS. A polished notification center will not compensate for a rough version of the feature your own executive summary calls out by name. The heatmap is promoted to Must Have.

3. **It over-invests in the Admin/Operator experience.** Cloud billing is intentionally postponed, so a "heartbeat dashboard / cloud job monitoring" screen has *nothing live to show* for most of the sprint, serves an actor evaluators barely exercise, and its data contract (job status documents) partially depends on infrastructure that isn't running. It is demoted to Nice to Have with a drastically reduced scope, replaced by something far more valuable for marks: a **Demo Mode / data seeding harness** that guarantees the evaluation walkthrough never depends on live weather APIs, live ML runs, or scheduler timing.

**The reordered sprint, in one line:** *Design System → App Shell & Navigation → Risk Dashboard + Heatmap (demo centerpiece) → Notification Experience → Cross-cutting Polish (continuous) → Health Insights (reduced) → Admin (minimal).*

**The single most important mindset:** evaluators form their quality judgment in the first 90 seconds, on the home/risk screen, on one device, possibly with bad Wi-Fi. Every hour of this sprint should be spent where their eyes will be.

---

## 1. Sprint Objective

**Objective statement:**
> Elevate ForeSeeMe's presentation layer to production quality — a coherent Material 3 design system, a demo-proof Risk Dashboard with the SDS-mandated heatmap, a first-class notification experience, and systematic polish (loading, empty, error, offline, motion, accessibility) — without modifying the domain layer's contracts, the data layer's implementations, or the frozen backend, and without introducing any architectural violation.

**Measurable definition of "polished" for this sprint (Sprint Success Criteria):**

| # | Criterion | How verified |
|---|---|---|
| S1 | Zero screens with default `CircularProgressIndicator`-only loading; all primary screens use skeletons or shimmer | Manual screen audit checklist |
| S2 | Every async surface handles all four states: loading / data / empty / error (with retry) | State-matrix audit (§7.2) |
| S3 | End-to-end demo script runs offline-tolerant and without live GCP billing | Rehearsed dry run × 3 |
| S4 | 60 fps on the Risk Dashboard and Notification Center scroll on a mid-range physical Android device | Flutter DevTools performance overlay, no red bars |
| S5 | All interactive elements ≥ 48×48 dp touch targets; text contrast ≥ 4.5:1 in both themes; TalkBack can complete the core flow | Accessibility audit checklist (§9) |
| S6 | Dark and light themes both fully specified from tokens; no hardcoded `Color(0xFF...)` in feature widgets | grep-level lint rule + review |
| S7 | Notification deep link opens the correct detail screen from a cold start | Instrumented manual test |
| S8 | No new lint warnings; `flutter analyze` clean; no `TODO` merged to main | CI / pre-merge check |

These eight criteria are the sprint's Definition of Success. Individual features below have their own DoD, but the sprint is not done until S1–S8 pass.

---

## 2. Roadmap Critique — Are the Proposed Modules Sufficient?

**Verdict: Not sufficient as listed, and mis-prioritized.** Here is the gap analysis:

### 2.1 What the proposed list gets right
- Notification Experience and Risk Dashboard are correctly identified as the two highest-traffic user surfaces.
- "Application Polish" as a named workstream is correct instinct — but it must run *continuously and cross-cutting*, not as a fifth module executed last (last-week polish is how sprints fail).

### 2.2 What is missing (added by this playbook)

| Missing item | Why it matters | Disposition |
|---|---|---|
| **Design system foundation** (tokens, theme, motion spec, component library) | Prerequisite for every redesign; prevents visual drift and rework | **Must Have — Phase 0** |
| **Geospatial risk heatmap polish** | SDS FR3.1–3.4, CON-8, mockups M7/M8; your own abstract's flagship visual | **Must Have** |
| **Health Resource Center polish** | SDS Module 4; cheap to polish (list + detail + emergency contacts), high SDS-compliance value | **Should Have** |
| **Onboarding / first-run experience** | Evaluators will register a fresh account live; first-run is literally the first thing they grade | **Should Have** |
| **Demo Mode & data seeding harness** | Billing postponed ⇒ live pipeline can't be relied on; the demo must be reproducible on command | **Must Have** |
| **App identity: icon, splash, app name, About screen** | 30 minutes of work, disproportionate "finished product" signal | **Must Have (trivial)** |
| **Empty/error/offline state *strategy*** (one reusable component family, not per-screen improvisation) | Listed as scattered bullets in the prompt; must be a single engineered system | Folded into Phase 0 |

### 2.3 What is demoted, and why

| Proposed item | Problem | Disposition |
|---|---|---|
| **Admin heartbeat / cloud job monitoring / deployment status UI** | No live infra until billing enabled; low evaluator exposure; observability belongs in Cloud Console for a system this size — rebuilding it in Flutter is résumé-driven scope | **Nice to Have**, reduced to a single read-only "System Status" screen fed by existing Firestore audit/heartbeat docs |
| **Report sharing / export / download (PDF)** | PDF generation on-device is a rabbit hole (fonts, pagination, platform channels); share-as-image is 10% of the cost for 80% of the demo value | Export → **Future**; share-as-image → **Nice to Have** |
| **Notification search** | Users have < 50 notifications; filtering by category covers the real need; search adds a text-index question with no backend support | **Future** |
| **Historical comparison on risk dashboard** | Depends on RiskEstimates history depth that the postponed pipeline hasn't accumulated; a 7-day trend sparkline from whatever exists is the honest version | Reduced to trend sparkline → **Should Have** |

### 2.4 Why this order (the dependency & payoff argument)

The ordering below is not preference — it is forced by three constraints:

1. **Dependency order.** Tokens/theme → shell/navigation → screens. Any screen built before the token layer exists will be rebuilt. Deep linking requires the navigation architecture finalized first. Skeletons require the card layouts finalized first (a skeleton mirrors its real layout).

2. **Evaluator exposure order.** Time-on-screen during a typical FYP evaluation: Home/Risk Dashboard (≈40%) > Notifications (≈20%) > Medication/Adherence (≈15%) > Heatmap (≈10%) > everything else. Effort should approximate this distribution.

3. **Risk burn-down.** The riskiest items (deep linking from a cold start, Maps heatmap rendering, demo seeding) must land early enough to survive two failure-fix cycles before evaluation. Anything risky scheduled in the final week is a plan to fail publicly.

---

## 3. Priority Ranking (MoSCoW, resequenced)

**Capacity reality check:** two developers, one sprint (assume 3 working weeks ≈ 30 person-days). The Must Have column below sums to ≈ 21 person-days, leaving ≈ 9 for Should Have and slack. Anything below the cut line is explicitly *pre-decided* to slip without guilt — that decision is being made now, in planning, not in a panic later.

### MUST HAVE (sprint fails without these)
| ID | Item | Est. (person-days) |
|---|---|---|
| P0-1 | Design system: tokens, Material 3 theme (light+dark), typography, motion spec | 2.5 |
| P0-2 | Core component library: AppCard, StatusChip, SkeletonLoader, EmptyState, ErrorState, OfflineBanner, AppButton states | 2.5 |
| P0-3 | App shell: navigation polish, bottom nav, route architecture ready for deep links, app icon/splash/branding | 1.5 |
| M-1 | Risk Dashboard redesign (risk card, confidence viz, trend, freshness, explanation, AQI/weather tiles, recommendations) | 5 |
| M-2 | Geospatial heatmap polish (SDS FR3.x) | 2 |
| M-3 | Notification Center redesign (list, grouping, unread, mark-as-read, swipe, categories, states) | 4 |
| M-4 | Notification Details + deep linking (FCM tap → detail, cold start safe) | 2 |
| M-5 | Demo Mode & Firestore seeding harness + rehearsed demo script | 1.5 |
| | **Subtotal** | **21** |

### SHOULD HAVE (do if Must Haves land by end of week 2)
| ID | Item | Est. |
|---|---|---|
| S-1 | Onboarding / first-run polish (auth screens, profile setup stepper) | 2 |
| S-2 | Health Resource Center polish (article list/detail, emergency contacts) | 1.5 |
| S-3 | Weekly Health Report (in-app viewer, computed client-side from existing adherence + risk data via use cases) | 3 |
| S-4 | Risk trend sparkline (7-day, from available RiskEstimates history) | 1 |
| S-5 | Accessibility deep pass (TalkBack labels, semantics, dynamic type survival) | 1.5 |

### NICE TO HAVE (only if ahead of schedule)
| ID | Item | Est. |
|---|---|---|
| N-1 | Report share-as-image | 0.5 |
| N-2 | Minimal Admin "System Status" read-only screen (heartbeat doc + last job audit entries) | 1.5 |
| N-3 | Hero/shared-element transitions between risk card and risk detail | 1 |
| N-4 | Haptic feedback on key confirmations (dose taken, mark all read) | 0.5 |

### FUTURE (explicitly out of Sprint 6 — record and move on)
- Notification full-text search
- PDF export of reports; email delivery of reports
- Historical multi-month risk comparison
- Full observability dashboard (job graphs, latency charts) — Cloud Console covers this
- Tablet/desktop adaptive layouts beyond graceful phone-landscape behavior
- Localization (Urdu) — flag in the report as designed-for but deferred

---

## 4. Architectural Ground Rules for a Presentation Sprint

These rules translate "never break Clean Architecture" into concrete, reviewable constraints for *this specific kind of work*. Every PR is reviewed against this section.

### 4.1 Where Sprint 6 code is allowed to live

| Layer | Sprint 6 activity | Allowed? |
|---|---|---|
| **Presentation** (widgets, screens, controllers/notifiers, routing, theming) | ~85% of the sprint | ✅ Unlimited |
| **Application** (use cases) | New *read/coordination* use cases only: e.g. `MarkNotificationRead`, `MarkAllNotificationsRead`, `WatchUnreadNotificationCount`, `GetNotificationById`, `GetWeeklyReportData`, `GetRiskHistory` | ✅ Additive only |
| **Domain** (entities, repository interfaces) | New *methods on existing repository interfaces* and new value objects (e.g. `NotificationCategory`, `RiskTrend`, `WeeklyReport`) where a use case needs them | ✅ Additive only; no changes to existing entity semantics |
| **Data** (repository impls, DTOs, Firestore) | Implementations of the new interface methods; new Firestore *queries* on existing collections | ⚠️ Additive only; **no schema redesign, no new write paths to backend-owned collections** |
| **Backend / Cloud** | — | ⛔ Frozen |

### 4.2 Non-negotiable implementation rules

1. **Widgets never touch repositories.** Widget → Riverpod provider → use case → repository interface. If a screen "just needs one field," it still goes through a use case. No exceptions for polish work.
2. **UI state is presentation state.** Skeleton visibility, swipe-dismiss pending state, filter selection, animation controllers, optimistic flags — all live in presentation-layer Notifiers/controllers, never in domain entities.
3. **Optimistic updates are a presentation pattern with a domain-safe rollback.** The Notifier flips local state immediately, calls the use case, and reverts + surfaces an error state if the use case fails. The repository contract does not change to accommodate optimism.
4. **One state envelope everywhere.** Standardize on `AsyncValue<T>` (or the project's existing sealed UI-state class if one already exists — do not introduce a second convention). Every screen renders from the same envelope; the four-state audit in §7.2 becomes mechanical.
5. **Design tokens are code, in one place.** A `core/theme` (or equivalent existing shared presentation module) exports `ColorScheme`, `TextTheme`, spacing constants, radius constants, duration constants, and semantic risk colors. Feature code imports tokens; it never declares raw colors, raw durations, or magic paddings. Enforce with review + a simple grep check for `Color(0x`.
6. **No new packages without a written one-line justification in the PR.** Target additions: none required for Must Haves beyond what a typical Flutter M3 + Maps project already has (`google_maps_flutter` should already exist per CON-8; `shimmer` is optional — a 30-line custom shimmer avoids the dependency).
7. **Deep linking rides the existing FCM payload contract.** The backend already emits notification documents/payloads; the app parses `type`/`entityId` (whatever the existing contract fields are) and maps to routes. If the payload lacks a routable identifier, the fix is a *mapping table with a safe fallback route (Notification Center)* — not a backend change.
8. **Nothing blocks on live GCP.** Every screen must render correctly from Firestore data alone. The seeding harness (M-5) writes realistic documents matching the backend's exact schemas so the app cannot tell the difference.

### 4.3 The one architecture *addition* this sprint makes (and why it's legal)

A **`core/ui` component library** (shared presentation module) is introduced beneath feature presentation code. This is not an architecture change — Clean Architecture is silent about horizontal sharing *within* a layer. It is the mechanism that makes S1/S2/S6 achievable: one `EmptyState` widget with an illustration slot, one `SkeletonLoader`, one `ErrorState(onRetry:)`, one `OfflineBanner` listening to a connectivity provider. Twenty screens consume them; zero screens reinvent them. This is also your strongest viva talking point on "how did you avoid duplication."

---

## 5. Phase Plan & Sequencing Rationale

**Week 1 — Foundation & Centerpiece start**
- Days 1–3: P0-1, P0-2, P0-3 (both devs pair on tokens day 1 to lock decisions, then split: Dev A components, Dev B shell/nav/deep-link route architecture).
- Days 4–5: M-1 begins (Dev A: risk card + confidence viz), M-5 seeding harness (Dev B) — *seeding lands in week 1 deliberately* so every subsequent day of UI work has rich, realistic data to build against. Building UI against empty databases is how empty states get forgotten and how demos get discovered broken on the last day.

**Week 2 — The two big surfaces**
- Dev A: finish M-1, then M-2 heatmap.
- Dev B: M-3 Notification Center, then M-4 details + deep linking.
- End of week 2: **Milestone gate — full demo dry-run #1.** Must Haves demonstrable end-to-end, ugly edges allowed.

**Week 3 — Polish sweep + Should Haves**
- Days 1–2: Cross-cutting audit sweeps (§7.2 state matrix, §9 accessibility, performance profiling) — both devs, checklist-driven.
- Days 3–4: Should Haves in priority order (S-1 onboarding first: it is the first thing evaluators see).
- Day 5: Demo dry-run #2 and #3, bug-fix only, feature freeze at noon.

**Why polish is scheduled as *audits*, not a module:** "Application Polish" as a backlog module invites vague, unfinishable work. As a checklist-driven audit (every screen × four states × two themes × TalkBack), it is finite, divisible between two people, and provably done.

---

## 6. Detailed Feature Breakdown

Format per feature: Purpose → User story → Technical impact → Architecture impact → Dependencies → Complexity → Risk → Acceptance criteria → Definition of Done.

---

### P0-1 · Design System Foundation

**Purpose.** Establish the single source of visual truth so every subsequent screen is assembled, not designed from scratch; guarantee Material 3 compliance and dual-theme correctness by construction.

**User story.** *As a user, every screen of ForeSeeMe looks and moves like it belongs to one product, in light or dark mode, so I trust it with my health data.*

**Technical impact.** New `core/theme` exports: seeded M3 `ColorScheme` pair (see §8.2 for palette direction), full `TextTheme` on a deliberate type scale, spacing scale (4/8/12/16/24/32), radius scale (small 8 / medium 12 / large 16 / full), elevation policy (M3 tonal elevation, minimal shadows), motion tokens (fast 150ms / standard 250ms / emphasized 400ms with M3 easing curves), and **semantic risk tokens**: `riskLow`, `riskMedium`, `riskHigh` with on-colors and container variants for both themes — *never* raw green/yellow/red in feature code, because these three colors are the app's core vocabulary (SDS FE-1 Module 3) and must remain accessible and consistent everywhere they appear (cards, chips, map, notifications).

**Architecture impact.** None beyond adding the shared presentation module. Zero domain/data changes.

**Dependencies.** None — this is the root of the sprint's dependency tree.

**Complexity.** Medium (decisions are harder than code). **Risk.** Low technically; medium schedule risk if the team bikesheds — timebox palette/type decisions to one paired half-day, decide, freeze.

**Acceptance criteria.**
1. Both themes generated from tokens; switching themes at runtime re-renders every screen correctly with no hardcoded colors surviving (`grep -rn "Color(0x" lib/features` returns zero results).
2. Risk semantic colors pass 4.5:1 contrast for text and 3:1 for graphical elements in both themes (verified with a contrast checker).
3. A single "gallery" debug screen renders all tokens and core components in both themes for review (doubles as report screenshots).

**Definition of Done.** Merged; gallery screen reviewed by both devs; §4.2 rule 5 grep check added to the pre-merge checklist; a one-page "Design Tokens" appendix drafted for the FYP report (evaluators reward documented process).

---

### P0-2 · Core Component Library

**Purpose.** Eliminate per-screen improvisation of the states and surfaces that define perceived quality: loading, empty, error, offline, cards, chips, buttons.

**User story.** *As a user, when something is loading I see a graceful placeholder of the real layout; when something is empty I'm told why and what to do; when something fails I can retry — everywhere, identically.*

**Technical impact.** `core/ui` widgets: `AppCard` (M3 elevated/filled/outlined variants), `StatusChip` (consumes risk semantic tokens), `SkeletonLoader` (shape-mirroring shimmer, custom ~30-line implementation, respects reduced-motion), `EmptyState(illustration, title, body, action?)`, `ErrorState(message, onRetry)`, `OfflineBanner` (driven by one connectivity provider), `SectionHeader`, `AppListTile`. Each with fixed padding/radius/typography from tokens — call-sites cannot restyle them.

**Architecture impact.** Presentation-only. One new presentation-level connectivity provider (wrapping the existing connectivity source if one exists in data layer; if none exists, a thin `connectivity_plus` listener is acceptable as *presentation infrastructure* since no domain logic depends on it — document this judgment call in the PR).

**Dependencies.** P0-1 tokens.

**Complexity.** Medium. **Risk.** Low.

**Acceptance criteria.**
1. All eight components render in the gallery screen, both themes.
2. `SkeletonLoader` visually mirrors the real card layouts for the risk card and notification tile (not generic gray boxes).
3. `EmptyState` and `ErrorState` used by at least the Notification Center and Risk Dashboard by sprint end (proof of adoption).

**Definition of Done.** Merged; adopted by ≥ 2 screens; components documented with a usage line each in the repo README or `core/ui/README.md`.

---

### P0-3 · App Shell, Navigation & Identity

**Purpose.** Make the app's skeleton feel deliberate: bottom navigation with correct M3 styling, route architecture that supports deep links, and the identity assets (icon, splash, name) that signal "finished product" in the first three seconds.

**User story.** *As a user, I move between Home, Heatmap, Medications, Notifications, and Profile with clear wayfinding, an unread badge tells me when something needs attention, and the app opens with a branded splash instead of a white flash.*

**Technical impact.** M3 `NavigationBar` (not the legacy `BottomNavigationBar`) with the unread-count badge on the Notifications destination (fed by `WatchUnreadNotificationCount` — see M-3); route table refactored (if not already) so every detail screen is addressable by a typed route with an ID parameter — the precondition for M-4 deep linking; adaptive app icon + themed splash (Android 12 splash API) + consistent app display name; an About screen (version, team, supervisor, university) — evaluators genuinely check this.

**Architecture impact.** Presentation only. The unread-count stream is consumed via provider → use case → repository (interface method may need adding: additive, legal per §4.1).

**Dependencies.** P0-1. Deep-link *handling* (M-4) depends on this route architecture.

**Complexity.** Low-Medium. **Risk.** Low, except splash/icon fiddliness on specific Android OEMs — verify on the actual demo device early.

**Acceptance criteria.**
1. Cold start shows branded splash → home with no white flash and no layout jump.
2. Every screen reachable by a named/typed route with parameters; navigation state survives process death on Android (test with "Don't keep activities").
3. Unread badge live-updates when a notification is marked read on another screen.

**Definition of Done.** Merged; verified on the physical demo device; icon/splash screenshots captured for the report.

---

### M-1 · Risk Dashboard Redesign (the centerpiece)

**Purpose.** This is the screen that carries the project's thesis — "AI-powered personalized risk" — and the screen evaluators will stare at longest. It must communicate *intelligence, freshness, and trustworthiness* at a glance.

**User story.** *As an asthma patient in Lahore, I open ForeSeeMe and within two seconds I see today's risk level for my city, why it is what it is, how confident the system is, whether it's rising or falling, and what I should do about it.*

**Scope (the redesigned screen, top to bottom).**
1. **Hero risk card** — city name, risk level as a large `StatusChip`-derived surface using semantic risk container colors, a short generated headline ("High smog risk in Lahore today").
2. **Confidence visualization** — the ML model's class probability rendered as a segmented arc or bar ("Model confidence: 82%"), with an info affordance explaining what confidence means in one sentence. *Honesty rule:* display the real probability from RiskEstimates; never invent a number. If the stored estimate lacks a probability field, show the class only and drop the confidence element — do not fake it.
3. **Trend indicator** — direction vs. previous estimate (↑ worsening / → stable / ↓ improving) with color + icon + text (never color alone — accessibility).
4. **Freshness** — "Updated 3 h ago" via a relative-time utility that updates while on screen; past a staleness threshold (mirror the SDS's 36-hour stale-data rule, ER1.1) it visibly degrades to a warning style ("Data may be outdated").
5. **Why this risk?** — 2–4 explanation rows derived from the environmental features already stored with the estimate (e.g., "AQI 180 — unhealthy", "Humidity 78% — favors dengue vectors"). This is the "Perceived Intelligence" moment: it shows the model's *inputs*, which reads as explainable AI. Source strictly from existing stored fields via a use case.
6. **Environment tiles** — AQI and weather as two compact tiles with iconography, value, and a plain-language band label (AQI bands per standard EPA breakpoints).
7. **Recommendation cards** — horizontally scrollable, category-tagged precaution cards conditioned on risk level and the user's chronic-condition profile (content from the Health Resource Center data or a curated static set — via use case, no hardcoded strings scattered in widgets).
8. **Quick action** — "Take now" for due medication directly from the dashboard (SDS FR2.4 already requires this; ensure it's present and optimistic-update smooth).

**Technical impact.** New/extended use cases: `GetCurrentRiskEstimate` (likely exists), `GetRiskExplanationFactors`, `GetRiskTrend` (compares last two estimates), `GetRecommendationsFor(riskLevel, conditions)`. One screen-level Notifier composes them; the widget tree renders from a single view-model object so the screen has exactly one loading skeleton, not five spinners popping independently.

**Architecture impact.** Additive use cases + possibly one additive repository query (`getRecentRiskEstimates(city, limit)`). No schema changes — trend and explanation are *derived* in the application layer from data the backend already writes.

**Dependencies.** P0-1, P0-2; M-5 seeding (to build against realistic data, including the stale-data and low-confidence edge cases).

**Complexity.** High (it's a composition of six sub-features). **Risk.** Medium — the main risk is *data shape assumptions*: verify the exact RiskEstimates document fields on day 1 of this feature and write the view-model mapping against reality, not memory.

**Acceptance criteria.**
1. Screen renders complete from a single skeleton → content transition in one frame-batch (no element-by-element pop-in).
2. All three risk levels render correctly (verified via seeded data) in both themes.
3. Stale-data state (> 36 h) visibly indicated; missing-probability case degrades gracefully per the honesty rule.
4. Explanation rows show only real stored factors; empty factors → section hides entirely (no placeholder lies).
5. Scroll performance: no dropped-frame bars in DevTools on the demo device.
6. "Take now" updates adherence optimistically and reconciles on failure with a snackbar + revert.

**Definition of Done.** Merged; screenshot set (3 risk levels × 2 themes) captured for report; dry-run walkthrough narration written (one paragraph the presenter says on this screen).

---

### M-2 · Geospatial Heatmap Polish

**Purpose.** Bring the SDS-mandated map (FR3.1–3.4, CON-8) to the same visual standard: color-coded city risk zones, legend, tappable zones, and a graceful path from map → city risk detail.

**User story.** *As a user, I open the map and instantly see which cities are red, yellow, or green; tapping a zone shows that city's risk summary and lets me open its details.*

**Scope.** Custom-styled Google Map (subtle desaturated style so risk colors dominate — use Google's cloud-based or JSON map styling); risk overlays using the semantic tokens at ~35–45% opacity with stroked boundaries or weighted circles (whichever the existing implementation uses — polish, don't rebuild); persistent legend chip row (Low/Med/High); tap → M3 bottom sheet with city, level, updated-time, and a "View details" action; camera animates to the user's profile city on open; loading skeleton over the map region until overlays are ready; graceful "map unavailable" error state (Maps SDK failures happen on emulators — another reason the demo device is physical).

**Technical impact.** Presentation-heavy; consumes an existing `GetAllCityRiskEstimates`-style use case (add additively if absent).

**Architecture impact.** None beyond additive query.

**Dependencies.** P0-1 (risk tokens shared with dashboard — the *same* three colors, by construction), M-5 seeding for multi-city data.

**Complexity.** Medium. **Risk.** Medium — Maps API key/quotas and OEM quirks; mitigate by testing on the demo device in week 2, not week 3.

**Acceptance criteria.**
1. All seeded cities render zones with correct semantic colors; legend always visible.
2. Tap any zone → bottom sheet in < 300 ms; "View details" deep-links to that city's risk view.
3. Map style consistent with app theme (at minimum: dark map style in dark mode).
4. No jank while panning with all overlays rendered.

**Definition of Done.** Merged; verified on physical device on real network and airplane-mode (cached tiles + error state); screenshots for report.

---

### M-3 · Notification Center Redesign

**Purpose.** The notification system is your backend's most sophisticated work (targeting, idempotency, throttling, audit). The Center is where that engineering becomes *visible*. It must feel like a first-class inbox, not a debug log.

**User story.** *As a user, I open Notifications and see my alerts grouped by day, unread ones clearly marked, color-coded by category (risk alert / medication / system), and I can swipe to dismiss or mark read, filter by category, and everything responds instantly.*

**Scope.**
1. **List redesign** — `AppListTile`-based rows: category color accent + icon, title, two-line body preview, relative timestamp, unread dot + subtly bolder title for unread.
2. **Grouping** — sticky date headers (Today / Yesterday / date).
3. **Categories & priority** — semantic mapping: risk alerts inherit risk-level colors; medication reminders use the primary/tertiary palette; system notices neutral. High-priority alerts get a stronger container treatment, not just a dot.
4. **Filtering** — M3 filter chip row (All / Risk / Medication / System / Unread). Client-side filter over the loaded window is acceptable at this data scale; note it as a conscious decision.
5. **Mark as read** — on open (detail view), on swipe action, and "Mark all read" in the app bar with confirmation snackbar + undo.
6. **Swipe actions** — swipe-to-dismiss with undo snackbar; the actual delete/mark call fires when the undo window expires (or immediately with rollback — choose one pattern, apply it to both actions, document it).
7. **Optimistic updates** — read/dismiss reflect instantly per §4.2 rule 3.
8. **States** — skeleton list (6 mirrored tiles), designed empty state ("You're all caught up" + illustration), error with retry, offline banner with cached data still shown.
9. **Pagination** — cursor-based "load more" on scroll if the existing repository supports it; if not, cap the query window (e.g., 50) and note it — do not build backend pagination this sprint.
10. **Motion** — list item entrance (staggered fade/slide ≤ 250 ms, first load only), animated removal on dismiss, badge count animates.

**Technical impact.** Use cases: `WatchNotifications` (stream, likely exists), `MarkNotificationRead`, `MarkAllRead`, `DismissNotification`, `WatchUnreadNotificationCount` (drives the shell badge). One Notifier owns list state + optimistic overlays + filter selection.

**Architecture impact.** Additive interface methods for read/dismiss if absent (these are user-owned notification documents — writing read-state is a legitimate existing app write-path, *not* a backend intrusion; confirm Firestore Security Rules already permit the owner to update read flags — if rules block it, that is a 3-line additive rules change to an app-owned field, flag it explicitly for review rather than working around it).

**Dependencies.** P0-1/2/3; M-5 seeded notifications across categories, priorities, read-states, and dates (grouping and filtering cannot be verified otherwise).

**Complexity.** High. **Risk.** Medium — optimistic-update rollback edge cases; mitigate with the single-pattern rule above and a manual test matrix (action × offline × failure).

**Acceptance criteria.**
1. 60 fps scroll with 50+ seeded notifications on the demo device.
2. Unread badge, list unread markers, and detail-screen read state never disagree (single stream of truth).
3. Swipe-dismiss + undo works offline (queued) or fails gracefully with revert — whichever pattern chosen, it never silently loses a notification.
4. All four states demonstrable on command (via seeding harness switches).
5. Filters combine with grouping correctly (empty filter result shows a filtered-empty state, distinct copy from true-empty).

**Definition of Done.** Merged; state-matrix manual tests recorded in a checklist; demo script updated to showcase swipe + undo + badge sync (a 15-second moment that reads as extremely polished).

---

### M-4 · Notification Details & Deep Linking

**Purpose.** Close the loop from push → meaning → action. A tapped FCM notification must land the user on a purposeful detail screen from any app state, including cold start.

**User story.** *As a user, when I tap a "High dengue risk in Karachi" push notification — even with the app closed — it opens directly to that alert's detail, showing full context and a button taking me to the Risk Dashboard for that city.*

**Scope.** Detail screen: category-colored header, full body, timestamp, related-entity context block (for risk alerts: level chip + city + "View risk dashboard" CTA; for medication: medication name + "Log dose" CTA); marks itself read on open; deep-link handling for all three FCM states (foreground / background-tap / terminated-tap via initial message) mapped through a single `NotificationRouteResolver` in the presentation layer that parses the existing payload contract and returns a typed route, with **fallback to the Notification Center** for unknown/missing payload types (never crash, never dead-end).

**Technical impact.** `GetNotificationById` use case; route resolver; FCM message handlers consolidated in one place (audit for duplicate handlers from earlier sprints — a classic source of double-navigation bugs).

**Architecture impact.** None structural. Payload contract is treated as frozen backend API; the resolver adapts to it.

**Dependencies.** P0-3 typed routes; M-3 read-state use cases.

**Complexity.** Medium. **Risk.** **High** — cold-start deep linking is the sprint's most failure-prone item (race with auth state restoration, splash timing, Android intent quirks). Mitigations: build in week 2 (two fix-cycles before demo); the resolver waits on the auth-ready provider before navigating; test matrix = 3 app states × 2 payload types × logged-in/out.

**Acceptance criteria.**
1. All six cells of the state × payload matrix land on the correct screen (logged-out lands on login, then continues to the target after auth — or, acceptable reduced scope: lands on home post-login; choose and document).
2. Unknown payload → Notification Center, with a debug log entry.
3. Detail open marks read; badge decrements everywhere within one frame of stream update.

**Definition of Done.** Merged; matrix executed on physical device and recorded; demo script includes one live push tap (sent via seeded FCM test or Firebase console) — rehearsed.

---

### M-5 · Demo Mode & Data Seeding Harness

**Purpose.** Decouple evaluation success from live infrastructure. Billing is postponed; weather APIs, Cloud Run jobs, and Scheduler cannot be assumed live or timely on demo day. The harness makes the full experience reproducible in 60 seconds.

**User story (team-facing).** *As the presenting team, we run one script and Firestore contains a realistic month of data for our demo account — three cities with distinct risk levels, risk history for trends, 20+ categorized notifications across dates and read-states, medication schedules with an adherence pattern that makes the weekly report interesting — and we can flip edge-case scenarios (stale data, empty inbox, offline) on demand.*

**Scope.** A Python (or Dart CLI) script in a `tools/` directory — *outside* `lib/`, explicitly not app code — that writes documents matching the backend's exact production schemas (copy field names from the deployed backend code, not from memory); named scenario presets (`demo-standard`, `edge-stale`, `edge-empty`, `edge-lowconfidence`); a written **demo script document**: screen-by-screen walkthrough order, the sentence to say on each screen, and the pre-demo checklist (device charged, seeded, notifications permission granted, airplane-mode fallback plan).

**Technical impact.** Zero app code. **Architecture impact.** None — and state this proudly in the viva: the app cannot distinguish seeded data from pipeline data *because* the schemas are honored, which is itself evidence the architecture's contracts are real.

**Dependencies.** Firestore access; backend schema reference.

**Complexity.** Low-Medium. **Risk.** Low — but it *removes* the largest project-level risk (demo dependent on postponed billing), which is why it is a Must Have.

**Acceptance criteria.** One command per scenario; idempotent (safe to re-run); demo account fully populated; edge scenarios switch in < 60 s.

**Definition of Done.** Script merged in `tools/`; three full dry-runs executed off the harness; demo script document finalized and rehearsed by both presenters.

---

### S-1 · Onboarding & First-Run Polish

**Purpose.** The evaluator's first 90 seconds: registration, profile setup, first dashboard. Currently likely functional-but-plain; make it guided and confident.

**User story.** *As a new user, I register, then a 3-step stepper (city → chronic conditions → notification permission with a value-explaining pre-prompt) sets me up, and I land on a dashboard that already speaks to my city and conditions.*

**Scope.** Auth screens restyled on the design system (proper field states, error inline-validation, loading button state — never a frozen UI during auth); profile setup as an M3 stepper with progress; **notification permission pre-prompt** (explain value *before* the OS dialog — materially improves grant rate and reads as thoughtful UX); post-setup landing celebrates readiness ("You're set — monitoring dengue, ILI and smog risk for Karachi").

**Complexity.** Medium. **Risk.** Low. **Architecture impact.** Presentation only (profile writes already exist).

**Acceptance criteria.** Fresh install → registered → personalized dashboard in < 90 s with zero dead ends; back-navigation through the stepper preserves entered data; both themes.

**DoD.** Merged; full fresh-install run recorded as the report's "user journey" figure sequence.

---

### S-2 · Health Resource Center Polish

**Purpose.** SDS Module 4 compliance at production quality, for low cost: it's a content list, a detail view, and emergency contacts.

**Scope.** Article cards (category chip, title, preview, reading time); detail screen with comfortable reading typography (larger line-height body style from the type scale); emergency contacts section with tap-to-call; high-risk advisory banner surfaced when the user's city is High (SDS FR3.3 "highlight critical alerts within the resource center"); empty/error/loading via core components.

**Complexity.** Low. **Risk.** Low. **Architecture impact.** None (existing content collection + use cases; additive query at most).

**Acceptance criteria.** All states render; tap-to-call works on device; high-risk banner appears iff seeded city risk is High.

**DoD.** Merged; two screenshots for report.

---

### S-3 · Weekly Health Report (reduced, honest scope)

**Purpose.** "Health Insights" reframed to what two devs can ship well in ≤ 3 days: an in-app weekly report *viewer* computed on demand from data that already exists — adherence logs + risk history — via application-layer composition. No new backend, no PDF.

**User story.** *As a user, I open Insights and see this week's story: adherence percentage with a ring, doses taken/missed by day (7 bars), my city's risk trajectory across the week, and one or two generated observations ("You missed evening doses on high-risk days").*

**Scope.** `GetWeeklyReportData(userId, weekStart)` use case aggregating existing repositories; report screen: adherence ring, 7-day bar row, risk-level strip (7 colored segments), observation cards (rule-based text from the aggregates — simple deterministic rules, presented plainly; do not label rule-based text as "AI"); report history = a week-picker over the same use case (no stored report documents — computed on read; state this design decision in the report: cheaper, always-consistent, no denormalization).

**Complexity.** Medium-High (aggregation correctness). **Risk.** Medium — timezone/week-boundary bugs; pin week logic to the user's local timezone and unit-test the aggregator (the one place this sprint where unit tests are non-negotiable).

**Architecture impact.** Additive use case + value objects; possibly additive ranged queries on adherence logs. Legal per §4.1.

**Acceptance criteria.** Numbers reconcile exactly against seeded fixtures (hand-computed expected values); empty week → designed empty state; charts render from tokens (semantic colors, no chart-library default palette clash — if a chart package is already in the project use it, otherwise these three visuals are simple enough to custom-paint, avoiding a new dependency).

**DoD.** Merged; aggregator unit tests green; one seeded "interesting week" scenario added to M-5 presets.

---

### N-1 → N-4 · Nice to Haves (abbreviated specs)

- **N-1 Share-as-image:** capture the report screen via a repaint boundary → system share sheet. AC: shared image is crisp on a real device; watermarked with app name. (Presentation-only.)
- **N-2 Minimal Admin System Status:** single read-only screen listing heartbeat doc freshness + last N audit entries with status chips. Strictly read-only; no controls; gated to admin role via existing RBAC. AC: renders live from Firestore; degrades to "no data" gracefully when jobs haven't run (the billing-postponed reality).
- **N-3 Hero transitions:** shared-element from dashboard risk card → risk detail; respect reduced-motion. AC: no frame drops; transition ≤ 400 ms.
- **N-4 Haptics:** light impact on dose-taken and mark-all-read confirmations. AC: fires once per action; silent on unsupported devices.


---

## 7. Cross-Cutting Workstreams (checklist-driven, not backlog modules)

### 7.1 Performance
Run these as a half-day profiling session in week 3 on the physical demo device, then fix findings:
- **Startup:** measure cold start; defer non-critical provider initialization; ensure the splash → home handoff doesn't rebuild the world twice.
- **Lists:** `ListView.builder` everywhere (never `Column` in a `SingleChildScrollView` for dynamic lists); `const` constructors audit; itemExtent/prototypeItem where rows are uniform.
- **Streams:** every Firestore stream consumed exactly once per screen via providers; no duplicate listeners (a common Riverpod pitfall when providers are re-created — verify with the Riverpod inspector / debug prints).
- **Images/maps:** map screen kept alive appropriately when tabbed away vs. disposed — pick based on memory measurements, not guesswork.
- **Frame budget:** DevTools performance overlay clean on: dashboard scroll, notification scroll (50 items), heatmap pan, theme switch.

### 7.2 The State Matrix Audit (the highest marks-per-hour activity in this sprint)
Build a spreadsheet: rows = every screen; columns = **loading / data / empty / error / offline × light / dark**. Two devs split the rows, walk every cell using M-5 scenario presets and airplane mode, and fix or file each ✗. Perceived quality is mostly the absence of broken cells in this matrix. Target: 100% of Must-Have screens ✓, ≥ 90% overall.

### 7.3 Error-Handling UX Policy (one policy, applied everywhere)
- User-caused, recoverable (validation): inline, next to the field.
- Transient system (network, timeout): `ErrorState` with retry on full-screen failures; snackbar with retry on action failures; optimistic rollbacks always explain themselves ("Couldn't mark as read — restored").
- Fatal/unknown: generic friendly screen; log detail; never show exception strings, stack traces, or Firestore error codes to users (audit for leaked `e.toString()` in snackbars — a classic).
- Offline: `OfflineBanner` + cached content where Firestore persistence provides it (confirm Firestore offline persistence is enabled — it materially improves the demo under bad venue Wi-Fi).

### 7.4 Motion Design Spec (decide once, in tokens)
- Durations: 150 ms (small state changes), 250 ms (standard transitions/entrances), 400 ms (emphasized/hero). M3 easing (`Easing.standard`, emphasized variants).
- Page transitions: M3 fade-through for tab switches; shared-axis for drill-downs.
- Rules: animate opacity/transform (cheap), not layout (expensive); entrance staggers on first load only, never on every rebuild; **all motion honors the OS reduced-motion setting** (check `MediaQuery.disableAnimations`); nothing loops indefinitely except skeletons.
- Micro-interactions budget: dose-taken confirmation (checkmark morph), badge count change, swipe-dismiss, pull-to-refresh with M3 indicator. Stop there — motion beyond this list is scope creep.

---

## 8. UI/UX Design Direction

### 8.1 Design references, translated into decisions (not mood-board hand-waving)
- **Apple HIG:** clarity of hierarchy — one primary element per screen (the risk level owns the dashboard); generous whitespace; text does the work before ornament.
- **Material 3:** the compliance baseline — tonal color system from a seed, `NavigationBar`, filter chips, bottom sheets, dynamic elevation. You are an M3 app; be an *exemplary* one rather than fighting it.
- **Linear:** speed as a feature — optimistic updates, skeletons over spinners, zero dead-time interactions.
- **Stripe:** trust through restraint — limited palette, strong typography, numbers presented with confidence and context ("82% confidence · Updated 3 h ago").
- **Airbnb:** warmth in empty states and onboarding copy — human sentences, not system messages.
- **Notion:** calm information density — grouped lists with clear headers (your notification grouping).
- **Uber:** map as canvas — desaturated map style so semantic color pops (your heatmap).
- **GitHub Mobile:** honest, compact list design with category color accents (your notification tiles).

### 8.2 Palette & tone for a healthcare product
Seed a **calm clinical teal/blue-green** primary (trustworthy, healthcare-coded, and — critically — *does not collide with the risk vocabulary*, since green/yellow/red must remain unambiguous). Neutral surfaces with M3 tonal elevation; reserve saturated color for meaning (risk levels, category accents, CTAs). Typography: the system font (Roboto) used *well* — a disciplined scale and weight contrast — beats a novelty font used badly; if differentiation is wanted, a single well-supported display font for large headings only. Copy tone: plain, calm, non-alarmist ("High smog risk today — limit outdoor time", never fear-mongering); this is a health product for potentially anxious users and evaluators will notice mature copywriting.

### 8.3 The three "wow moments" to engineer deliberately
Evaluation impressions hang on a few memorable seconds. Engineer exactly three, rehearse them:
1. **Dashboard reveal** — skeleton resolves into the full risk story in one beat; presenter says the one-line explanation of confidence + factors ("the model's actual probability and the environmental inputs behind it").
2. **Live push tap** — a real FCM notification arrives, tap, cold-start deep link straight to the alert detail, badge decrements. (Backend sophistication made visible.)
3. **Swipe + undo + badge sync** — dismiss a notification, undo it, watch the badge stay perfectly consistent. Small, silent, and it screams engineering discipline.

---

## 9. Accessibility Checklist (ship-blocking for Must-Have screens)
- Touch targets ≥ 48 dp; interactive elements have semantic labels (icon-only buttons especially: swipe actions, app-bar actions, map legend).
- Color never the sole signal: risk levels always icon + text + color (chips say "High", trend arrows have text).
- Contrast: 4.5:1 text, 3:1 UI graphics — verify the risk container colors in *both* themes, the classic failure point.
- Dynamic type: screens survive 1.3× font scale without clipped text or overflow stripes (test at 1.3× as part of the §7.2 matrix).
- TalkBack: complete the core journey (login → dashboard → notification → mark read) with screen reader on; announce risk level meaningfully ("Risk level high for Karachi, updated 3 hours ago").
- Reduced motion honored (§7.4); skeletons fall back to static placeholders.

---

## 10. Risk Register (sprint-level)

| # | Risk | L×I | Mitigation |
|---|---|---|---|
| R1 | Cold-start deep linking fails on demo device | M×H | Build in wk 2; auth-ready gating; 6-cell test matrix; fallback route |
| R2 | Demo depends on live pipeline that isn't running (billing postponed) | H×H | M-5 harness is Must Have; airplane-mode fallback plan; 3 rehearsals |
| R3 | RiskEstimates schema differs from assumptions (confidence field, factor fields) | M×H | Day-1 schema verification against deployed backend code; honesty-rule degradations designed in advance |
| R4 | Scope explosion in "polish" | H×M | MoSCoW cut line pre-agreed; polish runs as finite audits; feature freeze wk 3 day 5 noon |
| R5 | Animation jank on mid-range Android | M×M | Physical device from day 1; motion budget capped (§7.4); profile in wk 3 |
| R6 | Two-dev visual drift (each dev's screens look different) | M×M | Phase 0 tokens frozen first; gallery screen as the shared reference; cross-review every UI PR |
| R7 | Firestore rules block read-state writes | L×M | Verify rules in wk 1 during M-3 design; additive owner-field rule change if needed, explicitly reviewed |
| R8 | Maps SDK/key issues at venue | L×H | Test on venue-like network early; cached-tile behavior verified; map error state designed |

---

## 11. Process & Quality Gates
- **Branching:** feature branches per playbook ID (`sprint6/m1-risk-dashboard`); every PR cross-reviewed by the other dev against §4.2 rules + token grep.
- **Definition of Done (sprint-wide, additive to per-feature DoD):** `flutter analyze` clean; both themes checked; state matrix cells for touched screens re-verified; screenshots captured at merge time (report material accumulates for free).
- **Milestone gates:** end-wk-1 (foundation merged + seeding live), end-wk-2 (dry-run #1, all Must Haves demonstrable), wk-3 day-5 noon (feature freeze), day-5 EOD (dry-runs #2–3).
- **Report/viva leverage:** this playbook itself, the token appendix, the state-matrix spreadsheet, the risk register, and the before/after screenshot pairs are all direct FYP-report artifacts — budget zero extra time for them by capturing as you go.

---

## 12. What "Top 1%" Actually Looks Like Here (closing argument)
Not more features. It is: one visual language derived from tokens; zero broken cells in the state matrix; three rehearsed wow-moments; honest data presentation (real confidence values, visible staleness, no invented numbers — evaluators in a health domain probe exactly this); an architecture story you can defend in one sentence per layer; and a demo that cannot be taken down by Wi-Fi, billing status, or scheduler timing. Every item in this playbook serves one of those six outcomes. Anything that doesn't — however fun — is Future.

— End of Playbook —
