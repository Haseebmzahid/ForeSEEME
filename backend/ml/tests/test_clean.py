"""Tests for the Sprint 2 cleaning pipeline (Prompt 6).

Unit tests on synthetic *dirty* input covering each policy:
- out-of-range values are flagged and removed (NaN);
- short interior gaps are interpolated within max-gap, longer gaps are not;
- a long AQI gap is left NaN and flagged ``aqi_available = False``;
- hourly → daily aggregation (humidity mean) is correct;
- city-name normalisation is correct;
- cleaning is deterministic from raw.
"""

from __future__ import annotations

import numpy as np
import pandas as pd
import pytest

from ml.pipelines import clean
from ml.pipelines.acquisition_base import Window

ALIASES = clean._canonical_aliases(
    [
        {"name": "Islamabad"},
        {"name": "Rawalpindi"},
        {"name": "Lahore"},
        {"name": "Karachi"},
        {"name": "Peshawar"},
    ]
)

CLEANING = {
    "max_interpolation_gap_days": 3,
    "daily_aggregation": {"humidity": "mean", "pm2_5": "mean", "pm10": "mean", "us_aqi": "mean"},
    "physical_ranges": {
        "temperature": [-90, 60],
        "humidity": [0, 100],
        "precipitation": [0, 1000],
        "pm2_5": [0, 1000],
        "pm10": [0, 2000],
        "us_aqi": [0, 1000],
    },
}

WEATHER_SOURCE = {
    "granularity": "daily",
    "variables": {
        "temperature": {"api_param": "temperature_2m_mean", "acquire_param": "temperature_2m_mean", "acquire_granularity": "daily"},
        "humidity": {"api_param": "relative_humidity_2m_mean", "acquire_param": "relative_humidity_2m", "acquire_granularity": "hourly"},
        "precipitation": {"api_param": "precipitation_sum", "acquire_param": "precipitation_sum", "acquire_granularity": "daily"},
    },
}

AQI_SOURCE = {
    "granularity": "hourly",
    "variables": {
        "pm2_5": {"api_param": "pm2_5"},
        "pm10": {"api_param": "pm10"},
        "us_aqi": {"api_param": "us_aqi"},
    },
}


# --- City normalisation ----------------------------------------------------


@pytest.mark.parametrize(
    "messy,expected",
    [
        ("lahore", "Lahore"),
        ("  LAHORE  ", "Lahore"),
        ("Karachi", "Karachi"),
        ("khi", "Karachi"),
        ("peshwar", "Peshawar"),
    ],
)
def test_city_normalisation(messy, expected) -> None:
    assert clean.normalize_city(messy, ALIASES) == expected


def test_unknown_city_raises() -> None:
    with pytest.raises(ValueError):
        clean.normalize_city("Gotham", ALIASES)


# --- Hourly → daily aggregation --------------------------------------------


def test_humidity_hourly_mean_aggregation() -> None:
    window = Window("2022-08-05", "2022-08-06")
    # Day 1: hourly humidity averaging 50; Day 2: averaging 60.
    hours_d1 = [f"2022-08-05T{h:02d}:00" for h in range(24)]
    hours_d2 = [f"2022-08-06T{h:02d}:00" for h in range(24)]
    raw = {
        "daily": {
            "time": ["2022-08-05", "2022-08-06"],
            "temperature_2m_mean": [30.0, 31.0],
            "precipitation_sum": [0.0, 5.0],
        },
        "hourly": {
            "time": hours_d1 + hours_d2,
            "relative_humidity_2m": [50.0] * 24 + [60.0] * 24,
        },
    }
    specs = clean.variable_cleans(WEATHER_SOURCE, CLEANING)
    frame, _ = clean.clean_city(raw, "open_meteo_weather", "Lahore", window, specs, 3, ALIASES)
    assert frame.loc[0, "humidity"] == pytest.approx(50.0)
    assert frame.loc[1, "humidity"] == pytest.approx(60.0)
    assert frame.loc[1, "precipitation"] == pytest.approx(5.0)


# --- Physical ranges -------------------------------------------------------


def test_out_of_range_values_flagged_and_removed() -> None:
    window = Window("2022-08-05", "2022-08-07")
    raw = {
        "daily": {
            "time": ["2022-08-05", "2022-08-06", "2022-08-07"],
            "temperature_2m_mean": [30.0, 31.0, 32.0],
            "precipitation_sum": [0.0, 1.0, 2.0],
        },
        "hourly": {
            "time": [f"2022-08-0{d}T00:00" for d in (5, 6, 7)],
            "relative_humidity_2m": [55.0, 150.0, 60.0],  # 150% is impossible
        },
    }
    specs = clean.variable_cleans(WEATHER_SOURCE, CLEANING)
    frame, stats = clean.clean_city(raw, "open_meteo_weather", "Lahore", window, specs, 0, ALIASES)
    # The 150% reading is dropped to NaN and counted.
    assert np.isnan(frame.loc[1, "humidity"])
    hum_stats = next(v for v in stats.variables if v.variable == "humidity")
    assert hum_stats.out_of_range == 1


def test_negative_aqi_flagged() -> None:
    window = Window("2022-08-05", "2022-08-05")
    raw = {
        "hourly": {
            "time": [f"2022-08-05T{h:02d}:00" for h in range(24)],
            "pm2_5": [-5.0] * 24,  # impossible negative -> NaN
            "pm10": [40.0] * 24,
            "us_aqi": [80.0] * 24,
        }
    }
    specs = clean.variable_cleans(AQI_SOURCE, CLEANING)
    frame, stats = clean.clean_city(
        raw, "open_meteo_air_quality", "Lahore", window, specs, 0, ALIASES, add_aqi_flag=True
    )
    assert np.isnan(frame.loc[0, "pm2_5"])
    pm = next(v for v in stats.variables if v.variable == "pm2_5")
    assert pm.out_of_range == 1
    # pm10/us_aqi still present -> the day is aqi_available.
    assert bool(frame.loc[0, "aqi_available"]) is True


# --- Gap policy ------------------------------------------------------------


def test_short_gap_interpolated_long_gap_left_nan() -> None:
    window = Window("2022-08-01", "2022-08-12")  # 12 days
    dates = [f"2022-08-{d:02d}" for d in range(1, 13)]
    temps: list[float | None] = [20.0] * 12
    # Short 2-day interior gap (within max_gap=3): days index 2,3 (Aug 03-04).
    temps[2] = None
    temps[3] = None
    # Long 5-day interior gap (> max_gap): days index 5..9 (Aug 06-10).
    for i in range(5, 10):
        temps[i] = None
    raw = {
        "daily": {
            "time": dates,
            "temperature_2m_mean": temps,
            "precipitation_sum": [0.0] * 12,
        },
        "hourly": {"time": [f"{d}T00:00" for d in dates], "relative_humidity_2m": [50.0] * 12},
    }
    specs = clean.variable_cleans(WEATHER_SOURCE, CLEANING)
    frame, stats = clean.clean_city(raw, "open_meteo_weather", "Lahore", window, specs, 3, ALIASES)

    # Short gap filled (linear ~20.0) and flagged.
    assert not np.isnan(frame.loc[2, "temperature"])
    assert not np.isnan(frame.loc[3, "temperature"])
    assert bool(frame.loc[2, "temperature_imputed"]) is True
    # Long gap untouched.
    for i in range(5, 10):
        assert np.isnan(frame.loc[i, "temperature"])
        assert bool(frame.loc[i, "temperature_imputed"]) is False

    temp_stats = next(v for v in stats.variables if v.variable == "temperature")
    assert temp_stats.interpolated == 2
    # `missing` is RAW missingness (2 short-gap + 5 long-gap)...
    assert temp_stats.missing == 7
    # ...and the residual that was NOT imputed is exactly the long gap.
    assert temp_stats.missing - temp_stats.interpolated == 5


def test_long_aqi_gap_left_nan_and_flagged_unavailable() -> None:
    window = Window("2022-08-01", "2022-08-31")  # 31 days
    # Data only on the last 5 days; first 26 are a long pre-coverage absence.
    dates = []
    for d in range(27, 32):
        dates += [f"2022-08-{d:02d}T{h:02d}:00" for h in range(24)]
    vals = [40.0] * len(dates)
    raw = {"hourly": {"time": dates, "pm2_5": vals, "pm10": vals, "us_aqi": vals}}

    specs = clean.variable_cleans(AQI_SOURCE, CLEANING)
    frame, stats = clean.clean_city(
        raw, "open_meteo_air_quality", "Lahore", window, specs, 3, ALIASES, add_aqi_flag=True
    )

    # The 26-day pre-coverage block is NaN and NOT imputed.
    assert frame.loc[:25, "pm2_5"].isna().all()
    assert not frame.loc[:25, "pm2_5_imputed"].any()
    assert not frame.loc[:25, "aqi_available"].any()
    # The covered tail is available.
    assert frame.loc[26:, "aqi_available"].all()
    assert stats.aqi_available_days == 5
    pm = next(v for v in stats.variables if v.variable == "pm2_5")
    assert pm.interpolated == 0  # never imputed across the long absence


# --- Determinism -----------------------------------------------------------


def test_cleaning_is_deterministic() -> None:
    window = Window("2022-08-05", "2022-08-08")
    raw = {
        "daily": {
            "time": ["2022-08-05", "2022-08-06", "2022-08-07", "2022-08-08"],
            "temperature_2m_mean": [30.0, None, 32.0, 33.0],
            "precipitation_sum": [0.0, 1.0, 2.0, 3.0],
        },
        "hourly": {
            "time": [f"2022-08-0{d}T00:00" for d in (5, 6, 7, 8)],
            "relative_humidity_2m": [50.0, 52.0, 54.0, 56.0],
        },
    }
    specs = clean.variable_cleans(WEATHER_SOURCE, CLEANING)
    f1, _ = clean.clean_city(raw, "open_meteo_weather", "Lahore", window, specs, 3, ALIASES)
    f2, _ = clean.clean_city(raw, "open_meteo_weather", "Lahore", window, specs, 3, ALIASES)
    pd.testing.assert_frame_equal(f1, f2)
