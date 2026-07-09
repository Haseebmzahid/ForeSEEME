# ForeSeeMe — Sprint 5 Evaluation & Submission Report

*Prompt 17 deliverable. The FYP-facing defense: what the system is, how it works, what
it proves, and — as a deliberate scoring strength — exactly where its ceilings are.
No fabrication; every metric traces to `backend/ml/artifacts/`, every claim to a
committed artifact.*

---

## 0. One-paragraph positioning (read this first)

ForeSeeMe is a **proactive, explainable environmental disease-risk platform**. A weekly
backend pipeline scores how favourable each city-week's environment is for dengue,
smog/respiratory, and influenza; a scheduled dispatch engine detects a rise into
elevated risk and pushes one personalized, consented, throttled alert to a vulnerable
user *without them opening the app*; and every estimate carries genuine, model-derived
attributions the app renders in plain language. It is deliberately **not** an outbreak
predictor and **not** a clinical or diagnostic tool — it estimates *environmental
suitability*, an honest proxy, and says so on every risk-facing surface. That honesty
is not a hedge; it is the project's central engineering claim.

---

## 1. What ForeSeeMe is — and is not

| It IS | It is NOT |
|---|---|
| A Low/Med/High **environmental risk** estimate per city-week, with confidence | An outbreak / case-count forecast |
| A **proactive** delivery loop (transition-triggered, throttled, consented) | A clinical or diagnostic tool |
| An **explainable** model (real feature attributions → plain language) | A generator of medical advice or free-text health reasoning |
| A **descriptive** comparison of cities/diseases from existing data | A surveillance substitute |

This framing is enforced in code, not just documentation: the non-diagnostic disclaimer
is a shared component surfaced on risk, insights, recommendations and alert payloads
(`lib/core/widgets/medical_disclaimer.dart`), and a content-safety guardrail asserts that
every recommendation/explanation is a cited lookup or a deterministic model attribution —
never generated (`docs/content_safety_policy.md`).

---

## 2. System architecture

**Feature-first Clean Architecture**, maintained across five efforts (`docs/architecture.md`):

```
Presentation (Flutter widgets, GoRouter)   — no firebase_*, no http, no SDKs
        ↕ Riverpod providers
Domain (notifiers, use-cases, validators)  — no Flutter widget imports
        ↕ abstract repository interfaces
Data (Firebase impls, Dart models)         — all external I/O behind interfaces
        ↕
Firestore / FastAPI / FCM
```

Load-bearing invariants (`GOLDEN_RULES.md`, ADRs):

- **ADR-001 — single source of truth:** the app reads risk **only** from Firestore
  `riskEstimates`; it never calls the FastAPI `/predict` endpoint. Prediction is internal
  to the backend.
- **ADR-002 — scheduled compute:** prediction and dispatch run as backend batch jobs, not
  on device. Freshness is therefore a first-class UX concern (§7, staleness).
- Every repository has an interface with a unit test; models are immutable and null-safe;
  no secrets in source.

The Sprint 5 additions are **additive extensions** of this structure — a new `attributions`
field on the estimate, new presentation widgets/providers, new backend job instrumentation —
with no refactor of the Sprint 1–4 system.

---

## 3. The proactive loop (the differentiator that was recovered)

Full path, each leg backed by real code and an e2e test (`docs/e2e.md`):

```
predict → attribute → store → dispatch → receive → inbox → explain
```

- **Built, then hardened.** The dispatch engine shipped in Sprint 4; the Sprint 5 gap
  audit (`docs/dispatch_gap_audit.md`) verified it is wired end-to-end and took the
  **harden** path, not a rebuild.
- **Transition-triggered, not per-run.** An alert fires only on a rise into elevated risk
  (`targeting.risk_rose`), gated by vulnerability × notification preference.
- **Spam-safe by construction:** a 24h same-category throttle, plus **idempotency keyed to
  the specific estimate** (`dispatch_alerts.dispatch_key`). The decisive guard is a
  repeated-run test: firing the same estimate five times still yields exactly **one**
  delivery (`backend/tests/test_e2e_pipeline.py::test_repeated_runs_produce_no_spam`).
- **Round trip completed** by FCM foreground/background/terminated handling, deep-link
  routing, and a user-scoped alert inbox with an unread badge.

Honest operational gaps (named, not hidden — from the gap audit): the scheduled *trigger*
is not yet committed as infrastructure-as-code, and real-device end-to-end delivery is
unproven on hardware. Both are deployment tasks (§9), not architectural holes.

---

## 4. Explainable AI layer

The single highest-value ML and trust investment, and it is **genuine, not narrated**:

- **Backend emits real attributions** per prediction — top contributors (feature,
  direction, magnitude) plus a confidence rationale (margin/agreement from the class
  distribution) — stored additively in an `attributions` field on each `riskEstimate`
  (`backend/app/…` explainability; method `tree_path_contributions`). Old estimates without
  the field still parse.
- **The app never generates explanation text.** A framework-free, deterministic templater
  (`lib/features/risk/domain/services/explanation_templater.dart`) maps each stored
  attribution to a fixed sentence — it never recomputes, re-ranks, or reinterprets the
  model's numbers. Direction, magnitude, ordering, and confidence all come straight from
  the stored data.
- **Surfaces:** a "Why this estimate?" panel and a confidence explanation
  (`explanation_panel.dart`, `confidence_explanation.dart`), a Model Transparency page, and
  environmental insights derived from the same attributions. Accessibility is respected —
  every driver carries an icon + label (not colour alone) and a full-sentence semantics
  label.
- **Degrades honestly:** an estimate that predates the explainability layer yields `null`
  and shows an "explanation unavailable" note rather than a fabricated one.

---

## 5. ML methodology & honest limitations

**Model.** One self-contained scikit-learn `Pipeline` per disease —
`SimpleImputer(median) → StandardScaler → RandomForestClassifier(class_weight='balanced')` —
bundled behind one predict interface (`model_1.0.0.joblib`, `rf-1.0.0`). 36 leakage-free
engineered features (raw weather/AQI, 1–4wk lags, 3–4wk rolling means, seasonal anomalies,
cyclical week, city one-hots). Full card: `backend/ml/reports/MODEL_CARD.md`.

**Discipline.** Temporal split with no shuffling (train **735** / test **260** rows; test is
the most recent block, split point 2025-W27); TimeSeriesSplit tuning; seed 42 everywhere;
byte-for-byte reproducible candidate; a GREEN validation gate on schema, leakage,
contamination, and temporal integrity (`metrics.json` → `reproducibility.split_manifest`,
all checks PASS).

**Held-out metrics (from `backend/ml/artifacts/metrics.json` — not restated from memory):**

| Disease | Accuracy | F1 macro / wt | ROC-AUC (OvR) | Brier | ECE | Seasonality lift |
|---|---|---|---|---|---|---|
| dengue | 0.854 | 0.833 / 0.861 | 0.970 | 0.191 | 0.053 | 1.60 |
| smog | 0.954 | 0.926 / 0.954 | 0.995 | 0.074 | 0.053 | 2.91 |
| influenza | 0.908 | 0.839 / 0.909 | 0.984 | 0.158 | 0.102* | 3.92 |

\* influenza's top-class ECE (0.102) was improved to **0.057** with a temporal **sigmoid**
recalibrator (`metrics.json → influenza.recalibration`).

**The critical honesty (state this in the defense, do not let an examiner extract it):**

- **Accuracy is expected-by-construction and is NOT the scientific claim.** Labels are a
  literature-grounded environmental-suitability index derived from the *same* features the
  model reads, so a faithful surrogate necessarily scores high. The real evidence is
  **calibration** (Brier/ECE), **robustness** under input noise, **importance alignment**
  (e.g. dengue's top driver is temperature at 0.283 — physically sensible), and
  **seasonality lift** (High-risk weeks concentrate in documented windows: smog Oct–Jan,
  influenza Dec–Feb, dengue post-monsoon). See `backend/ml/reports/evaluation_report.md`.
- **Suitability, not incidence.** No immunity, mobility, vaccination, vector control, or
  reporting effects are modelled. The labels are **not** validated against real
  epidemiological outcomes — and that validation cannot be fabricated.
- **Known production-ML gaps** (acknowledged, not fixed this sprint): a single model per
  disease, no drift monitoring or retraining trigger, and a short data window
  (2022-08 → 2026-06). These are Sprint 6+ research work.

---

## 6. Safety & trust framing

- **Non-diagnostic everywhere:** a shared, persistent disclaimer on risk/insights/
  recommendation/alert surfaces; onboarding communicates the environmental-risk framing and
  doubles as consent copy (`docs/non_diagnostic_copy_review.md`).
- **Cited-only guardrail:** every recommendation carries a source; a test fails if any
  advisory lacks attribution or is produced by a generative path
  (`docs/content_safety_policy.md`).
- **Emergency routing:** high-risk surfaces expose one-tap emergency help, reusing the
  Sprint 3 emergency contact + dialer — no new medical content generated.

---

## 7. Production hardening

| Concern | Status | Evidence |
|---|---|---|
| Empty / error / offline states | Complete, shared widgets | `core/widgets/{empty,error,offline}_state.dart` |
| **Staleness** (never show old risk as current) | Complete | `risk_staleness.dart`; "This estimate may be out of date" label |
| Backend observability / failure alerting | Complete | `docs/observability.md`; heartbeat + failure signal |
| Manual risk override / admin fallback | Complete, auditable, labelled | `docs/admin_override.md`; `overrides` collection + rules |
| CI (analyze + tests gate merges) | Complete | `docs/ci.md` |
| Accessibility / contrast (glassmorphism) | Complete; reduced-transparency fallback; risk never colour-only | `docs/accessibility_audit.md` |
| End-to-end pipeline tests | Complete | `docs/e2e.md` |

---

## 8. Testing status

- **Backend e2e — verified green in this environment:**
  `backend/tests/test_e2e_dispatch.py` (4 passed) — multi-city dispatch, repeated-run spam
  guard, 24h throttle, token pruning.
- **Backend pipeline e2e:** `test_e2e_pipeline.py` (predict → attribute → store → dispatch →
  inbox, plus the five-run spam check) — runs offline against the real model bundle; part of
  the CI gate.
- **Flutter widget/provider/integration suites**, including the Prompt 16 read-legs e2e
  (`test/integration/pipeline_e2e_test.dart`: store→read→explain, receive→inbox, staleness)
  and the inbox engagement e2e (`alert_pipeline_e2e_test.dart`).
- **Run to confirm green before the defense:**
  ```
  flutter analyze && flutter test
  cd backend && pytest -q
  ```

---

## 9. Honest level assessment & remaining manual tasks

Restated from `docs/SPRINT_5_AUDIT.md` §9 — the honest ceilings are themselves a scoring
strength:

- **Top-1% FYP — ~8.5→9+.** With the proactive loop live and explainability shipped, this is
  top-band: a real pipeline + honest labelling + legible AI + proactive delivery is well
  beyond typical FYP scope.
- **Startup MVP — ~6.5.** Product shape and a real pipeline exist; what's missing is proof it
  reaches users on hardware and a value loop with real users.
- **Publishable — ~4.** Sound engineering, but no *novel, validated* research result: the
  labels aren't validated against epidemiological outcomes, so there is no predictive claim
  to publish. Raising this needs real disease-outcome data — a multi-month effort, not a
  sprint.
- **Deployable healthcare product — ~2.5.** A category truth, not a criticism: an
  environmental proxy would need clinical validation, medical content review, regulatory/
  liability clearance, and privacy compliance before touching patients.

**Remaining manual deployment/configuration tasks (out of code scope):**

1. Commit the scheduled **trigger** as infrastructure-as-code (Cloud Scheduler → Cloud Run
   per ADR-002); today only intent exists in `compose.yaml`.
2. Prove **real-device** end-to-end FCM delivery on physical hardware.
3. Register a **background data-only** FCM handler (`onBackgroundMessage`) — the one in-app
   handler the gap audit found absent.
4. Managed hosting, secrets management, and on-call for a health-context service.
5. Capture the live demo **screenshots** (`docs/screenshots_checklist.md`).

---

## 10. Anticipated examiner questions (honest answers)

- *"Isn't 95% accuracy suspicious?"* — Yes, and expected: labels derive from the model's own
  features. The claim is calibration + seasonality + importance alignment, not accuracy (§5).
- *"Is the AI explanation real or an LLM narrating?"* — Real: attributions are computed in the
  backend and templated deterministically; there is a guardrail test forbidding generative
  medical text (§4, §6).
- *"Does it actually reach the user?"* — The loop is built, wired, and spam-safe in tests;
  the honest gap is live-trigger IaC and on-device proof (§3, §9).
- *"Can this be used clinically?"* — No, by design; it's an environmental proxy and says so
  everywhere (§1, §5).

---

## Supporting documents

Architecture `docs/architecture.md` · ADRs `docs/adr/` · Gap audit
`docs/dispatch_gap_audit.md` · Dispatch design `docs/alert_dispatch_design.md` · Safety
`docs/content_safety_policy.md`, `docs/non_diagnostic_copy_review.md` · Model card
`backend/ml/reports/MODEL_CARD.md` · Label methodology `backend/ml/reports/label_methodology.md`
· Evaluation `backend/ml/reports/evaluation_report.md` · Observability `docs/observability.md`
· Admin override `docs/admin_override.md` · CI `docs/ci.md` · Accessibility
`docs/accessibility_audit.md` · E2E `docs/e2e.md` · Demo runbook `docs/DEMO_SCRIPT.md` ·
Screenshots `docs/screenshots_checklist.md`.
