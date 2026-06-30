# Sprint 3 — Accessibility Audit (colorblind-safe risk encoding)

**Principle:** risk is *never conveyed by colour alone*. Every risk/status signal
pairs colour with a **text label** and a **distinct icon/glyph** that survives
greyscale — a hard requirement for a health app.

Items marked ✅ are **codified as tests** (`test/accessibility/colorblind_audit_test.dart`
and the per-widget tests), so regressions fail CI.

## Risk indicators

| Indicator | Colour | Non-colour cue (label + glyph) | Status |
|---|---|---|---|
| Risk level — Low | `#35C28A` | "Low" + ✓ `check_circle_outline` | ✅ |
| Risk level — Medium | `#F4B740` | "Medium" + ! `priority_high` | ✅ |
| Risk level — High | `#F35B6B` | "High" + △ `warning_amber` | ✅ |
| Risk level — Uncertain (low-confidence) | `#7C89A6` | "Uncertain" + ? `help_outline` | ✅ |
| Trend — Rising | `#F35B6B` | "Rising" + ↗ `trending_up` | ✅ |
| Trend — Stable | `#F4B740` | "Stable" + → `trending_flat` | ✅ |
| Trend — Falling | `#35C28A` | "Falling" + ↘ `trending_down` | ✅ |
| Trend — Insufficient | `#7C89A6` | "Insufficient data" + "—" dash (no arrow) | ✅ |
| Staleness hint | `#F4B740` | "This estimate may be out of date" + clock-off icon | ✅ |
| National map zones | per level | colored circle **+ marker + label**; legend pairs each level colour with its icon + name | ✅ (legend tested; map render is manual/device) |
| Map detail sheet | per level | level label + icon pill | ✅ |
| Low-confidence treatment | grey | replaces level with "Uncertain" + ? (never a misleading coloured level) | ✅ |

Distinctness is asserted: the four risk icons are mutually distinct, the four
colours are distinct, and trend "insufficient" never renders a directional arrow.

## Other accessibility checks (manual, on device)

- [ ] **Contrast** — body/label text on glass meets WCAG AA (≥ 4.5:1). Glass sits
      over the fixed dark shell, so contrast does not collapse on bright content.
- [ ] **Touch targets** — interactive elements ≥ 44×44 (nav, chips, toggles,
      Call/Directions, Retry).
- [ ] **Screen reader** — RiskCard exposes a `Semantics` summary
      ("{city} risk: {level}, {disease}, {n} percent confidence"); TrendBadge,
      EmergencyCard and toggles have labels. Sweep with TalkBack.
- [ ] **Reduced motion** — verify ambient/shimmer animations are not essential to
      meaning (all state is also conveyed by text/icons).
- [ ] **Greyscale sweep** — enable a colorblind simulation / grayscale and confirm
      every indicator above is still unambiguous.

**Sign-off:** the colour-independence of every risk indicator is verified by
automated tests; the manual checks above are the device pass during the Sprint 3
exit review.
