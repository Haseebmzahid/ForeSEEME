# Merge Summary — ForeSeeMe Weekly Base Table

**Sprint 2, Prompt 7 — Temporal Alignment & Merging**

Unlabelled, unengineered weekly base table keyed uniquely on `(city, iso_year, week_of_year)`. Daily sources aggregated to ISO weeks and outer-joined.

- **Total rows:** 1020
- **Unique keys:** 1020 (duplicates: 0)
- **Cities:** 5

## Rows & week span per city

| City | Weeks | First (iso_year-Www) | Last (iso_year-Www) | AQI-available weeks |
|------|-------|----------------------|---------------------|---------------------|
| Islamabad | 204 | 2022-W31 | 2026-W26 | 204 |
| Karachi | 204 | 2022-W31 | 2026-W26 | 204 |
| Lahore | 204 | 2022-W31 | 2026-W26 | 204 |
| Peshawar | 204 | 2022-W31 | 2026-W26 | 204 |
| Rawalpindi | 204 | 2022-W31 | 2026-W26 | 204 |

## Post-merge missingness (per column)

| Column | Missing | % Missing |
|--------|---------|-----------|
| city | 0 | 0.0% |
| iso_year | 0 | 0.0% |
| week_of_year | 0 | 0.0% |
| days_in_week | 0 | 0.0% |
| temperature | 0 | 0.0% |
| humidity | 0 | 0.0% |
| precipitation | 0 | 0.0% |
| pm2_5 | 0 | 0.0% |
| pm10 | 0 | 0.0% |
| us_aqi | 0 | 0.0% |
| aqi_available | 0 | 0.0% |

## Aggregation (documented)

- temperature → **mean**, humidity → **mean**, precipitation → **sum**
- pm2_5 / pm10 / us_aqi → **mean**
- aqi_available → carried forward (**any** day with AQI in the week)
- `days_in_week` records how many daily rows fed each weekly cell (< 7 at dataset boundaries / partial weeks).
