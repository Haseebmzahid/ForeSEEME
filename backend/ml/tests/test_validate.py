"""Tests for the Sprint 2 validation gate (Prompt 10).

Covers:
- the schema rejects an out-of-range / wrong-type / invalid-label row;
- the temporal split has no time overlap between train and test;
- the class-coverage check requires all classes in both splits;
- contamination and feature-leakage checks catch injected problems;
- the frozen manifest hash is stable across re-runs.
"""

from __future__ import annotations

import numpy as np
import pandas as pd

from ml.pipelines import validate

VOCAB = ["Islamabad", "Rawalpindi", "Lahore", "Karachi", "Peshawar"]


def _valid_df() -> pd.DataFrame:
    base: dict = {
        "city": ["Lahore", "Lahore"],
        "iso_year": [2024, 2024],
        "week_of_year": [10, 11],
        "temperature": [25.0, 26.0],
        "humidity": [60.0, 62.0],
        "precipitation": [5.0, 1.0],
        "pm2_5": [40.0, 45.0],
        "pm10": [60.0, 65.0],
        "us_aqi": [110.0, 120.0],
        "aqi_available": [True, True],
        "temperature_lag1": [24.0, 25.0],
        "temperature_roll3": [23.0, 24.0],
        "temperature_anom": [1.0, np.nan],
        "week_sin": [0.5, 0.6],
        "week_cos": [0.5, 0.4],
        "insufficient_lag_history": [False, False],  # bool flag must be tolerated
    }
    for c in VOCAB:
        base[f"city_{c}"] = [1 if c == "Lahore" else 0] * 2
    for d in ("dengue", "smog", "influenza"):
        base[f"{d}_score"] = [0.5, 0.6]
        base[f"{d}_prob_low"] = [0.3, 0.2]
        base[f"{d}_prob_medium"] = [0.4, 0.3]
        base[f"{d}_prob_high"] = [0.3, 0.5]
        base[f"{d}_label"] = ["Medium", "High"]
        base[f"{d}_label_sampled"] = ["Medium", "High"]
    return pd.DataFrame(base)


def _schema():
    df = _valid_df()
    return validate.build_schema(df, VOCAB)


# --- Schema ----------------------------------------------------------------


def test_schema_accepts_valid_data() -> None:
    df = _valid_df()
    assert validate.check_schema(df, _schema()).passed is True


def test_schema_rejects_out_of_range() -> None:
    df = _valid_df()
    df.loc[0, "humidity"] = 150.0  # impossible
    assert validate.check_schema(df, _schema()).passed is False


def test_schema_rejects_invalid_label() -> None:
    df = _valid_df()
    df.loc[0, "dengue_label"] = "Extreme"  # not in {Low, Medium, High}
    assert validate.check_schema(df, _schema()).passed is False


def test_schema_rejects_wrong_type() -> None:
    df = _valid_df()
    df["temperature"] = df["temperature"].astype(object)
    df.loc[0, "temperature"] = "hot"  # string in a float column
    assert validate.check_schema(df, _schema()).passed is False


def test_schema_rejects_duplicate_key() -> None:
    df = _valid_df()
    df.loc[1, "week_of_year"] = 10  # duplicate (Lahore, 2024, 10)
    assert validate.check_schema(df, _schema()).passed is False


# --- Temporal split --------------------------------------------------------


def _timeseries(n_weeks: int) -> pd.DataFrame:
    return pd.DataFrame(
        {
            "city": "Lahore",
            "iso_year": 2024,
            "week_of_year": list(range(1, n_weeks + 1)),
        }
    )


def test_temporal_split_has_no_overlap() -> None:
    df = _timeseries(10)
    train, test, info = validate.temporal_split(df, test_weeks=3)
    assert len(train) == 7 and len(test) == 3
    assert validate.check_temporal_split(train, test).passed is True
    assert validate.check_contamination(train, test).passed is True
    # Latest train week strictly precedes earliest test week.
    assert train["week_of_year"].max() < test["week_of_year"].min()


def test_contamination_detected() -> None:
    train = _timeseries(5)
    test = _timeseries(5)  # identical weeks -> fully contaminated
    assert validate.check_contamination(train, test).passed is False


# --- Class coverage --------------------------------------------------------


def _labelled(weeks: list[int], labels: dict[str, list[str]]) -> pd.DataFrame:
    df = pd.DataFrame({"city": "Lahore", "iso_year": 2024, "week_of_year": weeks})
    for disease in ("dengue", "smog", "influenza"):
        df[f"{disease}_label"] = labels[disease]
        df[f"{disease}_label_sampled"] = labels[disease]
    return df


def test_all_classes_required_in_both_splits() -> None:
    train = _labelled([1, 2, 3], {d: ["Low", "Medium", "High"] for d in ("dengue", "smog", "influenza")})
    test = _labelled([4, 5, 6], {d: ["Low", "Medium", "High"] for d in ("dengue", "smog", "influenza")})
    assert validate.check_class_distribution(train, test).passed is True

    # Drop High from test for dengue -> must fail.
    test_bad = _labelled([4, 5, 6], {
        "dengue": ["Low", "Medium", "Low"],
        "smog": ["Low", "Medium", "High"],
        "influenza": ["Low", "Medium", "High"],
    })
    assert validate.check_class_distribution(train, test_bad).passed is False


# --- Feature leakage -------------------------------------------------------


def test_feature_leakage_check_catches_future_value() -> None:
    df = pd.DataFrame(
        {
            "city": "Lahore", "iso_year": 2024, "week_of_year": list(range(1, 6)),
            "temperature": [10.0, 20.0, 30.0, 40.0, 50.0],
        }
    )
    feat_cfg = {"lags": {"variables": ["temperature"], "weeks": [1]},
                "rolling": {"variables": [], "windows": [], "shift": 1}}
    # Correct causal lag1 = previous week.
    df["temperature_lag1"] = df["temperature"].shift(1)
    assert validate.check_feature_leakage(df, feat_cfg).passed is True

    # Inject a FUTURE value (lag1 = next week) -> must be caught.
    leaky = df.copy()
    leaky["temperature_lag1"] = leaky["temperature"].shift(-1)
    assert validate.check_feature_leakage(leaky, feat_cfg).passed is False


# --- Manifest stability ----------------------------------------------------


def test_manifest_hash_stable_across_runs(tmp_path) -> None:
    train = _valid_df()
    test = _valid_df()
    info = {"split_iso_year": 2025, "split_week_of_year": 27}

    m1 = validate.freeze(train, test, info, 0, [], tmp_path / "a")
    m2 = validate.freeze(train, test, info, 0, [], tmp_path / "b")
    assert m1["train_sha256"] == m2["train_sha256"]
    assert m1["test_sha256"] == m2["test_sha256"]
    # And the manifest records the hashes.
    assert (tmp_path / "a" / "processed" / "split_manifest.json").exists()
