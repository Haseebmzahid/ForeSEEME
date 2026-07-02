# ForeSeeMe — Sprint 5 Implementation Playbook

*The path to production readiness. Prompts are Claude Code–ready; run in order; review after each.*

**Sprint 5 goal:** close/verify the proactive loop, make the AI safe and legible, add only the curated high-value features, harden to production quality, and prepare a top-1% evaluation — without refactoring the existing Sprint 1–4 system.

**Invariants (unchanged):** Feature-first Clean Architecture (Presentation → Provider → Use Case → Repository interface → impl → Firebase/APIs); no Firebase in UI; every repository has an interface; DI via Riverpod; Flutter reads risk only from Firestore; dispatch/compute run as backend scheduled jobs. No fabricated or generated medical content — recommendations and explanations are cited lookups or deterministic model attributions only.

**Per-prompt reporting contract (every prompt ends with this, then stops — do NOT commit):** Files created · Files modified · Architecture decisions · Tests added · Analyze result · Acceptance criteria met · Proposed commit message. *"Stop after completing this task. Do not commit. Wait for review before continuing."*

**Effort legend (solo dev + Claude Code + review):** Low ≤ half-day · Med ~1 day · High 2–3 days.

**Open dependency:** Phase 1's scope depends on whether a proactive dispatch engine already exists (audit §0). Phase 1 resolves this by verification first.

---

# PHASE 1 — Close / Verify the Proactive Loop (foundation)

### Prompt 1 — Dispatch Engine Gap Audit (verification, no build)
- **Objective:** establish ground truth — does a scheduled engine that pushes personalized, transition-triggered, throttled alerts to users (without them opening the app) exist and work?
- **Context:** the platform is positioned as proactive; this prompt determines whether the loop is built or missing before any code is written.
- **Dependencies:** none.
- **Constraints:** read-only investigation; do not modify code. Inspect `backend/app/jobs/`, FCM send paths, throttle/idempotency logic, `alertDispatchLog`/`userAlerts` collections, and in-app FCM handlers.
- **Expected files:** `docs/dispatch_gap_audit.md` only.
- **Tests:** none (audit); list which existing tests, if any, cover dispatch.
- **Acceptance:** the report states clearly PRESENT or ABSENT for each of: scheduled dispatch job, transition detection, targeting by vulnerability + preference, 24h throttle, idempotency, audit log, token pruning, in-app foreground/background/terminated handling, alert inbox.
- **Risks:** false confidence — be literal about what exists vs planned.
- **Effort:** Low. **Commit boundary:** `docs: proactive dispatch engine gap audit`.

### Prompt 2 — Build or Harden the Loop (branches on Prompt 1)
- **Objective:** make the proactive loop real and safe.
- **Context:** two paths. **If ABSENT:** execute the dispatch prompts already specified in `docs/SPRINT_4.md` (Phases A–B: contract → engine → throttle/idempotency/token-hygiene → in-app handling → inbox) — do not re-invent them here. **If PRESENT:** perform a hardening pass instead.
- **Dependencies:** Prompt 1.
- **Constraints (hardening path):** add/repair only — no redesign. Verify transition-triggering (not per-run resend), 24h throttle, idempotency keyed to the specific estimate, token pruning, and preference enforcement.
- **Expected files:** per `SPRINT_4.md` (build path) or targeted fixes (harden path).
- **Tests:** the decisive one — **run the dispatch job twice back-to-back on identical seeded data and assert the second run sends zero messages**; plus targeting (vulnerable vs not, enabled vs disabled), token pruning.
- **Acceptance:** a vulnerable, consenting user receives exactly one alert on a transition into elevated risk; opted-out/non-matching users receive none; re-runs and within-24h events send nothing; dead tokens pruned.
- **Risks:** alert fatigue / duplicate sends — the two-run test is the guard.
- **Effort:** High (build) / Med (harden). **Commit boundary:** `feat(alerts): proactive dispatch loop verified spam-safe` (or per SPRINT_4 prompts).

---

# PHASE 2 — Safety & Trust Framing (GATE — must precede Phases 3–4)

### Prompt 3 — "Not Medical Advice" Framing & Non-Diagnostic Language
- **Objective:** make explicit, everywhere, that ForeSeeMe provides environmental risk estimates, not medical diagnosis.
- **Context:** ethical and liability requirement before any AI-facing feature ships.
- **Dependencies:** none (do before Phase 3).
- **Constraints:** a shared, reusable disclaimer component surfaced on risk, insights, recommendations, and alert payloads; onboarding sets expectations and doubles as consent copy; audit existing copy for diagnostic phrasing and soften to descriptive. No Firebase in UI; component is presentation-layer only.
- **Expected files:** `lib/core/widgets/medical_disclaimer.dart` (or shared components dir), modifications to risk/insights/recommendation/alert surfaces, onboarding copy.
- **Tests:** widget test asserting the disclaimer renders on each target surface; copy-review checklist.
- **Acceptance:** no screen implies clinical diagnosis; disclaimer present and consistent; onboarding communicates the environmental-risk framing.
- **Risks:** low; omission is a critical exposure.
- **Effort:** Low–Med. **Commit boundary:** `feat(core): add non-diagnostic medical framing across risk-facing surfaces`.

### Prompt 4 — Medical-Content Guardrail & Emergency Routing
- **Objective:** enforce in code that recommendations/explanations are cited lookups or deterministic attributions — never generated — and provide an emergency affordance.
- **Context:** codifies the project philosophy as a testable guarantee.
- **Dependencies:** Prompt 3; existing recommendation/content library.
- **Constraints:** every recommendation must carry a source; add a guard/test that fails if a recommendation or explanation lacks attribution or is produced by a generative path; add an emergency-help affordance (reuse Sprint 3 emergency contacts).
- **Expected files:** `docs/content_safety_policy.md`, a guard util + tests, emergency affordance on high-risk surfaces.
- **Tests:** assert recommendations/explanations always have a source; assert no generative medical path is invoked; emergency affordance renders on high risk.
- **Acceptance:** the guard passes; every user-facing advisory is sourced; emergency help is reachable when risk is high.
- **Risks:** a future feature bypassing the guard — the test prevents regressions.
- **Effort:** Low–Med. **Commit boundary:** `feat(safety): enforce cited-only medical content guardrail and emergency routing`.

---

# PHASE 3 — Explainable AI Layer (the differentiator)

### Prompt 5 — Backend: Emit Genuine Feature Attributions & Confidence Rationale
- **Objective:** compute per-prediction feature attributions and a confidence rationale in the pipeline; store them additively on each `riskEstimate`.
- **Context:** the single highest-value ML addition. **Additive extension** of `compute_risk` — not a refactor; existing documents remain valid.
- **Dependencies:** Sprint 2 model/pipeline.
- **Constraints:** use SHAP TreeExplainer (exact for RF) or equivalent genuine attribution — **never** hand-authored or generated values; store top-N contributions (feature, direction, magnitude) + a confidence rationale (margin/agreement from the class distribution) in a new `attributions` field. Backfill for existing estimates is optional and clearly separated. Do not change the prediction contract's existing fields.
- **Expected files:** `backend/app/explain.py` (or `attribution.py`), modified `backend/app/jobs/compute_risk.py`, schema note for the additive field, tests.
- **Tests:** attributions sum/relate to the model output sensibly; deterministic for fixed input; additive field present without breaking existing readers; old documents without the field still parse.
- **Acceptance:** each new estimate carries genuine top drivers with direction/magnitude and a confidence rationale, all model-derived.
- **Risks:** the shortcut of faking attributions — forbidden; SHAP must be real. Performance of per-city SHAP is negligible at 5 cities.
- **Effort:** Med–High. **Commit boundary:** `feat(ml): emit genuine feature attributions and confidence rationale per estimate`.

### Prompt 6 — Flutter: "Why This Prediction?" & Confidence Explanation
- **Objective:** render the stored attributions and confidence rationale as plain-language explanation via deterministic templates.
- **Context:** the trust surface; consumes Prompt 5 data.
- **Dependencies:** Prompt 5; Phase 2 gate passed.
- **Constraints:** deterministic templating only (attribution → sentence); no generative text; accessible (label + icon, not color-only); reads via existing risk repository/providers.
- **Expected files:** `lib/features/risk/presentation/widgets/explanation_panel.dart`, `confidence_explanation.dart`, provider additions.
- **Tests:** template maps known attributions → expected copy; renders across High/Med/Low + low-confidence; no generative path.
- **Acceptance:** users see, in plain language, the real top drivers of their risk and why confidence is high/low — matching the model.
- **Risks:** templates drifting from model semantics — keep them mechanical.
- **Effort:** Med. **Commit boundary:** `feat(risk): add explainable "why this prediction" and confidence explanation`.

### Prompt 7 — Model Transparency Page
- **Objective:** a page documenting data provenance, label methodology, limitations, and the model card.
- **Context:** reinforces the honest-labelling story; strong evaluation asset.
- **Dependencies:** Prompt 6.
- **Constraints:** static, sourced content (from the model card / label methodology docs); explicitly states "environmental risk, not outbreak/clinical prediction"; reachable from settings/insights.
- **Expected files:** `lib/features/insights/presentation/model_transparency_screen.dart` (+ content), navigation entry.
- **Tests:** renders; contains provenance, limitations, and the not-clinical statement.
- **Acceptance:** an examiner can read exactly how risk is produced and its limits.
- **Risks:** none material.
- **Effort:** Low. **Commit boundary:** `feat(insights): add model transparency page`.

---

# PHASE 4 — Curated Value Features (only these; defer the rest)

### Prompt 8 — Weekly Health Report (proactive digest)
- **Objective:** a periodic digest tying current risk + adherence insights + cited recommendations into one proactive touchpoint.
- **Context:** the one great new proactive feature; uses the dispatch/inbox channel from Phase 1.
- **Dependencies:** Phase 1; existing insights + recommendations.
- **Constraints:** compose from existing signals only; descriptive, non-diagnostic; cited recommendations; delivered via the existing alert channel + viewable in-app.
- **Expected files:** report composition use case, `weekly_report_screen.dart`, dispatch hook.
- **Tests:** composition from fixtures; renders across data states; disclaimer present.
- **Acceptance:** a user receives/opens a weekly report summarizing their risk and adherence with sourced guidance.
- **Risks:** becoming noise — respect notification preferences and throttle.
- **Effort:** Med. **Commit boundary:** `feat(insights): add weekly health report digest`.

### Prompt 9 — City & Disease Comparison (descriptive)
- **Objective:** compare risk across the five cities and across diseases for a city.
- **Context:** cheap, high-value use of existing multi-city data.
- **Dependencies:** existing `riskEstimates`.
- **Constraints:** descriptive only; reuse risk repository (add read query if needed, additive); accessible charts (not color-only).
- **Expected files:** `lib/features/risk/presentation/comparison_screen.dart`, provider/query additions.
- **Tests:** query returns latest per city/disease; widget renders; empty/missing handled.
- **Acceptance:** users can compare cities and diseases at a glance.
- **Risks:** low.
- **Effort:** Med. **Commit boundary:** `feat(risk): add city and disease comparison`.

### Prompt 10 — Environmental Insights & Recommendation Prioritization
- **Objective:** surface what in the environment drives current risk (from Phase 3 attributions) and rank recommendations by relevance/severity.
- **Context:** natural extension of explainability; small ranking improvement.
- **Dependencies:** Phases 3; recommendation engine.
- **Constraints:** insights derived from real attributions; prioritization deterministic; cited.
- **Expected files:** `environmental_insights_card.dart`, prioritization util + tests.
- **Tests:** insights reflect attributions; prioritization order deterministic for known inputs.
- **Acceptance:** users see environmental drivers and the most relevant guidance first.
- **Risks:** low.
- **Effort:** Low–Med. **Commit boundary:** `feat(insights): add environmental insights and recommendation prioritization`.

---

# PHASE 5 — Production Hardening

### Prompt 11 — Complete Unhappy Paths + Staleness Indicator
- **Objective:** finish empty/error/offline states and show a staleness indicator when the latest estimate is old.
- **Context:** premium apps are judged on unhappy paths; a health app must never silently show stale risk as current.
- **Dependencies:** existing risk surfaces.
- **Constraints:** consistent shared states; staleness computed from the estimate timestamp with a documented threshold; offline uses Firestore cache with a clear indicator.
- **Expected files:** shared state widgets (extend existing), staleness util, modifications to risk surfaces.
- **Tests:** each state renders; stale estimate shows the indicator; offline path shows cached + hint.
- **Acceptance:** no blank/misleading screens; stale data is labeled honestly.
- **Risks:** inconsistent states across screens — centralize.
- **Effort:** Med. **Commit boundary:** `feat(ux): complete empty/error/offline states with staleness indicator`.

### Prompt 12 — Backend Observability & Failure Alerting
- **Objective:** know when the pipeline or dispatch job fails.
- **Context:** silent failure of a health pipeline is dangerous (audit H1).
- **Dependencies:** Sprint 2 jobs; Phase 1 dispatch.
- **Constraints:** structured logging + a failure signal (e.g., a monitored log-based alert / heartbeat doc) when a scheduled run errors or produces zero output unexpectedly; no secrets in logs.
- **Expected files:** logging/heartbeat additions to `compute_risk` and `dispatch_alerts`, `docs/observability.md`.
- **Tests:** a simulated job failure raises the signal; a successful run writes a heartbeat.
- **Acceptance:** an operator can detect a failed/empty run; staleness (Prompt 11) is the user-facing complement.
- **Risks:** alert noise — threshold sensibly.
- **Effort:** Med. **Commit boundary:** `feat(backend): add job observability and failure alerting`.

### Prompt 13 — Manual Risk Override / Admin Fallback
- **Objective:** allow an authorized operator to override a city's risk estimate when the pipeline lags or errs.
- **Context:** the long-flagged fallback for data delays; safety valve for a live health signal.
- **Dependencies:** `riskEstimates`; auth roles.
- **Constraints:** minimal internal surface (a guarded screen or script — do not over-build); overrides recorded in an `overrides` collection with author + reason + timestamp; app clearly indicates an override is active; rules restrict to an admin role.
- **Expected files:** override write path, `overrides` schema + rules, admin surface, indicator on risk surfaces.
- **Tests:** override applies and is labeled; non-admin denied by rules; audit fields recorded.
- **Acceptance:** an operator can safely correct a stale/wrong estimate, transparently.
- **Risks:** unlabeled overrides eroding trust — always indicate.
- **Effort:** Med. **Commit boundary:** `feat(admin): add auditable manual risk override`.

### Prompt 14 — CI Pipeline
- **Objective:** gate merges on analyze + tests for both Flutter and backend.
- **Context:** "CI-quality code" becomes an enforced control.
- **Dependencies:** existing test suites.
- **Constraints:** run `flutter analyze` + `flutter test` and backend lint + pytest on PR; fail on regressions; no secrets in CI config.
- **Expected files:** CI workflow config, `docs/ci.md`.
- **Tests:** the pipeline runs green on a clean PR and red on an intentional failure.
- **Acceptance:** no PR merges with failing analyze/tests.
- **Risks:** flaky tests blocking merges — stabilize first.
- **Effort:** Low–Med. **Commit boundary:** `ci: add analyze + test gates for flutter and backend`.

### Prompt 15 — Accessibility & Contrast Audit
- **Objective:** ensure glassmorphism and risk encodings meet accessibility standards.
- **Context:** translucent surfaces risk poor contrast; risk must never be color-only (audit M4).
- **Dependencies:** UI surfaces.
- **Constraints:** audit contrast on translucent surfaces; provide a solid-surface/reduced-transparency fallback; confirm every risk signal has label + icon; verify with the reduced-motion path.
- **Expected files:** contrast fallbacks, `docs/accessibility_audit.md`.
- **Tests:** contrast checks on key surfaces; risk indicators assert label + icon presence.
- **Acceptance:** readable under reduced-transparency; no color-only risk signals.
- **Risks:** aesthetic pushback — accessibility wins.
- **Effort:** Low–Med. **Commit boundary:** `fix(a11y): contrast fallbacks and non-color-only risk encoding`.

### Prompt 16 — End-to-End Pipeline Tests
- **Objective:** prove the full loop: predict → attribute → store → dispatch → receive → inbox → explain.
- **Context:** the integration guarantee for the whole system.
- **Dependencies:** Phases 1–5.
- **Constraints:** run against a test project/emulator; include the repeated-run spam check and a staleness scenario.
- **Expected files:** e2e test suite, `docs/e2e.md`.
- **Tests:** full happy path; repeated-run produces no spam; stale scenario labeled; opted-out user receives nothing.
- **Acceptance:** the end-to-end pipeline passes on a test project.
- **Risks:** environment flakiness — isolate with a dedicated test project.
- **Effort:** Med–High. **Commit boundary:** `test: end-to-end proactive pipeline coverage`.

---

# PHASE 6 — Evaluation & Submission Readiness

### Prompt 17 — Evaluation & Submission Deliverables (mostly non-code)
- **Objective:** convert the product into a top-1% defense.
- **Context:** the FYP-facing packaging.
- **Dependencies:** all prior phases.
- **Constraints:** no fabrication; state limitations honestly (environmental proxy; not clinical; publishability/deployment ceilings per audit §9).
- **Expected files:** final report sections (architecture, ML methodology + honest limitations, safety framing), a **demo script** that shows the proactive loop live and the spam-safe repeated-run demo, polished model card, screenshots.
- **Tests:** n/a (review the demo runs live end-to-end).
- **Acceptance:** the demo shows a real, explainable, proactive, safe system; the report is honest about scope and limits.
- **Risks:** over-claiming — the honest framing is itself a scoring strength.
- **Effort:** Med. **Commit boundary:** `docs: sprint 5 evaluation and submission deliverables`.

---

## Sprint 5 Exit Criteria
The proactive loop is live and spam-safe; every AI-facing surface is safely framed and non-generative; predictions are explainable from genuine model attributions; the curated features (weekly report, comparison, environmental insights) ship; unhappy paths and staleness are complete; the backend is observable with an override fallback; CI gates merges; accessibility passes; the end-to-end pipeline is proven; and the submission package honestly demonstrates a real, explainable, proactive, production-shaped AI health platform. Sprint 1–4 remain intact and green.

## Recommended Implementation Order
1 → 2 (resolve/close the loop) → **3 → 4 (safety gate)** → 5 → 6 → 7 (explainability) → 8 → 9 → 10 (curated features) → 11 → 12 → 13 → 14 → 15 → 16 (hardening) → 17 (submission). Do not reorder the safety gate ahead of explainability/features.

## Post-Sprint-5 (Sprint 6+ / production)
Forward multi-week forecasting (genuine + validated); model drift monitoring + retraining; counterfactual explanations; more cities. For real deployment: clinical/epidemiological validation, medical content review, regulatory/liability assessment, privacy compliance, managed hosting + secrets + on-call, and retention instrumentation.
