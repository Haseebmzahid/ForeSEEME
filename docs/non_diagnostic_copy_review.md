# Non-Diagnostic Copy Review (Sprint 5, Prompt 3)

ForeSeeMe provides **environmental risk estimates**, not medical diagnosis. This
document records the copy audit performed in Prompt 3, the shared framing
component introduced, and a reusable checklist to keep future copy honest.

## Shared component

`lib/core/widgets/medical_disclaimer.dart` — `MedicalDisclaimer` (presentation
only, Design System v2). Two variants:

- `MedicalDisclaimer.banner()` — full panel for screen footers.
- `MedicalDisclaimer.inline()` — compact one-liner for dense surfaces.

Canonical copy (single source of truth — do not fork per screen):

> ForeSeeMe shows environmental risk estimates based on weather and air-quality
> data — not a medical diagnosis or personal medical advice. Always consult a
> qualified healthcare professional about your health. In an emergency, call
> Rescue 1122.

## Where it is surfaced

| Surface | File | Placement |
|---|---|---|
| Dashboard (risk) | `dashboard_screen.dart` | inline, under the risk card |
| Risk details | `risk_details_screen.dart` | banner, pinned footer (all data states) |
| Explainable Health Intelligence (risk + why + contributors + recommendations) | `health_intelligence_screen.dart` | banner, pinned footer (all data states; superseded `health_insights_screen.dart`) |
| Alert inbox (alert payloads) | `alert_inbox_screen.dart` | inline, pinned footer (present even when empty) |
| Onboarding / consent | `notification_permission_screen.dart` | inline, at the consent point |

Recommendations are framed by the screen-level disclaimer everywhere they appear
(dashboard, insights, risk details); the recommendation content itself already
carries a cited **Source:** line and an escalation-to-help line (Rule 11).

## Copy audit — diagnostic-phrasing sweep

Ran a lexical sweep across `lib/` for diagnostic phrasing (`diagnos*`,
`you have`, `will get/develop`, `symptom`, `cure`, `clinical`, `predict … you`,
`your chance/risk of <disease>`). Findings:

- **No screen implies a clinical diagnosis.** Risk is consistently labelled as
  the *environmental* risk of a named disease for a *city* (e.g. "Lahore ·
  Smog"), never a personal clinical verdict.
- The only `clinical` matches are in **code comments** (`risk_driver_service`,
  `risk_card`) explicitly stating a value is *not* an additional clinical claim —
  correct, not user-facing.
- `symptom` appears only inside **cited recommendation/escalation copy** ("if
  symptoms worsen … seek care"), which is guidance-to-professional, not
  diagnosis.
- `Health score` / composite clinical scores: **none present** (audit M-item
  guidance respected).
- Existing recommendation fallback already reads "general information, not
  personal medical advice" (`static_recommendation_repository.dart`).

No user-facing copy required softening; the one bespoke disclaimer that existed
(Health Insights) was replaced by the shared component for consistency.

## Reusable checklist (apply to every new risk-/AI-facing surface)

- [ ] The surface shows a `MedicalDisclaimer` (banner for a screen, inline for a
      dense card/flow) — do not hand-roll disclaimer text.
- [ ] Risk is described as an **environmental estimate** for a place, never a
      personal diagnosis ("your risk of X" implying clinical certainty is
      banned).
- [ ] No word implies diagnosis/cure/prognosis: `diagnose`, `you have`, `you
      will develop`, `cured`, `guaranteed`.
- [ ] Any advisory text is a **cited lookup** (shows `Source:`) or a
      deterministic model attribution — never generated (Rule 11; enforced in
      Prompt 4).
- [ ] Risk is never encoded by colour alone (label + icon present).
- [ ] An escalation/emergency route is reachable from high-risk guidance
      (Rescue 1122).
- [ ] Onboarding/consent copy sets the environmental-risk expectation before the
      user opts in.

## Tests

`test/features/core/medical_disclaimer_test.dart` — asserts the component
renders both variants and the canonical copy, exposes a single "Disclaimer:"
semantics group, and that the disclaimer is present on each target surface
(onboarding, health insights, risk details, alert inbox).
