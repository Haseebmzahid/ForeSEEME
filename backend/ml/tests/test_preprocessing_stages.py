"""Tests for the M5.3 preprocessing stage boundaries.

These are unit tests of stage *primitives* that were already isolated pure
functions but only ever exercised indirectly through `clean_city`/`merge_all`
integration tests (`test_clean.py`, `test_merge.py`, both untouched and still
passing). Nothing here changes production behavior — it only proves the
already-existing stages behave as documented and compose correctly.
"""

from __future__ import annotations

import numpy as np
import pandas as pd
import pytest

from ml.pipelines import clean, merge
from ml.pipelines.acquisition_base import Window

ALIASES = clean._canonical_aliases([{"name": "Lahore"}, {"name": "Karachi"}])


# --- Validation stage: clean.py's own precondition check --------------------


def test_require_raw_file_raises_clearly_when_missing(tmp_path) -> None:
    missing = tmp_path / "raw" / "weather" / "Atlantis.json"
    with pytest.raises(FileNotFoundError, match="open_meteo_weather.*Atlantis"):
        clean._require_raw_file(missing, "open_meteo_weather", "Atlantis")


def test_require_raw_file_is_a_noop_when_present(tmp_path) -> None:
    present = tmp_path / "raw.json"
    present.write_text("{}", encoding="utf-8")
    clean._require_raw_file(present, "open_meteo_weather", "Lahore")  # must not raise


def test_merge_load_source_daily_validation_unchanged(tmp_path) -> None:
    """merge.py's existing precondition check (documented, not modified)."""
    empty_dir = tmp_path / "interim" / "weather"
    empty_dir.mkdir(parents=True)
    with pytest.raises(FileNotFoundError, match="no interim parquet files"):
        merge.load_source_daily(tmp_path, "weather")


# --- Cleaning stage: enforce_range, interpolate_short_gaps as pure units ----


def test_enforce_range_flags_and_masks_out_of_bounds_values() -> None:
    series = pd.Series([10.0, -5.0, 200.0, 50.0])
    cleaned, n_flagged = clean.enforce_range(series, lo=0.0, hi=100.0)
    assert n_flagged == 2
    assert np.isnan(cleaned.iloc[1])
    assert np.isnan(cleaned.iloc[2])
    assert cleaned.iloc[0] == 10.0
    assert cleaned.iloc[3] == 50.0


def test_enforce_range_noop_when_no_bounds_configured() -> None:
    series = pd.Series([1.0, -999.0, 999.0])
    cleaned, n_flagged = clean.enforce_range(series, lo=None, hi=None)
    assert n_flagged == 0
    pd.testing.assert_series_equal(cleaned, series)


def test_interpolate_short_gaps_fills_interior_within_limit_only() -> None:
    series = pd.Series([10.0, np.nan, np.nan, 40.0, np.nan, np.nan, np.nan, np.nan, 90.0])
    filled, imputed, n = clean.interpolate_short_gaps(series, max_gap=2)
    # 2-day interior gap (index 1-2) is within limit -> interpolated.
    assert not np.isnan(filled.iloc[1])
    assert not np.isnan(filled.iloc[2])
    assert bool(imputed[1]) is True
    # 4-day interior gap (index 4-7) exceeds the limit -> left NaN.
    assert filled.iloc[4:8].isna().all()
    assert not imputed[4:8].any()
    assert n == 2


def test_interpolate_short_gaps_never_extrapolates_edges() -> None:
    series = pd.Series([np.nan, np.nan, 10.0, 20.0, np.nan, np.nan])
    filled, imputed, n = clean.interpolate_short_gaps(series, max_gap=5)
    assert filled.iloc[:2].isna().all()   # leading NaNs untouched
    assert filled.iloc[4:].isna().all()   # trailing NaNs untouched
    assert n == 0


# --- Normalization stage: aggregate_daily, normalize_city as pure units -----


def test_aggregate_daily_reduces_hourly_to_daily_mean() -> None:
    idx = pd.to_datetime([f"2022-08-05T{h:02d}:00" for h in range(24)]
                         + [f"2022-08-06T{h:02d}:00" for h in range(24)])
    series = pd.Series([50.0] * 24 + [60.0] * 24, index=idx)
    daily = clean.aggregate_daily(series, "hourly", "mean")
    assert len(daily) == 2
    assert daily.iloc[0] == pytest.approx(50.0)
    assert daily.iloc[1] == pytest.approx(60.0)


def test_aggregate_daily_passes_through_and_normalises_daily_series() -> None:
    idx = pd.to_datetime(["2022-08-05", "2022-08-06"])
    series = pd.Series([1.0, 2.0], index=idx)
    daily = clean.aggregate_daily(series, "daily", None)
    pd.testing.assert_series_equal(daily.reset_index(drop=True), series.reset_index(drop=True))


def test_aggregate_daily_empty_series_is_noop() -> None:
    empty = pd.Series(dtype="float64")
    assert clean.aggregate_daily(empty, "hourly", "mean").empty


def test_normalize_city_canonicalizes_known_aliases() -> None:
    assert clean.normalize_city("lahore", ALIASES) == "Lahore"
    assert clean.normalize_city("  KARACHI  ", ALIASES) == "Karachi"


def test_normalize_city_validation_raises_on_unknown() -> None:
    with pytest.raises(ValueError, match="unknown city"):
        clean.normalize_city("Gotham", ALIASES)


# --- Merge Preparation stage: with_iso_week as a pure unit ------------------


def test_with_iso_week_derives_correct_iso_year_and_week() -> None:
    daily = pd.DataFrame({
        "city": ["Lahore"] * 2,
        "date": pd.to_datetime(["2022-08-08", "2022-08-14"]),  # both ISO 2022-W32
    })
    out = merge.with_iso_week(daily)
    assert list(out["iso_year"]) == [2022, 2022]
    assert list(out["week_of_year"]) == [32, 32]


# --- Stage composition: clean_city == manual Normalization -> Cleaning -----


def test_clean_city_composes_normalization_then_cleaning_stages() -> None:
    """clean_city's per-variable pipeline must equal calling the same public
    stage functions by hand, in the documented order (Normalization then
    Cleaning) — proving the stages genuinely compose, not just coincidentally
    agree."""
    window = Window("2022-08-05", "2022-08-07")
    raw = {
        "daily": {
            "time": ["2022-08-05", "2022-08-06", "2022-08-07"],
            "temperature_2m_mean": [30.0, 150.0, None],  # 150 out of range, 3rd missing
            "precipitation_sum": [0.0, 1.0, 2.0],
        },
        "hourly": {
            "time": [f"2022-08-0{d}T00:00" for d in (5, 6, 7)],
            "relative_humidity_2m": [55.0, 56.0, 57.0],
        },
    }
    source = {
        "granularity": "daily",
        "variables": {
            "temperature": {"api_param": "temperature_2m_mean", "acquire_param": "temperature_2m_mean", "acquire_granularity": "daily"},
        },
    }
    cleaning_cfg = {
        "daily_aggregation": {},
        "physical_ranges": {"temperature": [-90, 60]},
    }
    specs = clean.variable_cleans(source, cleaning_cfg)

    frame, _ = clean.clean_city(raw, "open_meteo_weather", "lahore", window, specs, max_gap=1,
                                 aliases=ALIASES)

    # Manual composition using the same public stage functions.
    daily_index = pd.date_range(window.start, window.end, freq="D")
    manual_city = clean.normalize_city("lahore", ALIASES)
    manual = clean._raw_series(raw, "daily", "temperature_2m_mean")
    manual = clean.aggregate_daily(manual, "daily", None).reindex(daily_index)
    manual, _ = clean.enforce_range(manual, -90, 60)
    manual_filled, manual_imputed, _ = clean.interpolate_short_gaps(manual, 1)

    assert manual_city == "Lahore"
    np.testing.assert_array_equal(frame["temperature"].to_numpy(), manual_filled.to_numpy())
    np.testing.assert_array_equal(frame["temperature_imputed"].to_numpy(), manual_imputed)


# --- Preprocessing boundary: Module 5/6 handoff contract --------------------


def test_merge_columns_is_the_documented_module6_handoff_shape() -> None:
    """merge.COLUMNS is the entire contract features.py (Module 6) reads from
    weekly_base.parquet — this test pins that shape so a future merge.py
    change cannot silently alter Module 6's input without failing here."""
    assert merge.COLUMNS == [
        "city", "iso_year", "week_of_year", "days_in_week",
        "temperature", "humidity", "precipitation",
        "pm2_5", "pm10", "us_aqi", "aqi_available",
    ]

    weather = pd.DataFrame({
        "city": "Lahore", "date": pd.to_datetime(["2022-08-08"]),
        "temperature": [20.0], "humidity": [50.0], "precipitation": [0.0],
    })
    aqi = pd.DataFrame({
        "city": "Lahore", "date": pd.to_datetime(["2022-08-08"]),
        "pm2_5": [10.0], "pm10": [20.0], "us_aqi": [30.0], "aqi_available": [True],
    })
    base = merge.merge_sources(merge.aggregate_weekly_weather(weather),
                                merge.aggregate_weekly_aqi(aqi))
    assert list(base.columns) == merge.COLUMNS
