"""Data cleaning & missing-value strategy (Sprint 2, Prompt 6).

First transformation step: turn the immutable raw per-source files (Prompts 3-4)
into cleaned, **daily, per-city interim tables**. Cleaning is a pure, deterministic
function of (raw files + config) — raw is read, never mutated; re-running yields
identical interim tables.

What it does, per source / per city:

* **Standardise** city names (canonical, from cities.yaml) and dates (daily index
  over the configured modeling window).
* **Aggregate hourly → daily** where needed: humidity = mean, PM2.5/PM10/US-AQI =
  mean. Temperature and precipitation are already daily and pass through.
* **Enforce physical ranges**: impossible values (negative AQI, humidity > 100, …)
  are dropped to NaN and counted as anomalies.
* **Missing-value policy** (explicit, per variable):
    - short interior gaps (≤ ``max_interpolation_gap_days``) → linear interpolation,
      flagged ``<var>_imputed``;
    - longer gaps → left NaN, **never** imputed. In particular the AQI pre-coverage
      period is retained as NaN and flagged ``aqi_available = False`` — never
      imputed across a multi-year absence.
* Emit a per-source **data-quality summary** (counts, % missing, anomalies).

Outputs: ``data/interim/<source>/<city>.parquet`` and
``reports/data_quality.md``.

Run (from ``backend/``)::

    python -m ml.pipelines.clean
"""

from __future__ import annotations

import json
import logging
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd
import yaml

from ml.pipelines import paths
from ml.pipelines.acquisition_base import Window, load_pipeline_config

logger = logging.getLogger("foreseeme.ml.clean")

WEATHER_SOURCE = "open_meteo_weather"
AQI_SOURCE = "open_meteo_air_quality"
WEATHER_SUBDIR = "weather"
AQI_SUBDIR = "aqi"


# --- Config loading --------------------------------------------------------


def _load_yaml(path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def load_sources(path=paths.SOURCES_PATH) -> dict[str, Any]:
    return _load_yaml(path)["sources"]


def load_cities(path=paths.CITIES_PATH) -> list[dict[str, Any]]:
    return _load_yaml(path)["cities"]


def load_cleaning_config(path=paths.PIPELINE_PATH) -> dict[str, Any]:
    return _load_yaml(path)["cleaning"]


# --- City-name normalisation -----------------------------------------------


def _canonical_aliases(cities: list[dict[str, Any]]) -> dict[str, str]:
    """Map lower-cased name variants to the canonical city name."""
    aliases: dict[str, str] = {}
    for city in cities:
        canonical = city["name"]
        aliases[canonical.lower()] = canonical
    # A few common abbreviations / spellings seen in messy inputs.
    aliases.update(
        {
            "isb": "Islamabad",
            "rwp": "Rawalpindi",
            "lhr": "Lahore",
            "khi": "Karachi",
            "pew": "Peshawar",
            "peshwar": "Peshawar",
        }
    )
    return aliases


def normalize_city(name: str, aliases: dict[str, str]) -> str:
    """Return the canonical city name for a possibly-messy input.

    Trims/space-collapses and case-folds; raises on a genuinely unknown city
    rather than guessing (undocumented coercion would hide bad input).
    """
    key = " ".join(str(name).split()).lower()
    if key in aliases:
        return aliases[key]
    raise ValueError(f"unknown city name: {name!r}")


# --- Variable cleaning spec ------------------------------------------------


@dataclass(frozen=True)
class VariableClean:
    """How one source variable is cleaned into a daily column."""

    name: str
    raw_key: str
    granularity: str  # "daily" | "hourly"
    aggregation: str | None  # "mean" | "sum" | None (already daily)
    range_lo: float | None
    range_hi: float | None


def variable_cleans(
    source: dict[str, Any], cleaning: dict[str, Any]
) -> list[VariableClean]:
    """Build the cleaning spec for a source from sources.yaml + cleaning config."""
    default_granularity = source.get("granularity", "daily")
    aggregations = cleaning.get("daily_aggregation", {})
    ranges = cleaning.get("physical_ranges", {})
    specs: list[VariableClean] = []
    for name, var in source["variables"].items():
        granularity = var.get("acquire_granularity", default_granularity)
        rng = ranges.get(name, [None, None])
        specs.append(
            VariableClean(
                name=name,
                raw_key=var.get("acquire_param", var["api_param"]),
                granularity=granularity,
                aggregation=aggregations.get(name) if granularity == "hourly" else None,
                range_lo=rng[0],
                range_hi=rng[1],
            )
        )
    return specs


# --- Stats models ----------------------------------------------------------


@dataclass
class VariableStats:
    variable: str
    days: int
    present: int
    missing: int
    out_of_range: int
    interpolated: int
    coverage_start: str | None
    coverage_end: str | None

    @property
    def pct_missing(self) -> float:
        return (self.missing / self.days * 100.0) if self.days else 0.0


@dataclass
class CityStats:
    source: str
    city: str
    days: int
    variables: list[VariableStats] = field(default_factory=list)
    aqi_available_days: int | None = None


# --- Core cleaning primitives ----------------------------------------------


def _raw_series(raw: dict[str, Any], granularity: str, raw_key: str) -> pd.Series:
    """Extract a float Series (NaN for nulls) indexed by timestamp from raw."""
    block = raw.get(granularity, {}) or {}
    times = block.get("time", []) or []
    values = block.get(raw_key, [])
    if not times or values is None or raw_key not in block:
        return pd.Series(dtype="float64")
    arr = [np.nan if v is None else float(v) for v in values]
    return pd.Series(arr, index=pd.to_datetime(times), dtype="float64")


def aggregate_daily(series: pd.Series, granularity: str, method: str | None) -> pd.Series:
    """Reduce an hourly series to daily; pass a daily series through (normalised)."""
    if series.empty:
        return series
    if granularity == "hourly" and method:
        if method == "sum":
            return series.resample("D").sum(min_count=1)
        return series.resample("D").agg(method)
    # Already daily — normalise the index to midnight dates.
    return series.groupby(series.index.normalize()).first()


def enforce_range(
    series: pd.Series, lo: float | None, hi: float | None
) -> tuple[pd.Series, int]:
    """Drop out-of-range values to NaN; return (cleaned, n_flagged)."""
    if lo is None and hi is None:
        return series, 0
    mask = pd.Series(False, index=series.index)
    if lo is not None:
        mask |= series < lo
    if hi is not None:
        mask |= series > hi
    return series.mask(mask), int(mask.sum())


def interpolate_short_gaps(
    series: pd.Series, max_gap: int
) -> tuple[pd.Series, np.ndarray, int]:
    """Linearly interpolate interior NaN runs of length ≤ ``max_gap``.

    Longer runs and edge (leading/trailing) NaNs are left untouched — this is the
    hard guard against imputing across a long absence. Returns (series, imputed
    boolean mask, n_interpolated).
    """
    values = series.to_numpy(dtype="float64")
    isna = np.isnan(values)
    imputed = np.zeros(len(values), dtype=bool)
    if max_gap <= 0 or not isna.any():
        return series, imputed, 0

    interp = series.interpolate(method="linear", limit_area="inside").to_numpy(
        dtype="float64"
    )
    out = values.copy()
    n = len(values)
    i = 0
    while i < n:
        if isna[i]:
            j = i
            while j < n and isna[j]:
                j += 1
            run_len = j - i
            interior = i > 0 and j < n  # both neighbours are valid
            if interior and run_len <= max_gap:
                out[i:j] = interp[i:j]
                imputed[i:j] = True
            i = j
        else:
            i += 1
    return pd.Series(out, index=series.index), imputed, int(imputed.sum())


# --- Per-city cleaning -----------------------------------------------------


def clean_city(
    raw: dict[str, Any],
    source_key: str,
    city_name: str,
    window: Window,
    specs: list[VariableClean],
    max_gap: int,
    aliases: dict[str, str],
    add_aqi_flag: bool = False,
) -> tuple[pd.DataFrame, CityStats]:
    """Clean one city's raw response into a daily DataFrame + stats."""
    canonical = normalize_city(city_name, aliases)
    daily_index = pd.date_range(window.start, window.end, freq="D")
    frame = pd.DataFrame({"city": canonical, "date": daily_index})
    stats = CityStats(source=source_key, city=canonical, days=len(daily_index))

    value_columns: list[str] = []
    for spec in specs:
        series = _raw_series(raw, spec.granularity, spec.raw_key)
        series = aggregate_daily(series, spec.granularity, spec.aggregation)
        series = series.reindex(daily_index)
        series, n_out = enforce_range(series, spec.range_lo, spec.range_hi)

        # "Real" (pre-interpolation) presence drives missingness + coverage.
        present_mask = series.notna()
        present = int(present_mask.sum())
        real_dates = daily_index[present_mask.to_numpy()]
        cov_start = real_dates.min().date().isoformat() if len(real_dates) else None
        cov_end = real_dates.max().date().isoformat() if len(real_dates) else None

        filled, imputed, n_interp = interpolate_short_gaps(series, max_gap)
        frame[spec.name] = filled.to_numpy()
        frame[f"{spec.name}_imputed"] = imputed
        value_columns.append(spec.name)

        stats.variables.append(
            VariableStats(
                variable=spec.name,
                days=len(daily_index),
                present=present,
                missing=len(daily_index) - present,
                out_of_range=n_out,
                interpolated=n_interp,
                coverage_start=cov_start,
                coverage_end=cov_end,
            )
        )

    if add_aqi_flag:
        # Available where any pollutant has a (real or short-imputed) value;
        # False where all remain NaN — i.e. pre-coverage / long-gap, never imputed.
        available = frame[value_columns].notna().any(axis=1)
        frame["aqi_available"] = available.to_numpy()
        stats.aqi_available_days = int(available.sum())

    return frame, stats


# --- Source-level orchestration --------------------------------------------


def clean_source(
    source_key: str,
    subdir: str,
    sources: dict[str, Any],
    cities: list[dict[str, Any]],
    window: Window,
    cleaning: dict[str, Any],
    *,
    data_dir: Path,
    add_aqi_flag: bool = False,
) -> list[CityStats]:
    """Clean every city for one source, writing ``interim/<source>/<city>.parquet``."""
    source = sources[source_key]
    specs = variable_cleans(source, cleaning)
    max_gap = int(cleaning["max_interpolation_gap_days"])
    aliases = _canonical_aliases(cities)
    out_dir = paths.ensure_dir(data_dir / "interim" / subdir)

    all_stats: list[CityStats] = []
    for city in cities:
        raw_path = data_dir / "raw" / subdir / f"{city['name']}.json"
        raw = json.loads(raw_path.read_text(encoding="utf-8"))
        frame, stats = clean_city(
            raw, source_key, city["name"], window, specs, max_gap, aliases, add_aqi_flag
        )
        frame.to_parquet(out_dir / f"{stats.city}.parquet", index=False)
        all_stats.append(stats)
        logger.info(
            "cleaned",
            extra={
                "source": source_key,
                "city": stats.city,
                "days": stats.days,
                "aqi_available_days": stats.aqi_available_days,
            },
        )
    return all_stats


def clean_all(
    *,
    data_dir: Path | None = None,
    sources: dict[str, Any] | None = None,
    cities: list[dict[str, Any]] | None = None,
    window: Window | None = None,
    cleaning: dict[str, Any] | None = None,
) -> dict[str, list[CityStats]]:
    """Clean weather + AQI sources and return per-source stats."""
    data_dir = data_dir or paths.DATA_DIR
    sources = sources or load_sources()
    cities = cities or load_cities()
    window = window or load_pipeline_config().window
    cleaning = cleaning or load_cleaning_config()

    return {
        WEATHER_SOURCE: clean_source(
            WEATHER_SOURCE, WEATHER_SUBDIR, sources, cities, window, cleaning,
            data_dir=data_dir,
        ),
        AQI_SOURCE: clean_source(
            AQI_SOURCE, AQI_SUBDIR, sources, cities, window, cleaning,
            data_dir=data_dir, add_aqi_flag=True,
        ),
    }


# --- Data-quality report ---------------------------------------------------


def render_data_quality(
    stats_by_source: dict[str, list[CityStats]],
    window: Window,
    cleaning: dict[str, Any],
) -> str:
    """Render reports/data_quality.md from the cleaning stats (deterministic)."""
    lines: list[str] = []
    lines.append("# Data Quality Report — ForeSeeMe Risk Model")
    lines.append("")
    lines.append("**Sprint 2, Prompt 6 — Cleaning & Missing-Value Strategy**")
    lines.append("")
    lines.append(
        f"_Deterministic from the raw files. Modeling window "
        f"{window.start} → {window.end}._"
    )
    lines.append("")

    for source_key, all_stats in stats_by_source.items():
        lines.append(f"## {source_key}")
        lines.append("")
        header = "| City | Variable | Days | Present | Missing | % Missing | Out-of-range | Interpolated | Coverage |"
        lines.append(header)
        lines.append("|------|----------|------|---------|---------|-----------|--------------|--------------|----------|")
        for cs in all_stats:
            for vs in cs.variables:
                cov = (
                    f"{vs.coverage_start}…{vs.coverage_end}"
                    if vs.coverage_start
                    else "—"
                )
                lines.append(
                    f"| {cs.city} | {vs.variable} | {vs.days} | {vs.present} | "
                    f"{vs.missing} | {vs.pct_missing:.1f}% | {vs.out_of_range} | "
                    f"{vs.interpolated} | {cov} |"
                )
        if any(cs.aqi_available_days is not None for cs in all_stats):
            lines.append("")
            lines.append("AQI availability (days with real or short-imputed data):")
            lines.append("")
            for cs in all_stats:
                if cs.aqi_available_days is not None:
                    lines.append(
                        f"- {cs.city}: {cs.aqi_available_days}/{cs.days} days "
                        f"`aqi_available=True`"
                    )
        lines.append("")

    lines.append("## Missing-value policy (documented)")
    lines.append("")
    lines.append(
        f"- **Short gaps** (≤ {cleaning['max_interpolation_gap_days']} consecutive "
        "days) are linearly interpolated and flagged per variable "
        "(`<var>_imputed`)."
    )
    lines.append(
        "- **Longer gaps are never imputed** — they are left as NaN. The AQI "
        "pre-coverage period is retained as NaN with `aqi_available=False`; no "
        "values are invented across a multi-year absence."
    )
    lines.append("- **Leading/trailing** NaNs are never extrapolated.")
    lines.append(
        "- **Physical ranges** (out-of-range dropped to NaN and counted above):"
    )
    for var, (lo, hi) in cleaning["physical_ranges"].items():
        lines.append(f"  - `{var}` ∈ [{lo}, {hi}]")
    lines.append(
        f"- **Hourly→daily aggregation**: "
        + ", ".join(f"`{k}`={v}" for k, v in cleaning["daily_aggregation"].items())
        + "; temperature and precipitation are already daily."
    )
    lines.append("")
    return "\n".join(lines)


def main() -> None:
    """Clean all sources, write interim parquet tables, and the quality report."""
    from app.logging_config import configure_logging

    config = load_pipeline_config()
    configure_logging(config.log_level)
    cleaning = load_cleaning_config()
    stats = clean_all(window=config.window, cleaning=cleaning)

    report = render_data_quality(stats, config.window, cleaning)
    paths.ensure_dir(paths.REPORTS_DIR)
    (paths.REPORTS_DIR / "data_quality.md").write_text(report, encoding="utf-8")

    for source_key, all_stats in stats.items():
        for cs in all_stats:
            total_missing = sum(v.missing for v in cs.variables)
            print(f"{source_key:24} {cs.city:11} days={cs.days} missing_cells={total_missing}")
    print(f"report -> {paths.REPORTS_DIR / 'data_quality.md'}")


if __name__ == "__main__":
    main()
