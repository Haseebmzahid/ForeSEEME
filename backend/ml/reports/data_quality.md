# Data Quality Report — ForeSeeMe Risk Model

**Sprint 2, Prompt 6 — Cleaning & Missing-Value Strategy**

_Deterministic from the raw files. Modeling window 2022-08-05 → 2026-06-28._

## open_meteo_weather

| City | Variable | Days | Present | Missing | % Missing | Out-of-range | Interpolated | Coverage |
|------|----------|------|---------|---------|-----------|--------------|--------------|----------|
| Islamabad | temperature | 1424 | 1424 | 0 | 0.0% | 0 | 0 | 2022-08-05…2026-06-28 |
| Islamabad | humidity | 1424 | 1424 | 0 | 0.0% | 0 | 0 | 2022-08-05…2026-06-28 |
| Islamabad | precipitation | 1424 | 1424 | 0 | 0.0% | 0 | 0 | 2022-08-05…2026-06-28 |
| Rawalpindi | temperature | 1424 | 1424 | 0 | 0.0% | 0 | 0 | 2022-08-05…2026-06-28 |
| Rawalpindi | humidity | 1424 | 1424 | 0 | 0.0% | 0 | 0 | 2022-08-05…2026-06-28 |
| Rawalpindi | precipitation | 1424 | 1424 | 0 | 0.0% | 0 | 0 | 2022-08-05…2026-06-28 |
| Lahore | temperature | 1424 | 1424 | 0 | 0.0% | 0 | 0 | 2022-08-05…2026-06-28 |
| Lahore | humidity | 1424 | 1424 | 0 | 0.0% | 0 | 0 | 2022-08-05…2026-06-28 |
| Lahore | precipitation | 1424 | 1424 | 0 | 0.0% | 0 | 0 | 2022-08-05…2026-06-28 |
| Karachi | temperature | 1424 | 1424 | 0 | 0.0% | 0 | 0 | 2022-08-05…2026-06-28 |
| Karachi | humidity | 1424 | 1424 | 0 | 0.0% | 0 | 0 | 2022-08-05…2026-06-28 |
| Karachi | precipitation | 1424 | 1424 | 0 | 0.0% | 0 | 0 | 2022-08-05…2026-06-28 |
| Peshawar | temperature | 1424 | 1424 | 0 | 0.0% | 0 | 0 | 2022-08-05…2026-06-28 |
| Peshawar | humidity | 1424 | 1424 | 0 | 0.0% | 0 | 0 | 2022-08-05…2026-06-28 |
| Peshawar | precipitation | 1424 | 1424 | 0 | 0.0% | 0 | 0 | 2022-08-05…2026-06-28 |

## open_meteo_air_quality

| City | Variable | Days | Present | Missing | % Missing | Out-of-range | Interpolated | Coverage |
|------|----------|------|---------|---------|-----------|--------------|--------------|----------|
| Islamabad | pm2_5 | 1424 | 1424 | 0 | 0.0% | 0 | 0 | 2022-08-05…2026-06-28 |
| Islamabad | pm10 | 1424 | 1424 | 0 | 0.0% | 0 | 0 | 2022-08-05…2026-06-28 |
| Islamabad | us_aqi | 1424 | 1424 | 0 | 0.0% | 0 | 0 | 2022-08-05…2026-06-28 |
| Rawalpindi | pm2_5 | 1424 | 1424 | 0 | 0.0% | 0 | 0 | 2022-08-05…2026-06-28 |
| Rawalpindi | pm10 | 1424 | 1424 | 0 | 0.0% | 0 | 0 | 2022-08-05…2026-06-28 |
| Rawalpindi | us_aqi | 1424 | 1424 | 0 | 0.0% | 0 | 0 | 2022-08-05…2026-06-28 |
| Lahore | pm2_5 | 1424 | 1424 | 0 | 0.0% | 0 | 0 | 2022-08-05…2026-06-28 |
| Lahore | pm10 | 1424 | 1424 | 0 | 0.0% | 0 | 0 | 2022-08-05…2026-06-28 |
| Lahore | us_aqi | 1424 | 1424 | 0 | 0.0% | 0 | 0 | 2022-08-05…2026-06-28 |
| Karachi | pm2_5 | 1424 | 1424 | 0 | 0.0% | 0 | 0 | 2022-08-05…2026-06-28 |
| Karachi | pm10 | 1424 | 1424 | 0 | 0.0% | 0 | 0 | 2022-08-05…2026-06-28 |
| Karachi | us_aqi | 1424 | 1424 | 0 | 0.0% | 0 | 0 | 2022-08-05…2026-06-28 |
| Peshawar | pm2_5 | 1424 | 1424 | 0 | 0.0% | 0 | 0 | 2022-08-05…2026-06-28 |
| Peshawar | pm10 | 1424 | 1424 | 0 | 0.0% | 0 | 0 | 2022-08-05…2026-06-28 |
| Peshawar | us_aqi | 1424 | 1424 | 0 | 0.0% | 0 | 0 | 2022-08-05…2026-06-28 |

AQI availability (days with real or short-imputed data):

- Islamabad: 1424/1424 days `aqi_available=True`
- Rawalpindi: 1424/1424 days `aqi_available=True`
- Lahore: 1424/1424 days `aqi_available=True`
- Karachi: 1424/1424 days `aqi_available=True`
- Peshawar: 1424/1424 days `aqi_available=True`

## Missing-value policy (documented)

- **Short gaps** (≤ 3 consecutive days) are linearly interpolated and flagged per variable (`<var>_imputed`).
- **Longer gaps are never imputed** — they are left as NaN. The AQI pre-coverage period is retained as NaN with `aqi_available=False`; no values are invented across a multi-year absence.
- **Leading/trailing** NaNs are never extrapolated.
- **Physical ranges** (out-of-range dropped to NaN and counted above):
  - `temperature` ∈ [-90, 60]
  - `humidity` ∈ [0, 100]
  - `precipitation` ∈ [0, 1000]
  - `pm2_5` ∈ [0, 1000]
  - `pm10` ∈ [0, 2000]
  - `us_aqi` ∈ [0, 1000]
- **Hourly→daily aggregation**: `humidity`=mean, `pm2_5`=mean, `pm10`=mean, `us_aqi`=mean; temperature and precipitation are already daily.
