"""Tests for the Sprint 2 weather acquisition adapter (Prompt 3).

Fully mocked HTTP (no network, no sleep). Verifies:
- one raw file per city, containing the expected variables, written verbatim
  (no aggregation/transform in the acquisition step);
- the requested window matches the configured window;
- a manifest entry is created per city;
- a missing variable in the response is logged and recorded, not dropped;
- a re-run is a pure cache no-op.
"""

from __future__ import annotations

import json
import logging

from ml.pipelines import acquire_weather as aw
from ml.pipelines.acquisition_base import (
    AcquisitionBase,
    CachePolicy,
    PipelineConfig,
    RateLimit,
    RetryPolicy,
    Window,
    load_manifest,
)

WINDOW = Window("2022-08-05", "2026-06-28")
FIXED_NOW = "2026-06-28T00:00:00+00:00"

# A weather source spec mirroring sources.yaml (kept local so tests don't depend
# on the live coverage numbers).
SOURCE = {
    "base_url": "https://archive.example.test/v1/archive",
    "granularity": "daily",
    "coverage": {
        "earliest_confirmed": "1940-01-02",
        "latest_confirmed": "2026-06-28",
    },
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
        "precipitation": {
            "api_param": "precipitation_sum",
            "acquire_param": "precipitation_sum",
            "acquire_granularity": "daily",
            "units": "mm",
        },
    },
}

CITIES = [
    {"name": "Islamabad", "lat": 33.6844, "lon": 73.0479},
    {"name": "Rawalpindi", "lat": 33.5651, "lon": 73.0169},
    {"name": "Lahore", "lat": 31.5497, "lon": 74.3436},
    {"name": "Karachi", "lat": 24.8607, "lon": 67.0011},
    {"name": "Peshawar", "lat": 34.0151, "lon": 71.5249},
]


def _payload(include_precip: bool = True) -> bytes:
    daily = {"time": ["2022-08-05"], "temperature_2m_mean": [30.1]}
    if include_precip:
        daily["precipitation_sum"] = [0.0]
    body = {
        "daily": daily,
        "hourly": {
            "time": ["2022-08-05T00:00", "2022-08-05T01:00"],
            "relative_humidity_2m": [55, 57],
        },
    }
    return json.dumps(body).encode("utf-8")


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


def _config() -> PipelineConfig:
    return PipelineConfig(
        window=WINDOW,
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


def _client(tmp_path, getter) -> AcquisitionBase:
    return AcquisitionBase(
        config=_config(),
        get=getter,
        sleep=lambda _s: None,
        now=lambda: FIXED_NOW,
        data_dir=tmp_path,
        manifest_path=tmp_path / "raw" / "manifest.json",
    )


# --- Tests -----------------------------------------------------------------


def test_one_raw_file_per_city_with_expected_variables(tmp_path) -> None:
    payload = _payload()
    getter = FakeGetter(payload)
    results = aw.acquire_all(_client(tmp_path, getter), source=SOURCE, cities=CITIES)

    assert len(results) == 5
    assert len(getter.calls) == 5  # one request per city

    for city in CITIES:
        raw = tmp_path / "raw" / "weather" / f"{city['name']}.json"
        assert raw.exists()
        # Stored verbatim — proves no aggregation/transform happened here.
        assert raw.read_bytes() == payload
        body = json.loads(raw.read_text())
        assert "temperature_2m_mean" in body["daily"]
        assert "precipitation_sum" in body["daily"]
        assert "relative_humidity_2m" in body["hourly"]
        # Sidecar documents variables + units.
        sidecar = tmp_path / "raw" / "weather" / f"{city['name']}.meta.json"
        assert sidecar.exists()
        meta = json.loads(sidecar.read_text())
        units = {v["name"]: v["units"] for v in meta["variables"]}
        assert units["humidity"] == "%"

    for r in results:
        assert set(r.present_variables) == {"temperature", "humidity", "precipitation"}
        assert r.missing_variables == []


def test_request_window_matches_config(tmp_path) -> None:
    getter = FakeGetter(_payload())
    aw.acquire_all(_client(tmp_path, getter), source=SOURCE, cities=CITIES)
    for params in getter.calls:
        assert params["start_date"] == WINDOW.start
        assert params["end_date"] == WINDOW.end
    # Humidity rides the hourly param; temp/precip the daily param.
    assert getter.calls[0]["hourly"] == "relative_humidity_2m"
    assert "temperature_2m_mean" in getter.calls[0]["daily"]


def test_manifest_entries_created_per_city(tmp_path) -> None:
    getter = FakeGetter(_payload())
    aw.acquire_all(_client(tmp_path, getter), source=SOURCE, cities=CITIES)

    manifest = load_manifest(tmp_path / "raw" / "manifest.json")
    keys = set(manifest["entries"])
    assert keys == {f"raw/weather/{c['name']}.json" for c in CITIES}
    for entry in manifest["entries"].values():
        assert entry["window"] == {"start": WINDOW.start, "end": WINDOW.end}
        assert entry["source"] == "open_meteo_weather"
        assert entry["sha256"]


def test_missing_variable_is_logged_and_recorded(tmp_path, caplog) -> None:
    getter = FakeGetter(_payload(include_precip=False))  # precipitation absent
    with caplog.at_level(logging.WARNING, logger="foreseeme.ml.acquire_weather"):
        results = aw.acquire_all(_client(tmp_path, getter), source=SOURCE, cities=CITIES)

    for r in results:
        assert "precipitation" in r.missing_variables
        assert "precipitation" not in r.present_variables

    # Recorded in the sidecar, not silently dropped.
    meta = json.loads(
        (tmp_path / "raw" / "weather" / "Lahore.meta.json").read_text()
    )
    assert "precipitation" in meta["missing_variables"]
    # Logged.
    assert any("weather_variable_missing" in rec.message for rec in caplog.records)


def test_rerun_is_cache_noop(tmp_path) -> None:
    aw.acquire_all(_client(tmp_path, FakeGetter(_payload())), source=SOURCE, cities=CITIES)

    # Second run: any network call raises inside FakeGetter.
    no_net = FakeGetter(None)
    results = aw.acquire_all(_client(tmp_path, no_net), source=SOURCE, cities=CITIES)

    assert no_net.calls == []
    assert all(r.from_cache for r in results)
