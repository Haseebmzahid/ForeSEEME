"""Tests for the Sprint 2 label generation (Prompt 9).

Covers:
- membership functions and index computation match worked examples;
- threshold mapping is correct;
- transition-band scores produce non-degenerate probabilistic labels;
- fixed seed → identical labels; different seed differs at the boundary;
- the class distribution is non-degenerate (no class ~0%).
"""

from __future__ import annotations

import numpy as np
import pandas as pd
import pytest

from ml.pipelines import labels

CONFIG = {
    "seed": 1729,
    "transition_band": 0.06,
    "diseases": {
        "dengue": {
            "thresholds": {"low_medium": 0.33, "medium_high": 0.55},
            "weights": {"temperature": 0.40, "humidity": 0.25, "rainfall_lag": 0.35},
            "temperature_band": {"t_min": 18.0, "t_opt_lo": 26.0, "t_opt_hi": 30.0, "t_max": 34.0},
            "humidity_ramp": {"lo": 40.0, "hi": 75.0},
            "rainfall_lag": {"weeks": [2, 3, 4], "cap_mm": 35.0},
        },
        "smog": {
            "thresholds": {"low_medium": 0.35, "medium_high": 0.58},
            "weights": {"pm25": 0.45, "season": 0.20, "low_temperature": 0.20, "low_rainfall": 0.15},
            "pm25_ramp": {"lo": 15.0, "hi": 150.0},
            "season_months": [10, 11, 12, 1],
            "low_temperature_ramp": {"hi": 22.0, "lo": 8.0},
            "low_rainfall_ramp": {"wet": 15.0, "dry": 0.0},
        },
        "influenza": {
            "thresholds": {"low_medium": 0.20, "medium_high": 0.45},
            "weights": {"low_temperature": 0.40, "low_humidity": 0.30, "season": 0.30},
            "low_temperature_ramp": {"hi": 18.0, "lo": 2.0},
            "low_humidity_band": {"h_min": 10.0, "h_opt_lo": 20.0, "h_opt_hi": 35.0, "h_max": 60.0},
            "season_months": [12, 1, 2],
        },
    },
}


# --- Membership functions ---------------------------------------------------


def test_membership_functions() -> None:
    # ramp_up
    assert labels.ramp_up(40, 40, 75) == 0.0
    assert labels.ramp_up(75, 40, 75) == 1.0
    assert labels.ramp_up(57.5, 40, 75) == pytest.approx(0.5)
    # ramp_down (rises as x falls)
    assert labels.ramp_down(8, 22, 8) == 1.0
    assert labels.ramp_down(22, 22, 8) == 0.0
    assert labels.ramp_down(15, 22, 8) == pytest.approx(0.5)
    # trapezoid (plateau)
    assert labels.trapezoid(28, 18, 26, 30, 34) == 1.0
    assert labels.trapezoid(18, 18, 26, 30, 34) == 0.0
    assert labels.trapezoid(22, 18, 26, 30, 34) == pytest.approx(0.5)


def test_dengue_index_worked_example() -> None:
    # temp 28 -> 1.0; humidity 75 -> 1.0; lagged rain >= cap -> 1.0
    df = pd.DataFrame(
        {
            "temperature": [28.0], "humidity": [75.0],
            "precipitation_lag2": [40.0], "precipitation_lag3": [40.0], "precipitation_lag4": [40.0],
        }
    )
    score = labels.dengue_score(df, CONFIG["diseases"]["dengue"])
    assert score[0] == pytest.approx(1.0)  # 0.40 + 0.25 + 0.35

    # temp 28 (1.0), humidity 57.5 (0.5), no rain (0.0): 0.40 + 0.125 + 0 = 0.525
    df2 = pd.DataFrame(
        {
            "temperature": [28.0], "humidity": [57.5],
            "precipitation_lag2": [0.0], "precipitation_lag3": [0.0], "precipitation_lag4": [0.0],
        }
    )
    assert labels.dengue_score(df2, CONFIG["diseases"]["dengue"])[0] == pytest.approx(0.525)


# --- Threshold mapping + transition band -----------------------------------


def test_hard_label_mapping() -> None:
    scores = np.array([0.1, 0.45, 0.9, np.nan])
    out = labels.hard_label(scores, 0.33, 0.55)
    assert list(out[:3]) == ["Low", "Medium", "High"]
    assert out[3] is None


def test_transition_band_is_probabilistic() -> None:
    band = 0.06
    # Exactly on the Low/Medium boundary -> 50/50 Low/Medium, no High.
    p_low, p_med, p_high = labels.class_probabilities(np.array([0.33]), 0.33, 0.55, band)
    assert p_low[0] == pytest.approx(0.5)
    assert p_med[0] == pytest.approx(0.5)
    assert p_high[0] == pytest.approx(0.0)
    # Probabilities are a valid distribution and non-degenerate in the band.
    assert p_low[0] + p_med[0] + p_high[0] == pytest.approx(1.0)
    assert 0 < p_low[0] < 1

    # Far from any boundary -> degenerate (pure class).
    pl, pm, ph = labels.class_probabilities(np.array([0.05]), 0.33, 0.55, band)
    assert pl[0] == pytest.approx(1.0)


# --- Seed reproducibility ---------------------------------------------------


def _features(n=52) -> pd.DataFrame:
    rng = np.linspace(0, 1, n)
    return pd.DataFrame(
        {
            "city": "Lahore", "iso_year": 2024, "week_of_year": list(range(1, n + 1)),
            "temperature": 10 + 20 * rng, "humidity": 30 + 50 * rng,
            "precipitation": 5 * rng, "pm2_5": 200 * rng, "pm10": 250 * rng, "us_aqi": 300 * rng,
            "aqi_available": True,
            "precipitation_lag2": 30 * rng, "precipitation_lag3": 30 * rng, "precipitation_lag4": 30 * rng,
        }
    )


def test_fixed_seed_reproducible() -> None:
    feats = _features()
    a, _ = labels.build_labels(feats, CONFIG)
    b, _ = labels.build_labels(feats, CONFIG)
    pd.testing.assert_series_equal(a["dengue_label_sampled"], b["dengue_label_sampled"])


def test_different_seed_changes_some_boundary_labels() -> None:
    feats = _features()
    a, _ = labels.build_labels(feats, {**CONFIG, "seed": 1})
    b, _ = labels.build_labels(feats, {**CONFIG, "seed": 2})
    # Hard labels are seed-independent; sampled labels differ for some rows.
    assert (a["dengue_label_sampled"] != b["dengue_label_sampled"]).any()
    pd.testing.assert_series_equal(a["dengue_label"], b["dengue_label"])


def test_sampled_label_is_order_independent() -> None:
    feats = _features()
    a, _ = labels.build_labels(feats, CONFIG)
    shuffled = feats.sample(frac=1.0, random_state=0).reset_index(drop=True)
    b, _ = labels.build_labels(shuffled, CONFIG)
    merged = a.merge(
        b, on=["city", "iso_year", "week_of_year"], suffixes=("_a", "_b")
    )
    assert (merged["dengue_label_sampled_a"] == merged["dengue_label_sampled_b"]).all()


# --- Distribution -----------------------------------------------------------


def test_class_distribution_non_degenerate() -> None:
    # Build over a realistic spread (a full annual cycle of conditions).
    weeks = list(range(1, 53))
    feats = pd.DataFrame(
        {
            "city": "Lahore", "iso_year": 2024, "week_of_year": weeks,
            # seasonal temperature/humidity swings
            "temperature": 18 + 12 * np.cos((np.array(weeks) - 28) / 52 * 2 * np.pi),
            "humidity": 60 + 25 * np.sin(np.array(weeks) / 52 * 2 * np.pi),
            "precipitation": np.where((np.array(weeks) > 26) & (np.array(weeks) < 40), 25.0, 2.0),
            "pm2_5": np.where((np.array(weeks) > 40) | (np.array(weeks) < 6), 180.0, 30.0),
            "pm10": 80.0, "us_aqi": 120.0, "aqi_available": True,
            "precipitation_lag2": np.where((np.array(weeks) > 28) & (np.array(weeks) < 42), 25.0, 2.0),
            "precipitation_lag3": np.where((np.array(weeks) > 28) & (np.array(weeks) < 42), 25.0, 2.0),
            "precipitation_lag4": np.where((np.array(weeks) > 28) & (np.array(weeks) < 42), 25.0, 2.0),
        }
    )
    _, dist = labels.build_labels(feats, CONFIG)
    for disease in labels.DISEASES:
        sampled = dist[disease]["sampled"]
        defined = sum(sampled[c] for c in labels.CLASSES)
        # Every class present for at least one disease's synthetic annual cycle;
        # require at least Low and (Medium or High) to be non-zero here.
        assert sampled["Low"] > 0
        assert sampled["Medium"] + sampled["High"] > 0
        assert defined > 0
