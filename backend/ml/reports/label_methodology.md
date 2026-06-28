# Environmental Risk Label Methodology — ForeSeeMe

**Sprint 2, Prompt 9 — Environmental Risk Label Generation**

> **These labels encode ENVIRONMENTAL disease-risk SUITABILITY, not incidence.** They are a transparent, literature-grounded index of how favourable a city-week's environment is for each disease family — not a count or probability of actual cases.

All numbers below come from `config/pipeline.yaml` (`labels:`). Seed = 1729, transition band δ = 0.06.

## Method

For each disease, each determinant maps a variable to a membership sub-score in [0,1] (`ramp_up`, `ramp_down`, or `trapezoid`). The weighted sum (weights sum to 1) gives a continuous risk score in [0,1]. Two thresholds (θ_lm, θ_mh) map the score to Low/Medium/High, with a soft transition of width 2δ around each boundary producing class probabilities:

```
u1 = clip((s − (θ_lm − δ)) / 2δ, 0, 1)   # ≥ Medium
u2 = clip((s − (θ_mh − δ)) / 2δ, 0, 1)   # ≥ High
P(Low)=1−u1   P(Medium)=u1−u2   P(High)=u2
```

The stored `*_label_sampled` draws from these probabilities via a deterministic per-row hash of (seed, city, year, week, disease) — so a fixed seed reproduces identical labels regardless of row order. Determinant parameters are **cited to literature**; the index weights and Low/Med/High cutoffs are **documented design choices** calibrated for a non-degenerate, learnable distribution.

## Dengue

- Weights: {'temperature': 0.4, 'humidity': 0.25, 'rainfall_lag': 0.35}
- Thresholds: Low/Med = 0.33, Med/High = 0.55

| Determinant | Shape | Parameters | Rationale | Citation |
|-------------|-------|------------|-----------|----------|
| temperature | trapezoid | `{'t_min': 18.0, 't_opt_lo': 26.0, 't_opt_hi': 30.0, 't_max': 34.0}` | Thermal suitability: optimum ~29°C, transmission ~18-34°C. | mordecai2017 |
| humidity | ramp_up | `{'lo': 40.0, 'hi': 75.0}` | Higher humidity aids vector survival. | naish2014 |
| rainfall_lag | ramp_up | `{'weeks': [2, 3, 4], 'cap_mm': 35.0}` | Rainfall 2-4 weeks prior creates breeding sites (lagged). | reiter2001 |

- **Class distribution (sampled):** {'Low': 377, 'Medium': 249, 'High': 384, 'undefined': 10}
- **Class distribution (hard):** {'Low': 389, 'Medium': 239, 'High': 382, 'undefined': 10}

## Smog

- Weights: {'pm25': 0.45, 'season': 0.2, 'low_temperature': 0.2, 'low_rainfall': 0.15}
- Thresholds: Low/Med = 0.35, Med/High = 0.58

| Determinant | Shape | Parameters | Rationale | Citation |
|-------------|-------|------------|-----------|----------|
| pm25 | ramp_up | `{'lo': 15.0, 'hi': 150.0}` | PM2.5 above the WHO 24-h guideline (15 µg/m³) up to US-AQI 'unhealthy'. | whoaqg2021 |
| season | indicator | `[10, 11, 12, 1]` | Documented Oct-Jan Punjab smog season. | prompt5ref |
| low_temperature | ramp_down | `{'hi': 22.0, 'lo': 8.0}` | Cold and inversions trap particulates. | epaaqi |
| low_rainfall | ramp_down | `{'wet': 15.0, 'dry': 0.0}` | Less rain → less washout of particulates. | epaaqi |

- **Class distribution (sampled):** {'Low': 678, 'Medium': 221, 'High': 121, 'undefined': 0}
- **Class distribution (hard):** {'Low': 676, 'Medium': 222, 'High': 122, 'undefined': 0}

## Influenza

- Weights: {'low_temperature': 0.4, 'low_humidity': 0.3, 'season': 0.3}
- Thresholds: Low/Med = 0.2, Med/High = 0.45

| Determinant | Shape | Parameters | Rationale | Citation |
|-------------|-------|------------|-----------|----------|
| low_temperature | ramp_down | `{'hi': 18.0, 'lo': 2.0}` | Transmission peaks at low temperature (~5°C). | lowen2007 |
| low_humidity | trapezoid | `{'h_min': 10.0, 'h_opt_lo': 20.0, 'h_opt_hi': 35.0, 'h_max': 60.0}` | Transmission peaks at low relative humidity (~20-35%). | lowen2007 |
| season | indicator | `[12, 1, 2]` | Winter window; absolute-humidity seasonality. | shaman2009 |

- **Class distribution (sampled):** {'Low': 650, 'Medium': 218, 'High': 152, 'undefined': 0}
- **Class distribution (hard):** {'Low': 647, 'Medium': 225, 'High': 148, 'undefined': 0}

## Citations

- **mordecai2017** — Mordecai EA, et al. (2017). Detecting the impact of temperature on transmission of Zika, dengue, and chikungunya using mechanistic models. PLoS Neglected Tropical Diseases 11(4):e0005568.
- **naish2014** — Naish S, et al. (2014). Climate change and dengue: a critical and systematic review of quantitative modelling approaches. BMC Infectious Diseases 14:167.
- **reiter2001** — Reiter P. (2001). Climate change and mosquito-borne disease. Environmental Health Perspectives 109(Suppl 1):141-161.
- **whoaqg2021** — World Health Organization (2021). WHO Global Air Quality Guidelines: PM2.5 24-hour guideline level 15 µg/m³.
- **epaaqi** — US EPA. Technical Assistance Document for the Reporting of Daily Air Quality — the Air Quality Index (AQI), PM2.5 breakpoints.
- **lowen2007** — Lowen AC, Mubareka S, Steel J, Palese P. (2007). Influenza virus transmission is dependent on relative humidity and temperature. PLoS Pathogens 3(10):e151.
- **shaman2009** — Shaman J, Kohn M. (2009). Absolute humidity modulates influenza survival, transmission, and seasonality. PNAS 106(9):3243-3248.
- **prompt5ref** — ForeSeeMe disease seasonality reference (Prompt 5) — documented Oct-Jan Punjab smog season (validation-only).

## Limitations (state plainly)

- **Environmental risk, not incidence.** This is a suitability index; it does not predict case counts and is not clinically validated.
- The composite weighting and Low/Med/High cutoffs are transparent **design choices**, not derived constants; an examiner can and should challenge them.
- Only environmental determinants are used — no human immunity, mobility, vaccination, vector control, or reporting effects.
- Membership breakpoints are reasoned approximations grounded in the cited sources, not exact reproductions of any single study.
- The data window is short (2022-08 onward); climatological context is limited.
- The disease seasonality reference (Prompt 5) is used only to **validate** plausibility later (Prompt 12) — never as a training label here.
