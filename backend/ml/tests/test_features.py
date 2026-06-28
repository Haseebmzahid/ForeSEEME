"""Tests for the Sprint 2 feature engineering (Prompt 8).

Covers:
- lag/rolling correctness on a known series;
- anomaly = value − climatology (expanding, prior-years-only);
- cyclical encoding bounds and week-1≈week-52 adjacency;
- LOOKAHEAD: a feature at week t never uses data from t+1 (perturb-the-future test);
- insufficient-history rows are flagged.
"""

from __future__ import annotations

import numpy as np
import pandas as pd

from ml.pipelines import features as ft

CONFIG = {
    "lags": {"variables": ["precipitation", "temperature", "humidity"], "weeks": [1, 2, 3, 4]},
    "rolling": {"variables": ["precipitation", "temperature", "humidity"], "windows": [3, 4], "shift": 1},
    "anomaly": {"variables": ["temperature", "humidity", "precipitation", "us_aqi"], "mode": "expanding"},
    "cyclical": {"period": 52},
    "city_encoding": "onehot",
    "min_history_weeks": 5,
    "drop_insufficient_history": False,
}
VOCAB = ["Islamabad", "Rawalpindi", "Lahore", "Karachi", "Peshawar"]


def _contiguous_city(city: str, n_weeks: int, start_week: int = 1, iso_year: int = 2023) -> pd.DataFrame:
    """A contiguous weekly series for one city (one ISO year, simple ramps)."""
    weeks = list(range(start_week, start_week + n_weeks))
    return pd.DataFrame(
        {
            "city": city,
            "iso_year": iso_year,
            "week_of_year": weeks,
            "days_in_week": 7,
            "temperature": [20.0 + i for i in range(n_weeks)],
            "humidity": [50.0 + i for i in range(n_weeks)],
            "precipitation": [float(i) for i in range(n_weeks)],
            "pm2_5": [30.0 + i for i in range(n_weeks)],
            "pm10": [40.0 + i for i in range(n_weeks)],
            "us_aqi": [80.0 + i for i in range(n_weeks)],
            "aqi_available": True,
        }
    )


# --- Lag / rolling correctness ---------------------------------------------


def test_lag_correctness() -> None:
    base = _contiguous_city("Lahore", 8)
    df, _ = ft.engineer_features(base, CONFIG, VOCAB)
    # temperature ramps 20,21,...; lag1 at row 3 = temp[row2] = 22.
    assert df.loc[3, "temperature_lag1"] == 22.0
    assert df.loc[3, "temperature_lag2"] == 21.0
    # lag4 at row 4 = temp[row0] = 20.
    assert df.loc[4, "temperature_lag4"] == 20.0
    # First k rows have no lag-k value.
    assert np.isnan(df.loc[0, "temperature_lag1"])
    assert np.isnan(df.loc[3, "temperature_lag4"])  # row 3 needs row -1


def test_rolling_is_trailing_and_strictly_past() -> None:
    base = _contiguous_city("Lahore", 8)
    df, _ = ft.engineer_features(base, CONFIG, VOCAB)
    # temperature roll3 (shift=1) at row 4 = mean(temp[1],temp[2],temp[3]) = mean(21,22,23)=22.
    assert df.loc[4, "temperature_roll3"] == 22.0
    # Strictly past: it must NOT include the current week (temp[4]=24).
    assert df.loc[4, "temperature_roll3"] != np.mean([22.0, 23.0, 24.0])
    # Insufficient history -> NaN (row 3 needs t-1..t-3 i.e. rows 0,1,2 -> ok at row 3? shift1+win3 needs rows 0,1,2)
    assert not np.isnan(df.loc[3, "temperature_roll3"])
    assert np.isnan(df.loc[2, "temperature_roll3"])


# --- Anomaly = value - climatology -----------------------------------------


def test_anomaly_uses_prior_year_climatology() -> None:
    # Same city/week across three years: values 10, 20, 30.
    frames = [
        pd.DataFrame(
            {
                "city": "Lahore", "iso_year": y, "week_of_year": 10, "days_in_week": 7,
                "temperature": [v], "humidity": [v], "precipitation": [v],
                "pm2_5": [v], "pm10": [v], "us_aqi": [v], "aqi_available": [True],
            }
        )
        for y, v in [(2023, 10.0), (2024, 20.0), (2025, 30.0)]
    ]
    base = pd.concat(frames, ignore_index=True)
    df, _ = ft.engineer_features(base, CONFIG, VOCAB)
    df = df.sort_values("iso_year").reset_index(drop=True)
    # 2023: no prior year -> NaN anomaly, has_climatology False.
    assert np.isnan(df.loc[0, "temperature_anom"])
    assert bool(df.loc[0, "has_climatology"]) is False
    # 2024: climatology = mean(prior years) = 10 -> anomaly = 20 - 10 = 10.
    assert df.loc[1, "temperature_anom"] == 10.0
    # 2025: climatology = mean(10, 20) = 15 -> anomaly = 30 - 15 = 15.
    assert df.loc[2, "temperature_anom"] == 15.0


# --- Cyclical encoding ------------------------------------------------------


def test_cyclical_bounds_and_adjacency() -> None:
    base = pd.concat(
        [_contiguous_city("Lahore", 1, start_week=w) for w in (1, 52, 26)],
        ignore_index=True,
    )
    df, _ = ft.engineer_features(base, CONFIG, VOCAB)
    assert df["week_sin"].between(-1, 1).all()
    assert df["week_cos"].between(-1, 1).all()
    # Week 1 and week 52 are nearly adjacent on the circle.
    w1 = df[df["week_of_year"] == 1].iloc[0]
    w52 = df[df["week_of_year"] == 52].iloc[0]
    dist = np.hypot(w1["week_sin"] - w52["week_sin"], w1["week_cos"] - w52["week_cos"])
    assert dist < 0.2


def test_city_onehot_fixed_vocab() -> None:
    base = _contiguous_city("Karachi", 3)
    df, families = ft.engineer_features(base, CONFIG, VOCAB)
    # All vocab columns exist even though only Karachi is present.
    for name in VOCAB:
        assert f"city_{name}" in df.columns
    assert (df["city_Karachi"] == 1).all()
    assert (df["city_Lahore"] == 0).all()


# --- Lookahead: no future leakage ------------------------------------------


def test_no_future_leakage_perturb_future_row() -> None:
    """Perturbing the LAST (future-most) week must not change any earlier row's
    features — a strong guard against lookahead in lags/rollings/anomaly."""
    base = _contiguous_city("Lahore", 12)
    df1, families = ft.engineer_features(base, CONFIG, VOCAB)

    perturbed = base.copy()
    last = perturbed.index[-1]
    for col in ("temperature", "humidity", "precipitation", "us_aqi"):
        perturbed.loc[last, col] += 999.0
    df2, _ = ft.engineer_features(perturbed, CONFIG, VOCAB)

    feature_cols = [c for fam in families.values() for c in fam]
    earlier = df1.index[:-1]  # every row except the perturbed last week
    pd.testing.assert_frame_equal(
        df1.loc[earlier, feature_cols], df2.loc[earlier, feature_cols]
    )


def test_insufficient_history_flagged() -> None:
    base = _contiguous_city("Lahore", 10)
    df, _ = ft.engineer_features(base, CONFIG, VOCAB)
    # First min_history_weeks (5) rows flagged.
    assert df.loc[:4, "insufficient_lag_history"].all()
    assert not df.loc[5:, "insufficient_lag_history"].any()


def test_features_are_not_pure_raw_copies() -> None:
    base = _contiguous_city("Lahore", 10)
    df, families = ft.engineer_features(base, CONFIG, VOCAB)
    # Engineered families exist and are distinct from raw passthrough columns.
    assert families["lag"] and families["rolling"] and families["anomaly"]
    assert "temperature_lag2" in df.columns
    assert "precipitation_roll3" in df.columns
    assert "us_aqi_anom" in df.columns
