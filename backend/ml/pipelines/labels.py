"""Environmental risk label generation (Sprint 2, Prompt 9).

Generates transparent, reproducible, literature-grounded **Low/Medium/High
environmental risk** labels for three disease families (dengue, smog/respiratory,
influenza), with a soft transition band so boundary cases are probabilistic and
genuinely learnable.

These labels encode an **environmental disease-risk suitability index — NOT
incidence** (the R1 reframe / circularity defence). For each disease, a weighted
sum of literature-grounded membership sub-scores (each in [0,1]) yields a
continuous risk score in [0,1], mapped to Low/Medium/High by two thresholds with
a ±band transition zone:

    u1 = clip((s − (θ_lm − δ)) / 2δ, 0, 1)     # ≥ Medium membership
    u2 = clip((s − (θ_mh − δ)) / 2δ, 0, 1)     # ≥ High membership
    P(Low) = 1 − u1,  P(Medium) = u1 − u2,  P(High) = u2

Within ±δ of a boundary these probabilities are non-degenerate. A hard label is
also stored, plus a *seeded, deterministic* sampled label (per-row hash of
seed+key, so identical seed → identical labels, independent of row order).

Every threshold, weight and band width lives in ``config/pipeline.yaml`` and is
cited/justified in ``reports/label_methodology.md``.

Outputs: ``data/interim/weekly_labelled.parquet`` and
``reports/label_methodology.md``.

Run (from ``backend/``)::

    python -m ml.pipelines.labels
"""

from __future__ import annotations

import datetime
import hashlib
import logging
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd
import yaml

from ml.pipelines import paths

logger = logging.getLogger("foreseeme.ml.labels")

KEY = ["city", "iso_year", "week_of_year"]
DISEASES = ["dengue", "smog", "influenza"]
CLASSES = ["Low", "Medium", "High"]


# --- Config ----------------------------------------------------------------


def _load_yaml(path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def load_label_config(path=paths.PIPELINE_PATH) -> dict[str, Any]:
    return _load_yaml(path)["labels"]


# --- Membership functions (each returns values in [0, 1]) ------------------


def ramp_up(x, lo: float, hi: float):
    """0 below ``lo``, linear to 1 at ``hi``."""
    return np.clip((np.asarray(x, float) - lo) / (hi - lo), 0.0, 1.0)


def ramp_down(x, hi: float, lo: float):
    """1 at/below ``lo``, linear down to 0 at ``hi`` (membership rises as x falls)."""
    return np.clip((hi - np.asarray(x, float)) / (hi - lo), 0.0, 1.0)


def trapezoid(x, t_min: float, t_opt_lo: float, t_opt_hi: float, t_max: float):
    """0 outside [t_min, t_max], 1 on the optimal plateau [t_opt_lo, t_opt_hi]."""
    x = np.asarray(x, float)
    left = (x - t_min) / (t_opt_lo - t_min)
    right = (t_max - x) / (t_max - t_opt_hi)
    return np.clip(np.minimum(left, right), 0.0, 1.0)


# --- Per-disease risk indices ----------------------------------------------


def dengue_score(df: pd.DataFrame, cfg: dict[str, Any]) -> np.ndarray:
    """Dengue environmental suitability: thermal band + humidity + lagged rain."""
    temp = trapezoid(df["temperature"], **cfg["temperature_band"])
    hum = ramp_up(df["humidity"], **cfg["humidity_ramp"])
    rl = cfg["rainfall_lag"]
    lag_cols = [f"precipitation_lag{w}" for w in rl["weeks"]]
    rain_value = df[lag_cols].mean(axis=1)
    rain = ramp_up(rain_value, 0.0, rl["cap_mm"])
    w = cfg["weights"]
    return w["temperature"] * temp + w["humidity"] * hum + w["rainfall_lag"] * rain


def smog_score(df: pd.DataFrame, cfg: dict[str, Any]) -> np.ndarray:
    """Smog/respiratory suitability: PM2.5 + smog season + low temp + low rain."""
    pm = ramp_up(df["pm2_5"], **cfg["pm25_ramp"])
    season = df["month"].isin(cfg["season_months"]).to_numpy(dtype=float)
    low_t = ramp_down(df["temperature"], **cfg["low_temperature_ramp"])
    low_r = ramp_down(df["precipitation"], hi=cfg["low_rainfall_ramp"]["wet"],
                      lo=cfg["low_rainfall_ramp"]["dry"])
    w = cfg["weights"]
    return (
        w["pm25"] * pm
        + w["season"] * season
        + w["low_temperature"] * low_t
        + w["low_rainfall"] * low_r
    )


def influenza_score(df: pd.DataFrame, cfg: dict[str, Any]) -> np.ndarray:
    """Influenza suitability: low temperature + low humidity + winter window."""
    low_t = ramp_down(df["temperature"], **cfg["low_temperature_ramp"])
    hb = cfg["low_humidity_band"]
    low_h = trapezoid(df["humidity"], hb["h_min"], hb["h_opt_lo"], hb["h_opt_hi"], hb["h_max"])
    season = df["month"].isin(cfg["season_months"]).to_numpy(dtype=float)
    w = cfg["weights"]
    return w["low_temperature"] * low_t + w["low_humidity"] * low_h + w["season"] * season


_SCORERS = {"dengue": dengue_score, "smog": smog_score, "influenza": influenza_score}


# --- Score → class mapping (soft transition band) --------------------------


def class_probabilities(
    score: np.ndarray, th_lm: float, th_mh: float, band: float
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Soft Low/Medium/High probabilities from a continuous score.

    Linear transition of width 2·band around each boundary. Returns (p_low,
    p_medium, p_high), each in [0,1], summing to 1 (NaN propagates for NaN
    scores).
    """
    s = np.asarray(score, float)
    u1 = np.clip((s - (th_lm - band)) / (2 * band), 0.0, 1.0)
    u2 = np.clip((s - (th_mh - band)) / (2 * band), 0.0, 1.0)
    return 1.0 - u1, u1 - u2, u2


def hard_label(score: np.ndarray, th_lm: float, th_mh: float) -> np.ndarray:
    """Hard Low/Medium/High by the two thresholds (NaN → None)."""
    s = np.asarray(score, float)
    out = np.where(s < th_lm, "Low", np.where(s < th_mh, "Medium", "High")).astype(object)
    out[np.isnan(s)] = None
    return out


def _hash_uniform(seed: int, key: str) -> float:
    """Deterministic uniform in [0,1) from (seed, key) — order-independent."""
    digest = hashlib.sha256(f"{seed}|{key}".encode("utf-8")).hexdigest()
    return int(digest, 16) / 2**256


def sampled_label(
    p_low: np.ndarray, p_med: np.ndarray, keys: list[str], seed: int
) -> np.ndarray:
    """Seeded categorical sample of the soft label (deterministic per key)."""
    out = np.empty(len(keys), dtype=object)
    for i, key in enumerate(keys):
        if np.isnan(p_low[i]):
            out[i] = None
            continue
        u = _hash_uniform(seed, key)
        if u < p_low[i]:
            out[i] = "Low"
        elif u < p_low[i] + p_med[i]:
            out[i] = "Medium"
        else:
            out[i] = "High"
    return out


# --- Build -----------------------------------------------------------------


def _iso_month(iso_year: int, week: int) -> int:
    """Calendar month of the ISO-week Thursday; week 53 in a 52-week year → week 52."""
    try:
        return datetime.date.fromisocalendar(iso_year, week, 4).month
    except ValueError:
        return datetime.date.fromisocalendar(iso_year, 52, 4).month


def _month_column(df: pd.DataFrame) -> np.ndarray:
    """Calendar month from (iso_year, week_of_year) using the ISO-week Thursday."""
    return np.array(
        [_iso_month(int(y), int(w)) for y, w in zip(df["iso_year"], df["week_of_year"])]
    )


def build_labels(
    features: pd.DataFrame, config: dict[str, Any]
) -> tuple[pd.DataFrame, dict[str, dict[str, dict[str, int]]]]:
    """Add per-disease label columns to the feature table; return (df, distribution).

    Per disease ``d`` adds: ``d_score``, ``d_prob_low/medium/high``, ``d_label``
    (hard), ``d_label_sampled`` (seeded). Distribution is per disease per
    label-kind (hard/sampled).
    """
    df = features.copy()
    df["month"] = _month_column(df)
    seed = int(config["seed"])
    band = float(config["transition_band"])

    distribution: dict[str, dict[str, dict[str, int]]] = {}
    for disease in DISEASES:
        dcfg = config["diseases"][disease]
        th_lm = float(dcfg["thresholds"]["low_medium"])
        th_mh = float(dcfg["thresholds"]["medium_high"])

        score = np.asarray(_SCORERS[disease](df, dcfg), dtype=float)
        p_low, p_med, p_high = class_probabilities(score, th_lm, th_mh, band)
        hard = hard_label(score, th_lm, th_mh)
        keys = [
            f"{c}|{y}|{w}|{disease}"
            for c, y, w in zip(df["city"], df["iso_year"], df["week_of_year"])
        ]
        sampled = sampled_label(p_low, p_med, keys, seed)

        df[f"{disease}_score"] = score
        df[f"{disease}_prob_low"] = p_low
        df[f"{disease}_prob_medium"] = p_med
        df[f"{disease}_prob_high"] = p_high
        df[f"{disease}_label"] = hard
        df[f"{disease}_label_sampled"] = sampled

        distribution[disease] = {
            "hard": _distribution(hard),
            "sampled": _distribution(sampled),
        }

    return df, distribution


def _distribution(labels: np.ndarray) -> dict[str, int]:
    series = pd.Series(labels)
    counts = series.value_counts(dropna=True)
    out = {cls: int(counts.get(cls, 0)) for cls in CLASSES}
    out["undefined"] = int(series.isna().sum())
    return out


def build_from_disk(
    data_dir: Path | None = None, config: dict[str, Any] | None = None
) -> tuple[pd.DataFrame, dict[str, Any]]:
    data_dir = data_dir or paths.DATA_DIR
    config = config or load_label_config()
    features = pd.read_parquet(data_dir / "interim" / "weekly_features.parquet")
    return build_labels(features, config)


# --- Methodology report ----------------------------------------------------

_CITATIONS = {
    "mordecai2017": "Mordecai EA, et al. (2017). Detecting the impact of temperature on transmission of Zika, dengue, and chikungunya using mechanistic models. PLoS Neglected Tropical Diseases 11(4):e0005568.",
    "naish2014": "Naish S, et al. (2014). Climate change and dengue: a critical and systematic review of quantitative modelling approaches. BMC Infectious Diseases 14:167.",
    "reiter2001": "Reiter P. (2001). Climate change and mosquito-borne disease. Environmental Health Perspectives 109(Suppl 1):141-161.",
    "whoaqg2021": "World Health Organization (2021). WHO Global Air Quality Guidelines: PM2.5 24-hour guideline level 15 µg/m³.",
    "epaaqi": "US EPA. Technical Assistance Document for the Reporting of Daily Air Quality — the Air Quality Index (AQI), PM2.5 breakpoints.",
    "lowen2007": "Lowen AC, Mubareka S, Steel J, Palese P. (2007). Influenza virus transmission is dependent on relative humidity and temperature. PLoS Pathogens 3(10):e151.",
    "shaman2009": "Shaman J, Kohn M. (2009). Absolute humidity modulates influenza survival, transmission, and seasonality. PNAS 106(9):3243-3248.",
    "prompt5ref": "ForeSeeMe disease seasonality reference (Prompt 5) — documented Oct-Jan Punjab smog season (validation-only).",
}


def render_methodology(
    config: dict[str, Any], distribution: dict[str, Any]
) -> str:
    L: list[str] = []
    L.append("# Environmental Risk Label Methodology — ForeSeeMe")
    L.append("")
    L.append("**Sprint 2, Prompt 9 — Environmental Risk Label Generation**")
    L.append("")
    L.append(
        "> **These labels encode ENVIRONMENTAL disease-risk SUITABILITY, not "
        "incidence.** They are a transparent, literature-grounded index of how "
        "favourable a city-week's environment is for each disease family — not a "
        "count or probability of actual cases."
    )
    L.append("")
    L.append(f"All numbers below come from `config/pipeline.yaml` "
             f"(`labels:`). Seed = {config['seed']}, transition band δ = "
             f"{config['transition_band']}.")
    L.append("")

    L.append("## Method")
    L.append("")
    L.append(
        "For each disease, each determinant maps a variable to a membership "
        "sub-score in [0,1] (`ramp_up`, `ramp_down`, or `trapezoid`). The "
        "weighted sum (weights sum to 1) gives a continuous risk score in [0,1]. "
        "Two thresholds (θ_lm, θ_mh) map the score to Low/Medium/High, with a "
        "soft transition of width 2δ around each boundary producing class "
        "probabilities:"
    )
    L.append("")
    L.append("```")
    L.append("u1 = clip((s − (θ_lm − δ)) / 2δ, 0, 1)   # ≥ Medium")
    L.append("u2 = clip((s − (θ_mh − δ)) / 2δ, 0, 1)   # ≥ High")
    L.append("P(Low)=1−u1   P(Medium)=u1−u2   P(High)=u2")
    L.append("```")
    L.append("")
    L.append(
        "The stored `*_label_sampled` draws from these probabilities via a "
        "deterministic per-row hash of (seed, city, year, week, disease) — so a "
        "fixed seed reproduces identical labels regardless of row order. "
        "Determinant parameters are **cited to literature**; the index weights "
        "and Low/Med/High cutoffs are **documented design choices** calibrated "
        "for a non-degenerate, learnable distribution."
    )
    L.append("")

    determinants = {
        "dengue": [
            ("temperature", "trapezoid", "temperature_band",
             "Thermal suitability: optimum ~29°C, transmission ~18-34°C.", "mordecai2017"),
            ("humidity", "ramp_up", "humidity_ramp",
             "Higher humidity aids vector survival.", "naish2014"),
            ("rainfall_lag", "ramp_up", "rainfall_lag",
             "Rainfall 2-4 weeks prior creates breeding sites (lagged).", "reiter2001"),
        ],
        "smog": [
            ("pm25", "ramp_up", "pm25_ramp",
             "PM2.5 above the WHO 24-h guideline (15 µg/m³) up to US-AQI 'unhealthy'.",
             "whoaqg2021"),
            ("season", "indicator", "season_months",
             "Documented Oct-Jan Punjab smog season.", "prompt5ref"),
            ("low_temperature", "ramp_down", "low_temperature_ramp",
             "Cold and inversions trap particulates.", "epaaqi"),
            ("low_rainfall", "ramp_down", "low_rainfall_ramp",
             "Less rain → less washout of particulates.", "epaaqi"),
        ],
        "influenza": [
            ("low_temperature", "ramp_down", "low_temperature_ramp",
             "Transmission peaks at low temperature (~5°C).", "lowen2007"),
            ("low_humidity", "trapezoid", "low_humidity_band",
             "Transmission peaks at low relative humidity (~20-35%).", "lowen2007"),
            ("season", "indicator", "season_months",
             "Winter window; absolute-humidity seasonality.", "shaman2009"),
        ],
    }

    for disease in DISEASES:
        dcfg = config["diseases"][disease]
        L.append(f"## {disease.capitalize()}")
        L.append("")
        L.append(f"- Weights: {dcfg['weights']}")
        L.append(f"- Thresholds: Low/Med = {dcfg['thresholds']['low_medium']}, "
                 f"Med/High = {dcfg['thresholds']['medium_high']}")
        L.append("")
        L.append("| Determinant | Shape | Parameters | Rationale | Citation |")
        L.append("|-------------|-------|------------|-----------|----------|")
        for name, shape, param_key, rationale, cite in determinants[disease]:
            params = dcfg.get(param_key)
            L.append(f"| {name} | {shape} | `{params}` | {rationale} | "
                     f"{cite} |")
        L.append("")
        dist = distribution[disease]
        L.append(f"- **Class distribution (sampled):** {dist['sampled']}")
        L.append(f"- **Class distribution (hard):** {dist['hard']}")
        L.append("")

    L.append("## Citations")
    L.append("")
    for key, text in _CITATIONS.items():
        L.append(f"- **{key}** — {text}")
    L.append("")

    L.append("## Limitations (state plainly)")
    L.append("")
    L.append("- **Environmental risk, not incidence.** This is a suitability "
             "index; it does not predict case counts and is not clinically "
             "validated.")
    L.append("- The composite weighting and Low/Med/High cutoffs are transparent "
             "**design choices**, not derived constants; an examiner can and "
             "should challenge them.")
    L.append("- Only environmental determinants are used — no human immunity, "
             "mobility, vaccination, vector control, or reporting effects.")
    L.append("- Membership breakpoints are reasoned approximations grounded in "
             "the cited sources, not exact reproductions of any single study.")
    L.append("- The data window is short (2022-08 onward); climatological "
             "context is limited.")
    L.append("- The disease seasonality reference (Prompt 5) is used only to "
             "**validate** plausibility later (Prompt 12) — never as a training "
             "label here.")
    L.append("")
    return "\n".join(L)


def main() -> None:
    from app.logging_config import configure_logging

    configure_logging("INFO")
    config = load_label_config()
    df, distribution = build_from_disk(config=config)

    out_path = paths.DATA_DIR / "interim" / "weekly_labelled.parquet"
    paths.ensure_dir(out_path.parent)
    df.to_parquet(out_path, index=False)

    paths.ensure_dir(paths.REPORTS_DIR)
    (paths.REPORTS_DIR / "label_methodology.md").write_text(
        render_methodology(config, distribution), encoding="utf-8"
    )

    logger.info("labels_built", extra={"rows": len(df), "distribution": distribution})
    for disease in DISEASES:
        print(f"{disease:10} sampled={distribution[disease]['sampled']}")
    print(f"table  -> {out_path}")
    print(f"report -> {paths.REPORTS_DIR / 'label_methodology.md'}")


if __name__ == "__main__":
    main()
