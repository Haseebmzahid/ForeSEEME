"""Tests for the shared adapter helpers (M5.1).

Covers the logic extracted out of ``acquire_weather``/``acquire_aqi`` into
``acquisition_common`` (YAML/JSON loading, variable-spec derivation, coverage
clipping, variable presence) plus the new structural validator that checks a
raw response's internal consistency before it is trusted downstream.
"""

from __future__ import annotations

import json

import pytest

from ml.pipelines.acquisition_base import Window
from ml.pipelines.acquisition_common import (
    VariableSpec,
    check_variables,
    clip_to_coverage,
    load_cities,
    load_yaml,
    read_raw_json,
    validate_payload_structure,
    variable_specs,
)

SOURCE = {
    "granularity": "daily",
    "variables": {
        "temperature": {
            "api_param": "temperature_2m_mean",
            "acquire_param": "temperature_2m_mean",
            "acquire_granularity": "daily",
            "units": "°C",
        },
        "humidity": {
            "api_param": "relative_humidity_2m_mean",
            "acquire_param": "relative_humidity_2m",
            "acquire_granularity": "hourly",
            "units": "%",
        },
    },
}


# --- YAML / raw-file loading -------------------------------------------------


def test_load_yaml_and_load_cities(tmp_path) -> None:
    path = tmp_path / "cities.yaml"
    path.write_text(
        "cities:\n  - name: Lahore\n    lat: 31.5\n    lon: 74.3\n",
        encoding="utf-8",
    )
    assert load_yaml(path)["cities"][0]["name"] == "Lahore"
    assert load_cities(path) == [{"name": "Lahore", "lat": 31.5, "lon": 74.3}]


def test_read_raw_json(tmp_path) -> None:
    path = tmp_path / "raw.json"
    path.write_text(json.dumps({"a": 1}), encoding="utf-8")
    assert read_raw_json(path) == {"a": 1}


# --- Variable specs -----------------------------------------------------------


def test_variable_specs_defaults_granularity_per_variable() -> None:
    specs = variable_specs(SOURCE, default_granularity="daily")
    by_name = {s.name: s for s in specs}
    assert by_name["temperature"].granularity == "daily"
    assert by_name["humidity"].granularity == "hourly"
    assert by_name["humidity"].api_param == "relative_humidity_2m"


def test_variable_specs_falls_back_to_default_granularity() -> None:
    source = {
        "variables": {
            "pm2_5": {"api_param": "pm2_5", "units": "µg/m³"},
        }
    }
    specs = variable_specs(source, default_granularity="hourly")
    assert specs[0].granularity == "hourly"


# --- Coverage clipping ----------------------------------------------------


def test_clip_to_coverage_clips_both_bounds() -> None:
    window = Window("2010-01-01", "2030-01-01")
    coverage = {"earliest_confirmed": "2022-08-05", "latest_confirmed": "2026-06-28"}
    clipped, was_clipped = clip_to_coverage(window, coverage)
    assert was_clipped is True
    assert clipped == Window("2022-08-05", "2026-06-28")


def test_clip_to_coverage_noop_when_within_bounds() -> None:
    window = Window("2023-01-01", "2023-06-01")
    coverage = {"earliest_confirmed": "2022-08-05", "latest_confirmed": "2026-06-28"}
    clipped, was_clipped = clip_to_coverage(window, coverage)
    assert was_clipped is False
    assert clipped == window


@pytest.mark.parametrize("window", [
    Window("2026-07-20", "2026-10-12"),
    Window("2000-01-01", "2000-02-01"),
    Window("2026-06-28", "2026-06-01"),
])
def test_clip_to_coverage_rejects_empty_intersection(window):
    with pytest.raises(ValueError, match="does not overlap"):
        clip_to_coverage(window, {"earliest_confirmed": "2022-08-05",
                                  "latest_confirmed": "2026-06-28"})


# --- Variable presence ------------------------------------------------------


def test_check_variables_splits_present_and_missing() -> None:
    specs = variable_specs(SOURCE, default_granularity="daily")
    payload = {
        "daily": {"time": ["2022-08-05"], "temperature_2m_mean": [30.0]},
        "hourly": {},  # humidity absent
    }
    present, missing = check_variables(payload, specs)
    assert present == ["temperature"]
    assert missing == ["humidity"]


# --- Structural validation ---------------------------------------------------


def test_validate_payload_structure_clean_payload_has_no_issues() -> None:
    specs = variable_specs(SOURCE, default_granularity="daily")
    payload = {
        "daily": {"time": ["2022-08-05", "2022-08-06"], "temperature_2m_mean": [30.0, 31.0]},
        "hourly": {
            "time": ["2022-08-05T00:00", "2022-08-05T01:00"],
            "relative_humidity_2m": [55, 57],
        },
    }
    assert validate_payload_structure(payload, specs) == []


def test_validate_payload_structure_flags_length_mismatch() -> None:
    specs = [VariableSpec(name="temperature", api_param="temperature_2m_mean",
                           granularity="daily", units="°C")]
    payload = {"daily": {"time": ["2022-08-05", "2022-08-06"], "temperature_2m_mean": [30.0]}}
    issues = validate_payload_structure(payload, specs)
    assert len(issues) == 1
    assert issues[0].kind == "length_mismatch"
    assert issues[0].variable == "temperature"


def test_validate_payload_structure_flags_invalid_timestamp() -> None:
    specs = [VariableSpec(name="temperature", api_param="temperature_2m_mean",
                           granularity="daily", units="°C")]
    payload = {"daily": {"time": ["2022-08-05", "not-a-date"], "temperature_2m_mean": [30.0, 31.0]}}
    issues = validate_payload_structure(payload, specs)
    assert len(issues) == 1
    assert issues[0].kind == "invalid_timestamp"
    assert "1 of 2" in issues[0].detail


def test_validate_payload_structure_skips_absent_variables() -> None:
    """A missing variable is check_variables' concern, not a structural issue."""
    specs = [VariableSpec(name="humidity", api_param="relative_humidity_2m",
                           granularity="hourly", units="%")]
    payload = {"hourly": {}}
    assert validate_payload_structure(payload, specs) == []


def test_payload_issue_str_is_human_readable() -> None:
    specs = [VariableSpec(name="temperature", api_param="temperature_2m_mean",
                           granularity="daily", units="°C")]
    payload = {"daily": {"time": ["2022-08-05"], "temperature_2m_mean": [30.0, 31.0]}}
    issue = validate_payload_structure(payload, specs)[0]
    assert str(issue) == (
        "temperature: length_mismatch — time has 1 points, "
        "temperature_2m_mean has 2 points"
    )
