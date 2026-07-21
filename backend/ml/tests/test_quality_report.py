"""Tests for the M5.2 data-quality observability layer.

Covers: stage aggregation from already-computed acquisition/cleaning/merge
figures (no fabricated metrics), report-level rollups (rows/warnings/duration),
text rendering, and the JSON save/load round-trip including idempotent
stage-replacement across repeated runs.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field

from ml.pipelines.quality_report import (
    PIPELINE_VERSION,
    QualityReport,
    StageQuality,
    from_acquisition,
    from_cleaning,
    from_merge,
    new_report,
)


# --- Fakes mirroring the real result/stats shapes (duck-typed, no import cycle) --


@dataclass
class FakeAcquisitionResult:
    clipped: bool = False
    from_cache: bool = True
    missing_variables: list[str] = field(default_factory=list)
    structural_issues: list[str] = field(default_factory=list)


@dataclass
class FakeAqiAcquisitionResult(FakeAcquisitionResult):
    partial_coverage: bool = False


@dataclass
class FakeVariableStats:
    missing: int = 0
    out_of_range: int = 0
    interpolated: int = 0


@dataclass
class FakeCityStats:
    days: int
    variables: list[FakeVariableStats] = field(default_factory=list)
    aqi_available_days: int | None = None


# --- from_acquisition ---------------------------------------------------------


def test_from_acquisition_counts_cache_hits_and_downloads() -> None:
    results = [
        FakeAcquisitionResult(from_cache=True),
        FakeAcquisitionResult(from_cache=False),
        FakeAcquisitionResult(from_cache=True),
    ]
    stage = from_acquisition(results, duration_seconds=1.5)
    assert stage.stage == "acquisition"
    assert stage.detail["cities"] == 3
    assert stage.detail["cache_hits"] == 2
    assert stage.detail["downloaded"] == 1
    assert stage.duration_seconds == 1.5


def test_from_acquisition_sums_missing_and_structural_occurrences() -> None:
    results = [
        FakeAcquisitionResult(missing_variables=["precipitation"], structural_issues=[]),
        FakeAcquisitionResult(missing_variables=[], structural_issues=["temperature: length_mismatch — x"]),
    ]
    stage = from_acquisition(results, duration_seconds=0.1)
    assert stage.detail["missing_variable_occurrences"] == 1
    assert stage.detail["structural_issue_occurrences"] == 1
    assert stage.warnings == 2  # 0 clipped + 1 missing + 1 structural


def test_from_acquisition_tracks_partial_coverage_only_when_present() -> None:
    weather_like = [FakeAcquisitionResult(), FakeAcquisitionResult()]
    stage = from_acquisition(weather_like, duration_seconds=0.1)
    assert "partial_coverage_cities" not in stage.detail

    aqi_like = [FakeAqiAcquisitionResult(partial_coverage=True), FakeAqiAcquisitionResult()]
    stage_aqi = from_acquisition(aqi_like, duration_seconds=0.1)
    assert stage_aqi.detail["partial_coverage_cities"] == 1
    assert stage_aqi.warnings == 1


def test_from_acquisition_clipped_windows_count_as_warnings() -> None:
    results = [FakeAcquisitionResult(clipped=True), FakeAcquisitionResult(clipped=False)]
    stage = from_acquisition(results, duration_seconds=0.1)
    assert stage.detail["clipped_windows"] == 1
    assert stage.warnings == 1


# --- from_cleaning -------------------------------------------------------------


def test_from_cleaning_sums_rows_and_cell_counts() -> None:
    stats = [
        FakeCityStats(days=100, variables=[
            FakeVariableStats(missing=2, out_of_range=1, interpolated=1),
            FakeVariableStats(missing=0, out_of_range=0, interpolated=0),
        ]),
        FakeCityStats(days=100, variables=[
            FakeVariableStats(missing=5, out_of_range=0, interpolated=3),
        ]),
    ]
    stage = from_cleaning(stats, duration_seconds=2.0)
    assert stage.stage == "cleaning"
    assert stage.rows == 200
    assert stage.detail["rows_processed"] == 200
    assert stage.detail["missing_cells"] == 7
    assert stage.detail["out_of_range_cells"] == 1
    assert stage.detail["interpolated_cells"] == 4
    assert stage.warnings == 1  # out-of-range only


def test_from_cleaning_reports_aqi_available_days_only_when_present() -> None:
    weather_stats = [FakeCityStats(days=10, variables=[])]
    assert "aqi_available_days" not in from_cleaning(weather_stats, duration_seconds=0.1).detail

    aqi_stats = [FakeCityStats(days=10, variables=[], aqi_available_days=7)]
    stage = from_cleaning(aqi_stats, duration_seconds=0.1)
    assert stage.detail["aqi_available_days"] == 7


# --- from_merge ------------------------------------------------------------


def test_from_merge_wraps_precomputed_figures_without_recomputation() -> None:
    stage = from_merge(
        rows=1000, cities=5, duplicate_keys=0,
        column_missing_pct={"pm2_5": 12.5}, duration_seconds=0.8,
    )
    assert stage.stage == "merge"
    assert stage.rows == 1000
    assert stage.detail["cities"] == 5
    assert stage.detail["duplicate_keys"] == 0
    assert stage.detail["column_missing_pct"]["pm2_5"] == 12.5
    assert stage.warnings == 0


def test_from_merge_duplicate_keys_count_as_warnings() -> None:
    stage = from_merge(
        rows=1000, cities=5, duplicate_keys=3,
        column_missing_pct={}, duration_seconds=0.1,
    )
    assert stage.warnings == 3


# --- QualityReport rollups ---------------------------------------------------


def test_report_rollups_across_stages() -> None:
    report = new_report("open_meteo_weather")
    report.add_stage(StageQuality(stage="acquisition", duration_seconds=1.0, warnings=1, rows=None))
    report.add_stage(StageQuality(stage="cleaning", duration_seconds=2.0, warnings=2, rows=500))

    assert report.total_duration_seconds == 3.0
    assert report.warning_count == 3
    assert report.rows_processed == 500  # only cleaning has a row count
    assert report.error_count == 0
    assert report.pipeline_version == PIPELINE_VERSION


def test_add_stage_replaces_same_named_stage_not_accumulates() -> None:
    report = new_report("open_meteo_weather")
    report.add_stage(StageQuality(stage="acquisition", duration_seconds=1.0, warnings=1, rows=None))
    report.add_stage(StageQuality(stage="acquisition", duration_seconds=9.0, warnings=9, rows=None))

    assert len(report.stages) == 1
    assert report.stages[0].duration_seconds == 9.0
    assert report.warning_count == 9


def test_render_text_contains_key_figures() -> None:
    report = new_report("open_meteo_weather")
    report.add_stage(StageQuality(
        stage="cleaning", duration_seconds=1.23, warnings=2, rows=350,
        detail={"missing_cells": 4},
    ))
    text = report.render_text()
    assert "open_meteo_weather" in text
    assert "Rows processed: 350" in text
    assert "Warnings: 2" in text
    assert "missing_cells: 4" in text


# --- Persistence: atomic JSON, idempotent stage-merge across runs -----------


def test_save_and_load_round_trip(tmp_path) -> None:
    path = tmp_path / "quality_open_meteo_weather.json"
    report = new_report("open_meteo_weather")
    report.add_stage(StageQuality(stage="acquisition", duration_seconds=1.0, warnings=1, rows=None))
    report.save(path)

    loaded = QualityReport.load(path)
    assert loaded is not None
    assert loaded.source == "open_meteo_weather"
    assert len(loaded.stages) == 1
    assert loaded.stages[0].stage == "acquisition"

    raw = json.loads(path.read_text(encoding="utf-8"))
    assert raw["pipeline_version"] == PIPELINE_VERSION


def test_save_merges_new_stage_onto_existing_file_stages(tmp_path) -> None:
    """Simulates acquire_weather then clean running as separate processes."""
    path = tmp_path / "quality_open_meteo_weather.json"

    acquisition_run = new_report("open_meteo_weather")
    acquisition_run.add_stage(
        StageQuality(stage="acquisition", duration_seconds=1.0, warnings=0, rows=None)
    )
    acquisition_run.save(path)

    cleaning_run = new_report("open_meteo_weather")
    cleaning_run.add_stage(
        StageQuality(stage="cleaning", duration_seconds=2.0, warnings=1, rows=100)
    )
    cleaning_run.save(path)

    loaded = QualityReport.load(path)
    assert loaded is not None
    assert {s.stage for s in loaded.stages} == {"acquisition", "cleaning"}
    assert loaded.rows_processed == 100
    assert loaded.warning_count == 1


def test_save_replaces_stage_on_rerun_without_duplicating(tmp_path) -> None:
    path = tmp_path / "quality_open_meteo_weather.json"
    first = new_report("open_meteo_weather")
    first.add_stage(StageQuality(stage="cleaning", duration_seconds=1.0, warnings=5, rows=100))
    first.save(path)

    rerun = new_report("open_meteo_weather")
    rerun.add_stage(StageQuality(stage="cleaning", duration_seconds=1.5, warnings=0, rows=100))
    rerun.save(path)

    loaded = QualityReport.load(path)
    assert loaded is not None
    assert len(loaded.stages) == 1
    assert loaded.stages[0].warnings == 0


def test_load_returns_none_for_missing_file(tmp_path) -> None:
    assert QualityReport.load(tmp_path / "does_not_exist.json") is None
