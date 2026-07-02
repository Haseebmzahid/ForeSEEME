# Content Safety Policy (Sprint 5, Prompt 4)

ForeSeeMe never generates medical content. Every user-facing advisory is a
**cited lookup** or a **deterministic model attribution**. This document states
the policy and the code/tests that enforce it (GOLDEN_RULES **Rule 11**).

## The rule

- **Allowed:** advisory text drawn verbatim from a fixed, cited library
  (recommendations); deterministic, model-derived attributions (Phase 3
  explanations). Each carries a real `source` + `https://` `sourceUrl`.
- **Forbidden:** free-text medical summaries, LLM/generative "explanations",
  prescriptive care plans, any advisory synthesised at runtime, or any advisory
  shown without an attribution.

## What is generated vs looked up

| Surface | Content | Origin | Cited? |
|---|---|---|---|
| Recommendations (dashboard, insights, risk details) | `HealthRecommendation` | `StaticRecommendationRepository` fixed `(category, driver)` table | Yes — `source` + `sourceUrl` |
| Alert payloads (`userAlerts`) | recommendation snapshot | backend `recommendation_lookup.py` fixed table | Yes — mirrors the Flutter table field-for-field |
| Risk value / confidence / primary driver | model output | Sprint 2 RF model via `riskEstimates` | Deterministic model output (not advice) |
| Phase 3 "why this prediction" (future) | feature attributions | genuine SHAP/permutation values, templated deterministically | Must pass the same guard — attribution is the "source" |
| Nothing, anywhere | — | **no generative/LLM path exists in the codebase** | — |

## Enforcement in code

`lib/core/safety/content_safety_guard.dart` — `ContentSafetyGuard`:

- `isCited(source, sourceUrl)` — true iff a non-empty source and an `https://`
  URL are present.
- `requireCited(...)` — throws `ContentSafetyViolation` otherwise.

Wired at the composition point `currentRecommendationProvider`
(`insights_providers.dart`): the recommendation returned to the UI is guarded
before it is surfaced. A violation becomes an `AsyncError` that the
recommendation card renders as *hidden* — so an un-sourced advisory can never be
shown, and CI catches the defect via the guard tests.

The guard is intentionally reusable for Phase 3: an explanation/attribution
record passes its `(source, sourceUrl)` — e.g. the model + method as the source
— through the same `requireCited` check.

## Emergency routing

High-risk surfaces expose one-tap emergency help, reusing the Sprint 3 emergency
contact infrastructure (no new content):

- `emergencyContactProvider` → `kRescue1122` (Punjab Emergency Service).
- `EmergencyCard` + `launcherServiceProvider.dialPhone` (a `tel:` intent).
- **Risk Details** shows the `EmergencyCard` immediately below the hero **only
  when the current estimate is `RiskLevel.high`**.
- The **Resource Center** already surfaces the emergency card always and lifts
  Nearby Hospitals when city risk is High.
- Every cited recommendation additionally carries an `escalation` line routing
  to professional/emergency care ("emergency → Rescue 1122").

## Tests (regression guards)

`test/features/safety/content_safety_test.dart`:

- **Library integrity** — every `StaticRecommendationRepository.all` entry passes
  `requireCited` (non-empty source, `https://` url).
- **No generative path** — for a large matrix of arbitrary/junk `(category,
  driver)` inputs, `lookup` only ever returns objects from the fixed library
  (never a synthesised instance).
- **Runtime guard** — `currentRecommendationProvider` throws
  `ContentSafetyViolation` when a repository yields an un-sourced advisory.
- **Emergency affordance** — the `EmergencyCard` renders on a High estimate,
  dials `1122` on tap, and is absent on Low/Medium.

## Checklist for future advisory features

- [ ] Content comes from a fixed cited library or a genuine model attribution.
- [ ] `source` + `https://` `sourceUrl` present; run it through `requireCited`.
- [ ] No runtime string synthesis of medical claims; no LLM/generative call.
- [ ] The surface carries a `MedicalDisclaimer` (Prompt 3) and, on high risk, an
      emergency affordance.
