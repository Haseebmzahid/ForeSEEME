"""Tests for the Sprint 2 merge pipeline (Prompt 7).

Synthetic multi-source input:
- weekly aggregation arithmetic (mean vs sum) is correct;
- the merge yields the expected (city, week) rows, uniquely keyed;
- missing AQI weeks are preserved as NaN with aqi_available = False (no inner-join drop).
"""

from __future__ import annotations

import numpy as np
import pandas as pd

from ml.pipelines import merge


def _weather_daily(city: str, dates: list[str], temp, humidity, precip) -> pd.DataFrame:
    return pd.DataFrame(
        {
            "city": city,
            "date": pd.to_datetime(dates),
            "temperature": temp,
            "humidity": humidity,
            "precipitation": precip,
        }
    )


def _aqi_daily(city: str, dates: list[str], pm2_5, pm10, us_aqi, available) -> pd.DataFrame:
    return pd.DataFrame(
        {
            "city": city,
            "date": pd.to_datetime(dates),
            "pm2_5": pm2_5,
            "pm10": pm10,
            "us_aqi": us_aqi,
            "aqi_available": available,
        }
    )


# A full ISO week: Mon 2022-08-08 .. Sun 2022-08-14 = ISO 2022-W32.
WEEK32 = [f"2022-08-{d:02d}" for d in range(8, 15)]


def test_weekly_aggregation_arithmetic() -> None:
    temp = [10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 70.0]  # mean 40
    humidity = [50.0] * 7  # mean 50
    precip = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0]  # sum 28
    weekly = merge.aggregate_weekly_weather(
        _weather_daily("Lahore", WEEK32, temp, humidity, precip)
    )
    assert len(weekly) == 1
    row = weekly.iloc[0]
    assert int(row["iso_year"]) == 2022
    assert int(row["week_of_year"]) == 32
    assert int(row["days_in_week"]) == 7
    assert row["temperature"] == 40.0       # mean
    assert row["humidity"] == 50.0          # mean
    assert row["precipitation"] == 28.0     # SUM, not mean


def test_aqi_weekly_mean_and_flag() -> None:
    weekly = merge.aggregate_weekly_aqi(
        _aqi_daily("Lahore", WEEK32, [10.0] * 7, [20.0] * 7, [30.0] * 7, [True] * 7)
    )
    row = weekly.iloc[0]
    assert row["pm2_5"] == 10.0
    assert row["pm10"] == 20.0
    assert row["us_aqi"] == 30.0
    assert bool(row["aqi_available"]) is True


def test_expected_city_week_rows_and_unique_keys() -> None:
    # Two cities, two full weeks each -> 4 rows.
    week33 = [f"2022-08-{d:02d}" for d in range(15, 22)]  # ISO 2022-W33
    frames = []
    for city in ("Lahore", "Karachi"):
        for wk in (WEEK32, week33):
            frames.append(_weather_daily(city, wk, [20.0] * 7, [50.0] * 7, [0.0] * 7))
    weather = pd.concat(frames, ignore_index=True)

    aqi_frames = []
    for city in ("Lahore", "Karachi"):
        for wk in (WEEK32, week33):
            aqi_frames.append(_aqi_daily(city, wk, [40.0] * 7, [60.0] * 7, [80.0] * 7, [True] * 7))
    aqi = pd.concat(aqi_frames, ignore_index=True)

    base = merge.merge_sources(
        merge.aggregate_weekly_weather(weather), merge.aggregate_weekly_aqi(aqi)
    )
    assert len(base) == 4
    # Uniquely keyed.
    assert base[merge.KEY].duplicated().sum() == 0
    assert list(base.columns) == merge.COLUMNS


def test_missing_aqi_week_preserved_as_nan_and_flag() -> None:
    week33 = [f"2022-08-{d:02d}" for d in range(15, 22)]  # ISO 2022-W33
    # Weather has W32 and W33; AQI only has W32.
    weather = pd.concat(
        [
            _weather_daily("Lahore", WEEK32, [20.0] * 7, [50.0] * 7, [0.0] * 7),
            _weather_daily("Lahore", week33, [21.0] * 7, [51.0] * 7, [0.0] * 7),
        ],
        ignore_index=True,
    )
    aqi = _aqi_daily("Lahore", WEEK32, [40.0] * 7, [60.0] * 7, [80.0] * 7, [True] * 7)

    base = merge.merge_sources(
        merge.aggregate_weekly_weather(weather), merge.aggregate_weekly_aqi(aqi)
    )
    # Outer join keeps BOTH weeks (no inner-join drop).
    assert len(base) == 2
    w33 = base[base["week_of_year"] == 33].iloc[0]
    assert np.isnan(w33["pm2_5"])
    assert np.isnan(w33["us_aqi"])
    assert bool(w33["aqi_available"]) is False
    # The AQI-present week is intact.
    w32 = base[base["week_of_year"] == 32].iloc[0]
    assert w32["pm2_5"] == 40.0
    assert bool(w32["aqi_available"]) is True


def test_partial_week_sums_available_days() -> None:
    # A 3-day partial week (start of dataset): sum of present rainfall days.
    partial = [f"2022-08-{d:02d}" for d in (5, 6, 7)]  # ISO 2022-W31 (Fri-Sun)
    weekly = merge.aggregate_weekly_weather(
        _weather_daily("Lahore", partial, [20.0, 22.0, 24.0], [50.0] * 3, [1.0, 2.0, 3.0])
    )
    row = weekly.iloc[0]
    assert int(row["days_in_week"]) == 3
    assert row["temperature"] == 22.0   # mean of 3 days
    assert row["precipitation"] == 6.0  # sum of 3 days


def test_merge_is_deterministic() -> None:
    weather = _weather_daily("Lahore", WEEK32, [20.0] * 7, [50.0] * 7, [1.0] * 7)
    aqi = _aqi_daily("Lahore", WEEK32, [40.0] * 7, [60.0] * 7, [80.0] * 7, [True] * 7)
    a = merge.merge_sources(merge.aggregate_weekly_weather(weather), merge.aggregate_weekly_aqi(aqi))
    b = merge.merge_sources(merge.aggregate_weekly_weather(weather), merge.aggregate_weekly_aqi(aqi))
    pd.testing.assert_frame_equal(a, b)
