"""Feature engineering (Sprint 2, Prompt 8).

Derives temporal, lagged, and seasonal features from the weekly base table
(Prompt 7) so the learning problem is non-trivial and epidemiologically
meaningful — defusing the circularity trap (Shared Principle 1). Raw same-week
values alone make labels trivially invertible; lags, rolling means and seasonal
anomalies force the model to learn a function over time (disease responds to
environmental drivers weeks earlier — e.g. dengue to rainfall 2-4 weeks prior).

Every feature is **causal**: it uses only weeks ≤ t, and the climatology used by
the anomaly features is built from PRIOR YEARS ONLY. Nothing reads week t+1.

Feature families (all defined in ``config/pipeline.yaml``):

* **lags** — ``lag_k(var)[t] = var[t-k]`` for precipitation/temperature/humidity.
* **rolling** — trailing means over the N weeks strictly before t (t-1 … t-N).
* **anomaly** — ``value − climatology(city, week_of_year)`` (expanding prior-year
  climatology; leakage-free).
* **cyclical** — ``sin``/``cos`` of week-of-year (week 1 and 52 adjacent).
* **city one-hot** — fixed vocabulary from cities.yaml (serving-compatible).

Rows with insufficient history (and the first year, which has no climatology) are
flagged, not silently filled — see ``insufficient_lag_history`` / ``has_climatology``.

Outputs: ``data/interim/weekly_features.parquet`` and
``reports/feature_dictionary.md``.

Run (from ``backend/``)::

    python -m ml.pipelines.features
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd
import yaml

from ml.pipelines import paths

logger = logging.getLogger("foreseeme.ml.features")

KEY = ["city", "iso_year", "week_of_year"]


# --- Config ----------------------------------------------------------------


def _load_yaml(path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def load_feature_config(path=paths.PIPELINE_PATH) -> dict[str, Any]:
    return _load_yaml(path)["features"]


def load_city_vocab(path=paths.CITIES_PATH) -> list[str]:
    """Fixed, ordered city vocabulary for one-hot encoding (serving-compatible)."""
    return [c["name"] for c in _load_yaml(path)["cities"]]


# --- Ordering --------------------------------------------------------------


def _sorted(df: pd.DataFrame) -> pd.DataFrame:
    """Chronological order within each city (ISO year then week)."""
    return df.sort_values(KEY).reset_index(drop=True)


# --- Feature families ------------------------------------------------------


def add_lags(df: pd.DataFrame, variables: list[str], weeks: list[int]) -> list[str]:
    """Add ``<var>_lag<k>`` columns in place; return the new column names.

    ``shift(k)`` within each city moves values k rows (= k weeks, the index is
    contiguous weekly) into the future row, so row t sees only var[t-k] — past.
    """
    created: list[str] = []
    grouped = df.groupby("city", sort=False)
    for var in variables:
        for k in weeks:
            col = f"{var}_lag{k}"
            df[col] = grouped[var].shift(k)
            created.append(col)
    return created


def add_rollings(
    df: pd.DataFrame, variables: list[str], windows: list[int], shift: int
) -> list[str]:
    """Add ``<var>_roll<w>`` trailing means over the w weeks before t (shifted).

    With ``shift=1`` the window covers t-1 … t-w — strictly past, never the
    current week, never the future.
    """
    created: list[str] = []
    grouped = df.groupby("city", sort=False)
    for var in variables:
        for w in windows:
            col = f"{var}_roll{w}"
            df[col] = grouped[var].transform(
                lambda s, w=w: s.shift(shift).rolling(w, min_periods=w).mean()
            )
            created.append(col)
    return created


def climatology(df: pd.DataFrame, var: str, mode: str) -> pd.Series:
    """Per-(city, week_of_year) climatology of ``var``.

    ``expanding`` uses only prior years (leakage-free): for a given week, the
    mean of that week's value over strictly earlier years. ``global`` uses the
    full record (faster, but reads future years — only for explicit opt-in).
    Returned aligned to ``df``'s index.
    """
    if mode == "global":
        return df.groupby(["city", "week_of_year"])[var].transform("mean")

    # expanding (prior-years-only)
    work = df.sort_values(["city", "week_of_year", "iso_year"])
    clim = work.groupby(["city", "week_of_year"])[var].transform(
        lambda s: s.shift(1).expanding().mean()
    )
    return clim.reindex(df.index)


def add_anomalies(
    df: pd.DataFrame, variables: list[str], mode: str
) -> tuple[list[str], pd.Series]:
    """Add ``<var>_anom`` = value − climatology; return (cols, has_climatology)."""
    created: list[str] = []
    has_clim = pd.Series(True, index=df.index)
    for var in variables:
        clim = climatology(df, var, mode)
        col = f"{var}_anom"
        df[col] = df[var] - clim
        created.append(col)
        has_clim &= clim.notna()
    return created, has_clim


def add_cyclical(df: pd.DataFrame, period: float) -> list[str]:
    """Add ``week_sin`` / ``week_cos`` cyclical encoding of week-of-year."""
    angle = 2.0 * np.pi * df["week_of_year"].to_numpy() / period
    df["week_sin"] = np.sin(angle)
    df["week_cos"] = np.cos(angle)
    return ["week_sin", "week_cos"]


def add_city_onehot(df: pd.DataFrame, vocab: list[str]) -> list[str]:
    """Add fixed-vocabulary ``city_<name>`` one-hot columns (serving-compatible)."""
    created: list[str] = []
    for name in vocab:
        col = f"city_{name}"
        df[col] = (df["city"] == name).astype("int64")
        created.append(col)
    return created


# --- Orchestration ---------------------------------------------------------


def engineer_features(
    base: pd.DataFrame,
    config: dict[str, Any],
    city_vocab: list[str],
) -> tuple[pd.DataFrame, dict[str, list[str]]]:
    """Engineer all feature families on a weekly base table.

    Returns (feature_frame, family→columns map). Pure and deterministic; raw
    columns are carried through unchanged.
    """
    df = _sorted(base.copy())

    families: dict[str, list[str]] = {}
    families["lag"] = add_lags(
        df, config["lags"]["variables"], config["lags"]["weeks"]
    )
    families["rolling"] = add_rollings(
        df,
        config["rolling"]["variables"],
        config["rolling"]["windows"],
        int(config["rolling"].get("shift", 1)),
    )
    anom_cols, has_clim = add_anomalies(
        df, config["anomaly"]["variables"], config["anomaly"].get("mode", "expanding")
    )
    families["anomaly"] = anom_cols
    families["cyclical"] = add_cyclical(df, float(config["cyclical"]["period"]))
    families["city"] = add_city_onehot(df, city_vocab)

    # History flags.
    min_history = int(config.get("min_history_weeks", 5))
    weeks_elapsed = df.groupby("city", sort=False).cumcount()
    df["insufficient_lag_history"] = (weeks_elapsed < min_history).to_numpy()
    df["has_climatology"] = has_clim.to_numpy()
    families["flags"] = ["insufficient_lag_history", "has_climatology"]

    if config.get("drop_insufficient_history", False):
        df = df[~df["insufficient_lag_history"]].reset_index(drop=True)

    return df, families


# --- IO --------------------------------------------------------------------


def build_features(
    data_dir: Path | None = None,
    config: dict[str, Any] | None = None,
    city_vocab: list[str] | None = None,
) -> tuple[pd.DataFrame, dict[str, list[str]]]:
    """Load the weekly base table and engineer features."""
    data_dir = data_dir or paths.DATA_DIR
    config = config or load_feature_config()
    city_vocab = city_vocab or load_city_vocab()
    base = pd.read_parquet(data_dir / "interim" / "weekly_base.parquet")
    return engineer_features(base, config, city_vocab)


# --- Feature dictionary report ---------------------------------------------


def render_feature_dictionary(
    df: pd.DataFrame, families: dict[str, list[str]], config: dict[str, Any]
) -> str:
    """Render reports/feature_dictionary.md (rationale + leakage notes)."""
    lines: list[str] = []
    lines.append("# Feature Dictionary — ForeSeeMe Risk Model")
    lines.append("")
    lines.append("**Sprint 2, Prompt 8 — Feature Engineering**")
    lines.append("")
    lines.append(
        "All features are **causal**: they use only weeks ≤ t, and climatology "
        "uses prior years only — no lookahead into t+1. Definitions live in "
        "`config/pipeline.yaml`."
    )
    lines.append("")
    lines.append(f"- Rows: {len(df)}  |  Feature columns: "
                 f"{sum(len(v) for v in families.values())}")
    lines.append("")

    rationale = {
        "lag": (
            "Lagged drivers. Disease incidence responds to environmental "
            "conditions weeks earlier (dengue to rainfall 2-4 weeks prior as "
            "mosquito breeding develops; humidity/temperature to vector "
            "survival). `lag_k(var)[t] = var[t-k]` — strictly past."
        ),
        "rolling": (
            "Trailing means over the weeks strictly before t (t-1 … t-N). Smooths "
            "short-term noise and captures sustained conditions (e.g. a wet "
            "fortnight) without using the current or future week."
        ),
        "anomaly": (
            "Departure from the city's seasonal norm: `value − climatology(city, "
            "week_of_year)`. Captures *unusual* conditions for the time of year "
            "(an abnormally warm/wet/smoggy week) that drive outbreaks beyond the "
            "ordinary season. Climatology is expanding (prior years only)."
        ),
        "cyclical": (
            "`sin`/`cos` of week-of-year so the model sees seasonality smoothly "
            "and week 52 is adjacent to week 1 (no artificial year-boundary jump)."
        ),
        "city": (
            "Fixed-vocabulary one-hot city encoding. The serving pipeline builds "
            "the same `city_<name>` columns for a requested city, so training and "
            "serving agree."
        ),
        "flags": (
            "`insufficient_lag_history` marks the first weeks per city without "
            "full lag/rolling history; `has_climatology` is False for the first "
            "year per city (no prior-year climatology). Downstream may drop or "
            "impute; nothing is silently filled here."
        ),
    }

    for family, cols in families.items():
        lines.append(f"## {family}")
        lines.append("")
        lines.append(rationale.get(family, ""))
        lines.append("")
        # Per-column non-null counts (surfaces the history-driven NaNs).
        lines.append("| Column | Non-null | Null |")
        lines.append("|--------|----------|------|")
        for col in cols:
            nn = int(df[col].notna().sum())
            lines.append(f"| {col} | {nn} | {len(df) - nn} |")
        lines.append("")

    lines.append("## Leakage guarantees")
    lines.append("")
    lines.append("- Lags use `shift(k)` within a city → only var[t-k].")
    lines.append(
        f"- Rolling means are shifted by {config['rolling'].get('shift', 1)} week(s) "
        "and thus exclude the current and all future weeks."
    )
    lines.append(
        "- Climatology (`anomaly`) is expanding over prior years only, so a "
        "feature at week t never depends on any week > t. Verified by a unit test "
        "that perturbs a future row and checks past features are unchanged."
    )
    lines.append("")
    return "\n".join(lines)


def main() -> None:
    """Build features, write the parquet table and the feature dictionary."""
    from app.logging_config import configure_logging

    configure_logging("INFO")
    config = load_feature_config()
    df, families = build_features(config=config)

    out_path = paths.DATA_DIR / "interim" / "weekly_features.parquet"
    paths.ensure_dir(out_path.parent)
    df.to_parquet(out_path, index=False)

    paths.ensure_dir(paths.REPORTS_DIR)
    (paths.REPORTS_DIR / "feature_dictionary.md").write_text(
        render_feature_dictionary(df, families, config), encoding="utf-8"
    )

    n_features = sum(len(v) for v in families.values())
    logger.info("features_built", extra={"rows": len(df), "features": n_features})
    print(f"weekly_features rows={len(df)} feature_cols={n_features}")
    print(f"  insufficient_lag_history rows: {int(df['insufficient_lag_history'].sum())}")
    print(f"  has_climatology rows: {int(df['has_climatology'].sum())}/{len(df)}")
    print(f"table  -> {out_path}")
    print(f"report -> {paths.REPORTS_DIR / 'feature_dictionary.md'}")


if __name__ == "__main__":
    main()
