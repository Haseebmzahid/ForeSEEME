# Recommendation Rules — cited mapping (Sprint 4)

**Deterministic lookup, never generation (Rule 11).** Each advisory is a fixed,
**cited** entry drawn from the same verified authorities as the Sprint 3 Resource
Center. The engine and the dashboard recommendation card select an entry by
`(category, driver)` — they never compose free-text medical advice. Every entry
carries a `source` + `sourceUrl`, an escalation line, and a safe default exists
for "no match".

This table is the single source of truth for both:
- the `recommendation` embedded in alert payloads / `userAlerts` (P2), and
- the dashboard recommendations card (P6).

## Sources (verified, reused from Sprint 3)

| Key | Authority | URL |
|---|---|---|
| WHO-AIR | World Health Organization — Air pollution | https://www.who.int/health-topics/air-pollution |
| CDC-ASTHMA | U.S. CDC — Asthma | https://www.cdc.gov/asthma/ |
| EPA-AQI | U.S. EPA — AirNow AQI basics | https://www.airnow.gov/aqi/aqi-basics/ |
| WHO-HEAT | World Health Organization — Heatwaves | https://www.who.int/health-topics/heatwaves |
| CDC-HEAT | U.S. CDC — Extreme heat (chronic conditions, incl. diabetes/heart) | https://www.cdc.gov/disasters/extremeheat/ |

## Mapping (`category` × `driver` → cited advisory)

Selection key: `(category, driver)`. `driver` is derived from the estimate's
`disease` per `alert_dispatch_design.md` §5 (`Air quality`, `Heat`, `Respiratory`).

| id | category | driver | Advisory text (cited, conservative) | Source | Deep link | Escalation |
|---|---|---|---|---|---|---|
| `rec-resp-air` | respiratory | Air quality | Limit prolonged or heavy outdoor exertion; keep windows closed during peak smog; a well-fitted N95/FFP2 mask reduces fine-particle exposure; run a HEPA purifier indoors. | WHO-AIR / CDC-ASTHMA | `/resources` | If breathing worsens (frequent wheeze/breathlessness), seek medical care; emergency → Rescue 1122. |
| `rec-resp-seasonal` | respiratory | Respiratory | Keep your reliever inhaler with you and follow your asthma action plan; avoid crowded indoor spaces during peak respiratory season. | CDC-ASTHMA | `/resources` | Seek care promptly if symptoms escalate; emergency → Rescue 1122. |
| `rec-cardio-air` | cardiovascular | Air quality | On high-AQI days, reduce strenuous outdoor activity; sensitive groups (heart/lung conditions) should limit prolonged exertion and keep medications on hand. | EPA-AQI | `/resources` | Chest discomfort/shortness of breath → seek urgent care; emergency → Rescue 1122. |
| `rec-cardio-heat` | cardiovascular | Heat | Drink water regularly, avoid the hottest hours, and keep cool. People with heart disease, hypertension or diabetes tolerate heat less well — watch for dizziness, headache or nausea. | WHO-HEAT / CDC-HEAT | `/nearby-hospitals` | Heat exhaustion not improving, or chest pain/confusion → seek help immediately; emergency → Rescue 1122. |
| `rec-default` | * | * | Check your local Air Quality Index and follow official guidance for your area. This is general information, not personal medical advice. | EPA-AQI | `/resources` | For personal guidance consult a healthcare professional; emergency → Rescue 1122. |

### Selection rules

1. Look up the exact `(category, driver)` row.
2. If none matches, use `rec-default` (always sourced, never empty).
3. The advisory is attached verbatim with its `source`/`sourceUrl`; the engine
   adds no other medical text.
4. Every advisory routes to a verified resource or to professional/emergency help
   — it never improvises treatment.

### Integrity guarantees (enforced by tests in P6)

- Every entry has a non-empty `source` and an `https://` `sourceUrl`.
- Lookup is total: any `(category, driver)` resolves to a row (via `rec-default`).
- No entry contains dosing, diagnosis, or generated claims.
