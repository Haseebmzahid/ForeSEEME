"""Temporal alignment & dataset merging (Sprint 2, Prompt 7).

Aligns the cleaned daily per-source interim tables (Prompt 6) to a common
``(city, iso_year, week_of_year)`` grid and outer-joins them into a single
**unlabelled, unengineered** weekly base table.

Weekly aggregation (per city / ISO week):

* temperature  -> mean
* humidity     -> mean
* precipitation (rainfall) -> sum
* pm2_5 / pm10 / us_aqi     -> mean
* aqi_available -> carried forward (True if any day in the week had AQI data)

Sources are joined with an **outer** join on the key, so weeks where AQI is
missing are preserved as NaN with ``aqi_available = False`` — never dropped by an
inner join. No feature engineering and no labels happen here.

Outputs: ``data/interim/weekly_base.parquet`` and ``reports/merge_summary.md``.

Pipeline stages (M5.3, see ``PREPROCESSING.md``): this module owns Merge
Preparation (:func:`with_iso_week`, :func:`aggregate_weekly_weather`,
:func:`aggregate_weekly_aqi`) and Merge proper (:func:`merge_sources`).
:func:`load_source_daily` already carries this module's Validation
responsibility — a clear precondition error if the expected interim files are
absent — unchanged here, just named.

Module 5 / Module 6 handoff: ``data/interim/weekly_base.parquet``, with
exactly the columns in :data:`COLUMNS`, is the entire contract Module 6's
``features.py`` reads. This module has no knowledge of feature engineering,
labels, training, or FastAPI, and must stay that way.

Run (from ``backend/``)::

    python -m ml.pipelines.merge
"""

from __future__ import annotations

import logging
from pathlib import Path

import numpy as np
import pandas as pd

from ml.pipelines import paths
from ml.pipelines.quality_report import from_merge, new_report

logger = logging.getLogger("foreseeme.ml.merge")

KEY = ["city", "iso_year", "week_of_year"]

#: Final column order of the weekly base table.
COLUMNS = [
    "city",
    "iso_year",
    "week_of_year",
    "days_in_week",
    "temperature",
    "humidity",
    "precipitation",
    "pm2_5",
    "pm10",
    "us_aqi",
    "aqi_available",
]


# --- Keying ----------------------------------------------------------------


def with_iso_week(daily: pd.DataFrame) -> pd.DataFrame:
    """Add ``iso_year`` / ``week_of_year`` columns from the daily ``date``.

    Merge Preparation stage: temporal key derivation (see ``PREPROCESSING.md``).
    """
    iso = daily["date"].dt.isocalendar()
    return daily.assign(
        iso_year=iso["year"].astype("int64"),
        week_of_year=iso["week"].astype("int64"),
    )


# --- Weekly aggregation ----------------------------------------------------


def aggregate_weekly_weather(daily: pd.DataFrame) -> pd.DataFrame:
    """Aggregate daily weather to weekly: temp/humidity mean, rainfall sum.

    Merge Preparation stage (see ``PREPROCESSING.md``).
    """
    df = with_iso_week(daily)
    grouped = df.groupby(KEY, sort=True)
    weekly = grouped.agg(
        days_in_week=("temperature", "size"),
        temperature=("temperature", "mean"),
        humidity=("humidity", "mean"),
        # Rainfall is a SUM (not a mean); partial weeks sum the available days,
        # NaN only if the whole week is missing.
        precipitation=("precipitation", lambda s: s.sum(min_count=1)),
    ).reset_index()
    return weekly


def aggregate_weekly_aqi(daily: pd.DataFrame) -> pd.DataFrame:
    """Aggregate daily AQI to weekly means; carry the availability flag forward.

    Merge Preparation stage (see ``PREPROCESSING.md``).
    """
    df = with_iso_week(daily)
    grouped = df.groupby(KEY, sort=True)
    weekly = grouped.agg(
        pm2_5=("pm2_5", "mean"),
        pm10=("pm10", "mean"),
        us_aqi=("us_aqi", "mean"),
        aqi_available=("aqi_available", "any"),
    ).reset_index()
    return weekly


# --- Merge -----------------------------------------------------------------


def merge_sources(
    weather_weekly: pd.DataFrame, aqi_weekly: pd.DataFrame
) -> pd.DataFrame:
    """Outer-join weekly sources on the key into the weekly base table.

    Outer join: a week present in either source survives. AQI-missing weeks keep
    NaN AQI columns and ``aqi_available = False`` (never dropped).

    Merge stage proper (see ``PREPROCESSING.md``).
    """
    base = weather_weekly.merge(aqi_weekly, on=KEY, how="outer")
    # Weeks absent from AQI come through as NaN; treat as not-available. Use numpy
    # to avoid pandas' object-dtype fillna downcast deprecation.
    avail = base["aqi_available"]
    base["aqi_available"] = np.where(avail.isna(), False, avail).astype(bool)
    base = base.reindex(columns=COLUMNS)
    base = base.sort_values(KEY).reset_index(drop=True)
    return base


# --- IO --------------------------------------------------------------------


def load_source_daily(data_dir: Path, subdir: str) -> pd.DataFrame:
    """Concatenate all cleaned per-city daily parquet files for one source.

    Validation stage: fails clearly (not with a silent empty frame) if the
    expected interim files are absent — see ``PREPROCESSING.md``.
    """
    source_dir = data_dir / "interim" / subdir
    frames = [pd.read_parquet(p) for p in sorted(source_dir.glob("*.parquet"))]
    if not frames:
        raise FileNotFoundError(f"no interim parquet files under {source_dir}")
    return pd.concat(frames, ignore_index=True)


def merge_all(data_dir: Path | None = None) -> pd.DataFrame:
    """Build the weekly base table from the cleaned interim tables on disk."""
    data_dir = data_dir or paths.DATA_DIR
    weather_weekly = aggregate_weekly_weather(load_source_daily(data_dir, "weather"))
    aqi_weekly = aggregate_weekly_aqi(load_source_daily(data_dir, "aqi"))
    return merge_sources(weather_weekly, aqi_weekly)


# --- Summary report --------------------------------------------------------


def column_missingness(base: pd.DataFrame) -> dict[str, tuple[int, float]]:
    """Per-column (n_missing, pct_missing) over the merged table."""
    total = len(base)
    out: dict[str, tuple[int, float]] = {}
    for col in base.columns:
        n_missing = int(base[col].isna().sum())
        out[col] = (n_missing, (n_missing / total * 100.0) if total else 0.0)
    return out


def render_summary(base: pd.DataFrame) -> str:
    """Render reports/merge_summary.md from the merged table (deterministic)."""
    lines: list[str] = []
    lines.append("# Merge Summary — ForeSeeMe Weekly Base Table")
    lines.append("")
    lines.append("**Sprint 2, Prompt 7 — Temporal Alignment & Merging**")
    lines.append("")
    lines.append(
        "Unlabelled, unengineered weekly base table keyed uniquely on "
        "`(city, iso_year, week_of_year)`. Daily sources aggregated to ISO weeks "
        "and outer-joined."
    )
    lines.append("")
    lines.append(f"- **Total rows:** {len(base)}")
    lines.append(f"- **Unique keys:** {base[KEY].drop_duplicates().shape[0]} "
                 f"(duplicates: {len(base) - base[KEY].drop_duplicates().shape[0]})")
    lines.append(f"- **Cities:** {base['city'].nunique()}")
    lines.append("")

    lines.append("## Rows & week span per city")
    lines.append("")
    lines.append("| City | Weeks | First (iso_year-Www) | Last (iso_year-Www) | AQI-available weeks |")
    lines.append("|------|-------|----------------------|---------------------|---------------------|")
    for city, grp in base.groupby("city", sort=True):
        first = grp.iloc[0]
        last = grp.iloc[-1]
        aqi_weeks = int(grp["aqi_available"].sum())
        lines.append(
            f"| {city} | {len(grp)} | "
            f"{first['iso_year']}-W{int(first['week_of_year']):02d} | "
            f"{last['iso_year']}-W{int(last['week_of_year']):02d} | {aqi_weeks} |"
        )
    lines.append("")

    lines.append("## Post-merge missingness (per column)")
    lines.append("")
    lines.append("| Column | Missing | % Missing |")
    lines.append("|--------|---------|-----------|")
    for col, (n, pct) in column_missingness(base).items():
        lines.append(f"| {col} | {n} | {pct:.1f}% |")
    lines.append("")

    lines.append("## Aggregation (documented)")
    lines.append("")
    lines.append("- temperature → **mean**, humidity → **mean**, precipitation → **sum**")
    lines.append("- pm2_5 / pm10 / us_aqi → **mean**")
    lines.append("- aqi_available → carried forward (**any** day with AQI in the week)")
    lines.append("- `days_in_week` records how many daily rows fed each weekly cell "
                 "(< 7 at dataset boundaries / partial weeks).")
    lines.append("")
    return "\n".join(lines)


def main() -> None:
    """Build the weekly base table, write it and the merge summary."""
    import time

    from app.logging_config import configure_logging

    configure_logging("INFO")

    start = time.perf_counter()
    base = merge_all()
    duration = time.perf_counter() - start

    out_path = paths.DATA_DIR / "interim" / "weekly_base.parquet"
    paths.ensure_dir(out_path.parent)
    base.to_parquet(out_path, index=False)

    paths.ensure_dir(paths.REPORTS_DIR)
    (paths.REPORTS_DIR / "merge_summary.md").write_text(
        render_summary(base), encoding="utf-8"
    )

    n_dupes = len(base) - base[KEY].drop_duplicates().shape[0]
    logger.info("merged", extra={"rows": len(base), "duplicate_keys": n_dupes})
    print(f"weekly_base rows={len(base)} cities={base['city'].nunique()} "
          f"duplicate_keys={n_dupes}")
    print(f"table  -> {out_path}")
    print(f"report -> {paths.REPORTS_DIR / 'merge_summary.md'}")

    missingness = column_missingness(base)  # reused, not recomputed by quality_report
    quality = new_report("weekly_base")
    quality.add_stage(
        from_merge(
            rows=len(base),
            cities=int(base["city"].nunique()),
            duplicate_keys=n_dupes,
            column_missing_pct={col: pct for col, (_, pct) in missingness.items()},
            duration_seconds=duration,
        )
    )
    quality.save(paths.REPORTS_DIR / "quality_weekly_base.json")
    print(quality.render_text())


if __name__ == "__main__":
    main()
