# ForeSeeMe — Submission Screenshots Checklist (Sprint 5, Prompt 17)

*The report needs real screenshots from the running app. These cannot be fabricated —
capture them live on a device/emulator with the demo user (asthma profile, respiratory
alerts enabled, a modelled city such as Lahore). Design references for each screen live in
`docs/ui sprint 3/`; the captures below must be the **actual app**, not the mockups.*

Save captures to `docs/screenshots/` (create it) with the suggested filenames.

## Core narrative (must-have)

| # | Screen / state | What must be visible | Filename | Design ref |
|---|---|---|---|---|
| 1 | Home dashboard | Live risk card with level + icon + label (not colour-only) | `01_dashboard.png` | `Home Dashboard.png` |
| 2 | Risk Details — hero | Level headline, confidence badge, "Updated …" recency | `02_risk_details_hero.png` | `Risk details.png` |
| 3 | **Why this estimate?** panel | Real drivers with direction arrows + measured values | `03_explanation_panel.png` | — (Sprint 5) |
| 4 | **Confidence explanation** | Strength chip + plain-language rationale | `04_confidence.png` | — (Sprint 5) |
| 5 | Model Transparency page | Provenance + "not clinical/outbreak" statement | `05_transparency.png` | — (Sprint 5) |
| 6 | Push notification (lock screen / tray) | The proactive alert arriving un-opened | `06_push_notification.png` | — |
| 7 | Alert inbox | Delivered alert + unread badge; cited source line | `07_alert_inbox.png` | `Notification Preferences.png` (adjacent) |
| 8 | Non-diagnostic disclaimer | Persistent banner on a risk surface | `08_disclaimer.png` | — |

## Unhappy paths & safety (strongly recommended)

| # | Screen / state | What must be visible | Filename | Design ref |
|---|---|---|---|---|
| 9 | Staleness label | "This estimate may be out of date" beside headline | `09_stale.png` | — |
| 10 | Offline state | Cached data + offline indicator | `10_offline.png` | `Offline States .png` |
| 11 | Empty state | Honest no-data screen | `11_empty.png` | `Empty State.png` |
| 12 | Loading / skeleton | Shimmer skeletons | `12_loading.png` | `Loading State.png` |
| 13 | Emergency affordance (High risk) | One-tap emergency dial card | `13_emergency.png` | — |
| 14 | Operator override banner | Labelled override above model detail | `14_override.png` | — (Sprint 5) |

## Feature breadth (optional)

| # | Screen | Filename | Design ref |
|---|---|---|---|
| 15 | City & disease comparison | `15_comparison.png` | — (Sprint 5) |
| 16 | Weekly health report | `16_weekly_report.png` | — (Sprint 5) |
| 17 | National risk map | `17_risk_map.png` | `National Risk MAP.png` |
| 18 | Nearby hospitals | `18_hospitals.png` | `Nearby Hospitals .png` |
| 19 | Resource center | `19_resources.png` | `Resource center.png` |
| 20 | Notification preferences | `20_preferences.png` | `Notification Preferences.png` |

## Capture tips

- Use a consistent device frame and light/dark mode across shots.
- For the accessibility story, capture one screen with **reduced transparency** enabled to
  show the solid-surface fallback (`docs/accessibility_audit.md`).
- For shots 1–4, seed a **High** smog estimate for the city so the explanation panel is
  populated with real drivers.
- Do **not** edit numbers into screenshots — capture whatever the real pipeline produced.
