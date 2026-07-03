# Accessibility & Contrast Audit (Sprint 5, Prompt 15)

*Resolves audit **M4**: glassmorphism contrast on translucent surfaces, and risk
that must never be conveyed by colour alone. Extends the Sprint-3 audit
(`docs/sprint3-accessibility-audit.md`).*

## 1. Contrast on the glass surface

Neutral cards use a translucent fill (`glassFill`, white @ ~4.3%) over the deep
shell. Text/icon contrast is measured against the **effective** surface — the fill
composited over the shell = **`#101219`** — using the WCAG utility in
`lib/core/theme/a11y.dart` (verified by `test/accessibility/contrast_audit_test.dart`).

| Foreground | Ratio on glass | AA (4.5 text / 3.0 UI) |
|---|---:|:---:|
| `textPrimary` `#EAF0FF` | **16.4:1** | ✅ (AAA) |
| `textSecondary` `#A4AECB` | **8.5:1** | ✅ |
| `textTertiary` `#8B96B1` | **6.3:1** | ✅ |
| `textFaint` `#77819E` | **4.83:1** | ✅ |
| `teal` (interactive) `#2FD4C2` | **10.1:1** | ✅ |
| risk **Low** `#35C28A` | **8.2:1** | ✅ |
| risk **Medium** `#F4B740` | **10.4:1** | ✅ |
| risk **High** `#F35B6B` | **5.8:1** | ✅ |
| risk **Uncertain** `#7C89A6` | **5.3:1** | ✅ |

**Fix applied:** `textFaint` was `#697391` (≈**4.0:1** — *below* AA for normal text).
It was raised to `#77819E` (**4.83:1**) so the faintest hint tier still passes AA;
every other tier already passed. The test pins each pair at its threshold, so a
future token regression fails CI.

## 2. Reduced-transparency fallback (translucent → solid)

Translucent, blurred surfaces (`BackdropFilter` glass over gradients) can drop
below contrast thresholds depending on what shows through. Flutter exposes no
dedicated "reduce transparency" flag, so we trigger on **`MediaQuery.highContrast`**
(iOS *Increase Contrast* / Android high-contrast). The `A11y` helpers implement the
fallback centrally:

- `A11y.glassFill(context)` → the translucent fill normally; an **opaque** solid
  (`shellRaised`) under high contrast, so contrast no longer depends on the
  backdrop.
- `A11y.stroke(context)` → a stronger, more visible border under high contrast.
- `A11y.blurSigma(context)` → **0** under high contrast (backdrop blur dropped).

**Applied to** the primary translucent surfaces: the dashboard `RiskCard` shell
(opaque neutral fill + the ambient glow dropped), the Risk Details glass cards
(opaque fill + stronger stroke), and the Profile glass panels (the flagship
`BackdropFilter` — blur dropped, fill opaque, border strengthened). The helper is
reusable; the remaining chrome `BackdropFilter` surfaces (auth, medication, bottom
nav) can adopt it mechanically as a follow-up — they are non-essential chrome and
already sit on dark backgrounds.

All fallbacks are **no-ops in the default (non-high-contrast) state**, so the
premium look is unchanged for most users; accessibility users get solid,
predictable surfaces.

## 3. Risk is never colour-only

Every risk/status signal pairs its colour with a **text label + a distinct icon
glyph** that survives greyscale — the single source of truth is
`RiskVisuals` (✓ Low / ! Medium / △ High / ? Uncertain) and `TrendBadge`
(↑ / → / ↓ / — with text). Confirmed on every surface that shows risk:

| Surface | Label + icon |
|---|---|
| Dashboard `RiskCard` (data / override) | ✅ headline + `RiskVisuals` icon |
| Risk Details hero + analytics | ✅ |
| National map `CityDetailSheet` + markers | ✅ label pill + distinct marker hue **and** icon |
| Comparison rows | ✅ icon + label + bar |
| Risk legend | ✅ labels every level |
| Trend badge | ✅ arrow/dash + word |
| Operator override notice/badge | ✅ "Operator-set" text + icon |
| Staleness notice | ✅ icon + text |

Enforced by `test/accessibility/colorblind_audit_test.dart` and
`test/accessibility/contrast_audit_test.dart` (icons mutually distinct; labels
non-empty; `RiskCard` asserts label **and** icon).

## 4. Reduced motion

All motion honours `MediaQuery.disableAnimations` via `AppMotion` (state/route
transitions, `PressableScale`, `AppReveal`, and the bespoke fades in
Offline/Details) — motion collapses to an instant, non-animated result, so **no
information is motion-dependent**. The contrast-audit test renders `RiskCard` with
`disableAnimations: true` and asserts the label + icon are fully present.

## 5. Verification

`flutter test test/accessibility/` — WCAG maths anchors (black/white/21:1),
per-pair contrast on the glass surface at AA thresholds, the reduced-transparency
fallback (opaque fill + zero blur + stronger stroke under high contrast), and risk
label-plus-icon under reduced motion. Green as part of the CI Flutter gate
(Prompt 14).

## 6. Known limitations / follow-ups

- Broader `BackdropFilter` chrome (auth, medication, bottom nav) can adopt the
  `A11y` fallback for full coverage — deferred as low-risk (dark backgrounds,
  non-essential chrome).
- Contrast is audited for the **dark** design-system-v2 surfaces (the app's shell);
  the light-theme legacy screens (Sprint 1/2) keep their own palette and were not
  re-audited here.
