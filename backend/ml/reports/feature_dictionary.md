# Feature Dictionary — ForeSeeMe Risk Model

**Sprint 2, Prompt 8 — Feature Engineering**

All features are **causal**: they use only weeks ≤ t, and climatology uses prior years only — no lookahead into t+1. Definitions live in `config/pipeline.yaml`.

- Rows: 1020  |  Feature columns: 31

## lag

Lagged drivers. Disease incidence responds to environmental conditions weeks earlier (dengue to rainfall 2-4 weeks prior as mosquito breeding develops; humidity/temperature to vector survival). `lag_k(var)[t] = var[t-k]` — strictly past.

| Column | Non-null | Null |
|--------|----------|------|
| precipitation_lag1 | 1015 | 5 |
| precipitation_lag2 | 1010 | 10 |
| precipitation_lag3 | 1005 | 15 |
| precipitation_lag4 | 1000 | 20 |
| temperature_lag1 | 1015 | 5 |
| temperature_lag2 | 1010 | 10 |
| temperature_lag3 | 1005 | 15 |
| temperature_lag4 | 1000 | 20 |
| humidity_lag1 | 1015 | 5 |
| humidity_lag2 | 1010 | 10 |
| humidity_lag3 | 1005 | 15 |
| humidity_lag4 | 1000 | 20 |

## rolling

Trailing means over the weeks strictly before t (t-1 … t-N). Smooths short-term noise and captures sustained conditions (e.g. a wet fortnight) without using the current or future week.

| Column | Non-null | Null |
|--------|----------|------|
| precipitation_roll3 | 1005 | 15 |
| precipitation_roll4 | 1000 | 20 |
| temperature_roll3 | 1005 | 15 |
| temperature_roll4 | 1000 | 20 |
| humidity_roll3 | 1005 | 15 |
| humidity_roll4 | 1000 | 20 |

## anomaly

Departure from the city's seasonal norm: `value − climatology(city, week_of_year)`. Captures *unusual* conditions for the time of year (an abnormally warm/wet/smoggy week) that drive outbreaks beyond the ordinary season. Climatology is expanding (prior years only).

| Column | Non-null | Null |
|--------|----------|------|
| temperature_anom | 760 | 260 |
| humidity_anom | 760 | 260 |
| precipitation_anom | 760 | 260 |
| us_aqi_anom | 760 | 260 |

## cyclical

`sin`/`cos` of week-of-year so the model sees seasonality smoothly and week 52 is adjacent to week 1 (no artificial year-boundary jump).

| Column | Non-null | Null |
|--------|----------|------|
| week_sin | 1020 | 0 |
| week_cos | 1020 | 0 |

## city

Fixed-vocabulary one-hot city encoding. The serving pipeline builds the same `city_<name>` columns for a requested city, so training and serving agree.

| Column | Non-null | Null |
|--------|----------|------|
| city_Islamabad | 1020 | 0 |
| city_Rawalpindi | 1020 | 0 |
| city_Lahore | 1020 | 0 |
| city_Karachi | 1020 | 0 |
| city_Peshawar | 1020 | 0 |

## flags

`insufficient_lag_history` marks the first weeks per city without full lag/rolling history; `has_climatology` is False for the first year per city (no prior-year climatology). Downstream may drop or impute; nothing is silently filled here.

| Column | Non-null | Null |
|--------|----------|------|
| insufficient_lag_history | 1020 | 0 |
| has_climatology | 1020 | 0 |

## Leakage guarantees

- Lags use `shift(k)` within a city → only var[t-k].
- Rolling means are shifted by 1 week(s) and thus exclude the current and all future weeks.
- Climatology (`anomaly`) is expanding over prior years only, so a feature at week t never depends on any week > t. Verified by a unit test that perturbs a future row and checks past features are unchanged.
