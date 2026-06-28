"""Tests for the Sprint 2 AQI acquisition adapter (Prompt 4).

Fully mocked HTTP (no network, no sleep). Verifies:
- one raw file per city, each containing the expected AQI variables;
- the requested window is clipped to AQI coverage (no back-filling);
- a partial-coverage city is handled, recorded, and logged (not a failure);
- the exact covered window is written to the sidecar;
- a manifest entry is created per city;
- a re-run is a pure cache no-op.
"""

from __future__ import annotations

import json
import logging

from ml.pipelines import acquire_aqi as aq
from ml.pipelines.acquisition_base import (
    AcquisitionBase,
    CachePolicy,
    PipelineConfig,
    RateLimit,
    RetryPolicy,
    Window,
    load_manifest,
)

# AQI coverage is narrower than this requested window — clipping must kick in.
WIDE_WINDOW = Window("2020-01-01", "2026-06-28")
AQI_START = "2022-08-05"
AQI_END = "2026-06-28"
FIXED_NOW = "2026-06-28T00:00:00+00:00"

SOURCE = {
    "base_url": "https://aqi.example.test/v1/air-quality",
    "granularity": "hourly",
    "coverage": {"earliest_confirmed": AQI_START, "latest_confirmed": AQI_END},
    "variables": {
        "pm2_5": {"api_param": "pm2_5", "units": "µg/m³"},
        "pm10": {"api_param": "pm10", "units": "µg/m³"},
        "us_aqi": {"api_param": "us_aqi", "units": "US AQI"},
    },
}

CITIES = [
    {"name": "Islamabad", "lat": 33.6844, "lon": 73.0479},
    {"name": "Rawalpindi", "lat": 33.5651, "lon": 73.0169},
    {"name": "Lahore", "lat": 31.5497, "lon": 74.3436},
    {"name": "Karachi", "lat": 24.8607, "lon": 67.0011},
    {"name": "Peshawar", "lat": 34.0151, "lon": 71.5249},
]


def _full_payload() -> bytes:
    """Two days, all variables non-null across the window start."""
    times = [f"{AQI_START}T{h:02d}:00" for h in range(24)] + [
        f"2022-08-06T{h:02d}:00" for h in range(24)
    ]
    n = len(times)
    body = {
        "hourly": {
            "time": times,
            "pm2_5": [40.0] * n,
            "pm10": [70.0] * n,
            "us_aqi": [110.0] * n,
        }
    }
    return json.dumps(body).encode()


def _partial_payload() -> bytes:
    """Data null on the first day, present on the second — a partial-coverage city."""
    day1 = [f"{AQI_START}T{h:02d}:00" for h in range(24)]
    day2 = [f"2022-08-06T{h:02d}:00" for h in range(24)]
    times = day1 + day2
    nulls = [None] * 24
    vals = [50.0] * 24
    body = {
        "hourly": {
            "time": times,
            "pm2_5": nulls + vals,
            "pm10": nulls + vals,
            "us_aqi": nulls + vals,
        }
    }
    return json.dumps(body).encode()


class FakeResponse:
    def __init__(self, status_code: int, content: bytes):
        self.status_code = status_code
        self.content = content

    def json(self):
        return json.loads(self.content)


class FakeGetter:
    def __init__(self, content: bytes | None, status: int = 200):
        self._content = content
        self._status = status
        self.calls: list[dict] = []

    def __call__(self, url, params):
        self.calls.append(dict(params))
        if self._content is None:
            raise AssertionError("network called on an expected cache hit")
        return FakeResponse(self._status, self._content)


def _config(window: Window) -> PipelineConfig:
    return PipelineConfig(
        window=window,
        cache=CachePolicy(reuse_on_hash_match=True, verify_hash=True),
        retry=RetryPolicy(
            max_attempts=3,
            backoff_initial_seconds=0.0,
            backoff_factor=2.0,
            retry_on_status=(429, 500, 502, 503, 504),
            timeout_seconds=5.0,
        ),
        rate_limit=RateLimit(min_interval_seconds=0.0),
        log_level="INFO",
    )


def _client(tmp_path, getter, window=WIDE_WINDOW) -> AcquisitionBase:
    return AcquisitionBase(
        config=_config(window),
        get=getter,
        sleep=lambda _s: None,
        now=lambda: FIXED_NOW,
        data_dir=tmp_path,
        manifest_path=tmp_path / "raw" / "manifest.json",
    )


# --- Tests -----------------------------------------------------------------


def test_one_raw_file_per_city_with_expected_variables(tmp_path) -> None:
    getter = FakeGetter(_full_payload())
    results = aq.acquire_all(_client(tmp_path, getter), source=SOURCE, cities=CITIES)

    assert len(results) == 5
    assert len(getter.calls) == 5
    for city in CITIES:
        raw = tmp_path / "raw" / "aqi" / f"{city['name']}.json"
        assert raw.exists()
        body = json.loads(raw.read_text())
        for var in ("pm2_5", "pm10", "us_aqi"):
            assert var in body["hourly"]
    for r in results:
        assert set(r.present_variables) == {"pm2_5", "pm10", "us_aqi"}


def test_window_clipped_to_aqi_coverage(tmp_path, caplog) -> None:
    getter = FakeGetter(_full_payload())
    with caplog.at_level(logging.WARNING, logger="foreseeme.ml.acquire_aqi"):
        results = aq.acquire_all(_client(tmp_path, getter), source=SOURCE, cities=CITIES)

    # Requested 2020 start, but AQI coverage begins 2022-08-05 — never request earlier.
    for params in getter.calls:
        assert params["start_date"] == AQI_START
        assert params["end_date"] == AQI_END
    for r in results:
        assert r.clipped is True
        assert r.effective_window == (AQI_START, AQI_END)
    assert any("window_clipped_to_coverage" in rec.message for rec in caplog.records)


def test_partial_coverage_city_recorded_and_logged(tmp_path, caplog) -> None:
    getter = FakeGetter(_partial_payload())
    # Use a tight window so the second day is the only covered day.
    window = Window(AQI_START, "2022-08-06")
    with caplog.at_level(logging.WARNING, logger="foreseeme.ml.acquire_aqi"):
        results = aq.acquire_all(
            _client(tmp_path, getter, window=window), source=SOURCE, cities=CITIES
        )

    for r in results:
        assert r.partial_coverage is True
        # Data only exists from the second day onward — recorded exactly.
        assert r.covered_window == ("2022-08-06", "2022-08-06")

    meta = json.loads((tmp_path / "raw" / "aqi" / "Lahore.meta.json").read_text())
    assert meta["partial_coverage"] is True
    assert meta["covered_window"] == {"start": "2022-08-06", "end": "2022-08-06"}
    assert meta["variables"][0]["coverage"]["earliest"] == "2022-08-06"
    assert any("aqi_partial_coverage" in rec.message for rec in caplog.records)


def test_exact_covered_window_in_sidecar(tmp_path) -> None:
    getter = FakeGetter(_full_payload())
    aq.acquire_all(
        _client(tmp_path, getter, window=Window(AQI_START, "2022-08-06")),
        source=SOURCE,
        cities=CITIES,
    )
    meta = json.loads((tmp_path / "raw" / "aqi" / "Karachi.meta.json").read_text())
    assert meta["covered_window"] == {"start": AQI_START, "end": "2022-08-06"}
    assert meta["partial_coverage"] is False
    assert meta["note"].startswith("Raw, unaggregated")


def test_manifest_entries_created_per_city(tmp_path) -> None:
    getter = FakeGetter(_full_payload())
    aq.acquire_all(_client(tmp_path, getter), source=SOURCE, cities=CITIES)
    manifest = load_manifest(tmp_path / "raw" / "manifest.json")
    keys = set(manifest["entries"])
    assert keys == {f"raw/aqi/{c['name']}.json" for c in CITIES}
    for entry in manifest["entries"].values():
        assert entry["window"] == {"start": AQI_START, "end": AQI_END}
        assert entry["source"] == "open_meteo_air_quality"


def test_rerun_is_cache_noop(tmp_path) -> None:
    aq.acquire_all(_client(tmp_path, FakeGetter(_full_payload())), source=SOURCE, cities=CITIES)
    no_net = FakeGetter(None)
    results = aq.acquire_all(_client(tmp_path, no_net), source=SOURCE, cities=CITIES)
    assert no_net.calls == []
    assert all(r.from_cache for r in results)
