"""Tests for the M5.4/M5.5 dataset lineage ledger.

Covers: record construction (checksum reuse, row/column counts passed through
rather than recomputed), ledger load/save round-trip, and idempotent
upsert-on-rerun (matching manifest.json's established pattern).
"""

from __future__ import annotations

from pathlib import Path

from ml.pipelines.acquisition_base import sha256_file
from ml.pipelines.lineage import (
    SCHEMA_VERSION,
    build_record,
    load_ledger,
    record_lineage,
)


def _write_fake_parquet(path: Path, content: bytes = b"fake-parquet-bytes") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(content)


# --- build_record ------------------------------------------------------------


def test_build_record_reuses_sha256_file_not_a_second_hasher(tmp_path) -> None:
    output = tmp_path / "data" / "interim" / "weather" / "Lahore.parquet"
    _write_fake_parquet(output, b"identical-bytes")

    record = build_record(
        dataset="interim/weather/Lahore",
        output_path=output,
        data_dir=tmp_path / "data",
        sources=["open_meteo_weather"],
        input_artifacts=[tmp_path / "data" / "raw" / "weather" / "Lahore.json"],
        row_count=1424,
        column_count=7,
        pipeline_version="m5.5",
    )
    assert record.sha256 == sha256_file(output)


def test_build_record_uses_caller_supplied_counts_not_a_reread(tmp_path) -> None:
    output = tmp_path / "data" / "interim" / "weekly_base.parquet"
    _write_fake_parquet(output)

    record = build_record(
        dataset="weekly_base",
        output_path=output,
        data_dir=tmp_path / "data",
        sources=["open_meteo_weather", "open_meteo_air_quality"],
        input_artifacts=[],
        row_count=999,
        column_count=11,
        pipeline_version="m5.5",
    )
    assert record.row_count == 999
    assert record.column_count == 11
    assert record.schema_version == SCHEMA_VERSION


def test_build_record_relative_paths_are_posix_style(tmp_path) -> None:
    data_dir = tmp_path / "data"
    output = data_dir / "interim" / "weather" / "Lahore.parquet"
    _write_fake_parquet(output)
    raw_input = data_dir / "raw" / "weather" / "Lahore.json"

    record = build_record(
        dataset="interim/weather/Lahore", output_path=output, data_dir=data_dir,
        sources=["open_meteo_weather"], input_artifacts=[raw_input],
        row_count=1, column_count=1, pipeline_version="m5.5",
    )
    assert record.output_path == "interim/weather/Lahore.parquet"
    assert record.input_artifacts == ["raw/weather/Lahore.json"]


def test_build_record_carries_optional_references(tmp_path) -> None:
    output = tmp_path / "weekly_base.parquet"
    _write_fake_parquet(output)

    record = build_record(
        dataset="weekly_base", output_path=output, data_dir=tmp_path,
        sources=[], input_artifacts=[], row_count=0, column_count=0,
        pipeline_version="m5.5",
        quality_report_path=Path("reports/quality_weekly_base.json"),
        consumed_by="features.py (Module 6)",
    )
    assert record.quality_report_path == "reports/quality_weekly_base.json"
    assert record.consumed_by == "features.py (Module 6)"


def test_build_record_optional_references_default_to_none(tmp_path) -> None:
    output = tmp_path / "weekly_base.parquet"
    _write_fake_parquet(output)

    record = build_record(
        dataset="weekly_base", output_path=output, data_dir=tmp_path,
        sources=[], input_artifacts=[], row_count=0, column_count=0,
        pipeline_version="m5.5",
    )
    assert record.quality_report_path is None
    assert record.consumed_by is None


# --- ledger persistence -------------------------------------------------------


def test_load_ledger_returns_empty_shape_when_missing(tmp_path) -> None:
    ledger = load_ledger(tmp_path / "does_not_exist.json")
    assert ledger == {"version": 1, "entries": {}}


def test_record_lineage_round_trips_and_is_idempotent_keyed_by_output_path(tmp_path) -> None:
    ledger_path = tmp_path / "lineage.json"
    output = tmp_path / "data" / "interim" / "weather" / "Lahore.parquet"
    _write_fake_parquet(output)

    record = build_record(
        dataset="interim/weather/Lahore", output_path=output, data_dir=tmp_path / "data",
        sources=["open_meteo_weather"], input_artifacts=[], row_count=100, column_count=5,
        pipeline_version="m5.5",
    )
    record_lineage(ledger_path, record)

    loaded = load_ledger(ledger_path)
    assert list(loaded["entries"].keys()) == ["interim/weather/Lahore.parquet"]
    assert loaded["entries"]["interim/weather/Lahore.parquet"]["row_count"] == 100


def test_record_lineage_rerun_replaces_not_duplicates(tmp_path) -> None:
    ledger_path = tmp_path / "lineage.json"
    output = tmp_path / "data" / "interim" / "weather" / "Lahore.parquet"
    _write_fake_parquet(output, b"v1")

    first = build_record(
        dataset="interim/weather/Lahore", output_path=output, data_dir=tmp_path / "data",
        sources=["open_meteo_weather"], input_artifacts=[], row_count=100, column_count=5,
        pipeline_version="m5.5",
    )
    record_lineage(ledger_path, first)

    _write_fake_parquet(output, b"v2-different-bytes")
    second = build_record(
        dataset="interim/weather/Lahore", output_path=output, data_dir=tmp_path / "data",
        sources=["open_meteo_weather"], input_artifacts=[], row_count=101, column_count=5,
        pipeline_version="m5.5",
    )
    record_lineage(ledger_path, second)

    loaded = load_ledger(ledger_path)
    assert len(loaded["entries"]) == 1
    entry = loaded["entries"]["interim/weather/Lahore.parquet"]
    assert entry["row_count"] == 101
    assert entry["sha256"] == sha256_file(output)


def test_record_lineage_multiple_datasets_accumulate_distinct_entries(tmp_path) -> None:
    ledger_path = tmp_path / "lineage.json"
    data_dir = tmp_path / "data"
    lahore = data_dir / "interim" / "weather" / "Lahore.parquet"
    karachi = data_dir / "interim" / "weather" / "Karachi.parquet"
    _write_fake_parquet(lahore, b"lahore")
    _write_fake_parquet(karachi, b"karachi")

    for path, city in ((lahore, "Lahore"), (karachi, "Karachi")):
        record_lineage(ledger_path, build_record(
            dataset=f"interim/weather/{city}", output_path=path, data_dir=data_dir,
            sources=["open_meteo_weather"], input_artifacts=[], row_count=10, column_count=5,
            pipeline_version="m5.5",
        ))

    loaded = load_ledger(ledger_path)
    assert set(loaded["entries"].keys()) == {
        "interim/weather/Lahore.parquet", "interim/weather/Karachi.parquet",
    }
