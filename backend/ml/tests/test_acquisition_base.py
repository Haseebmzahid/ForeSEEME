"""Tests for the Sprint 2 acquisition framework (Prompt 2).

Covers the required scenarios with a fully mocked HTTP layer (no network, no
real sleep):
- a first call writes a raw file + manifest entry;
- a second identical call is a cache hit with zero network calls;
- a hash mismatch triggers a re-download;
- a transient 5xx retries then succeeds.

Plus the acceptance guarantees: deterministic round-tripping manifest, identical
manifests across re-runs, no-hardcoded-paths contract, and non-retryable errors.
"""

from __future__ import annotations

import httpx
import pytest

from ml.pipelines import paths
from ml.pipelines.acquisition_base import (
    AcquisitionBase,
    AcquisitionError,
    CachePolicy,
    PipelineConfig,
    RateLimit,
    RetryPolicy,
    Window,
    empty_manifest,
    load_manifest,
    load_pipeline_config,
    save_manifest_atomic,
    sha256_bytes,
)

URL = "https://example.test/archive"
WINDOW = Window("2022-08-05", "2026-06-28")
FIXED_NOW = "2026-06-28T00:00:00+00:00"


# --- Test doubles ----------------------------------------------------------


class FakeResponse:
    def __init__(self, status_code: int, content: bytes = b"", json_data=None):
        self.status_code = status_code
        self.content = content
        self._json = json_data

    def json(self):
        return self._json


class FakeGetter:
    """Returns queued responses in order; raises queued exceptions; records calls."""

    def __init__(self, responses):
        self._responses = list(responses)
        self.calls: list[tuple[str, dict]] = []

    def __call__(self, url, params):
        self.calls.append((url, dict(params)))
        item = self._responses.pop(0)
        if isinstance(item, Exception):
            raise item
        return item


def _config(**overrides) -> PipelineConfig:
    base = dict(
        window=WINDOW,
        cache=CachePolicy(reuse_on_hash_match=True, verify_hash=True),
        retry=RetryPolicy(
            max_attempts=4,
            backoff_initial_seconds=0.0,
            backoff_factor=2.0,
            retry_on_status=(429, 500, 502, 503, 504),
            timeout_seconds=5.0,
        ),
        rate_limit=RateLimit(min_interval_seconds=0.0),
        log_level="INFO",
    )
    base.update(overrides)
    return PipelineConfig(**base)


def _client(tmp_path, getter, **cfg_overrides) -> AcquisitionBase:
    return AcquisitionBase(
        config=_config(**cfg_overrides),
        get=getter,
        sleep=lambda _seconds: None,
        now=lambda: FIXED_NOW,
        data_dir=tmp_path,
        manifest_path=tmp_path / "raw" / "manifest.json",
    )


def _fetch(client, **overrides):
    kwargs = dict(
        source="open_meteo_weather",
        city="Lahore",
        window=WINDOW,
        url=URL,
        params={"latitude": 31.5, "longitude": 74.3},
    )
    kwargs.update(overrides)
    return client.fetch_with_cache(**kwargs)


# --- Paths / config contracts ----------------------------------------------


def test_paths_are_derived_not_hardcoded() -> None:
    assert paths.RAW_DIR == paths.DATA_DIR / "raw"
    assert paths.MANIFEST_PATH == paths.RAW_DIR / "manifest.json"
    rel = paths.raw_relpath("open_meteo_weather", "Lahore", WINDOW)
    assert rel == "raw/open_meteo_weather__Lahore__2022-08-05_2026-06-28.json"


def test_raw_path_is_rooted_at_given_data_dir(tmp_path) -> None:
    p = paths.raw_path("open_meteo_air_quality", "Karachi", WINDOW, data_dir=tmp_path)
    assert p == tmp_path / "raw" / (
        "open_meteo_air_quality__Karachi__2022-08-05_2026-06-28.json"
    )


def test_pipeline_yaml_parses() -> None:
    cfg = load_pipeline_config()
    assert cfg.window.start and cfg.window.end
    assert cfg.cache.reuse_on_hash_match is True
    assert 500 in cfg.retry.retry_on_status
    assert cfg.retry.max_attempts >= 1


# --- Required: first write, cache hit, mismatch, retry ----------------------


def test_first_call_writes_raw_file_and_manifest_entry(tmp_path) -> None:
    getter = FakeGetter([FakeResponse(200, content=b'{"ok":1}')])
    client = _client(tmp_path, getter)

    result = _fetch(client)

    assert result.from_cache is False
    assert result.path.exists()
    assert result.path.read_bytes() == b'{"ok":1}'
    assert len(getter.calls) == 1

    manifest = load_manifest(tmp_path / "raw" / "manifest.json")
    entry = manifest["entries"][result.key]
    assert entry["source"] == "open_meteo_weather"
    assert entry["city"] == "Lahore"
    assert entry["window"] == {"start": "2022-08-05", "end": "2026-06-28"}
    assert entry["sha256"] == sha256_bytes(b'{"ok":1}')
    assert entry["bytes"] == len(b'{"ok":1}')
    assert entry["fetched_at"] == FIXED_NOW


def test_second_identical_call_is_cache_hit_with_no_network(tmp_path) -> None:
    first = FakeGetter([FakeResponse(200, content=b'{"ok":1}')])
    _fetch(_client(tmp_path, first))
    assert len(first.calls) == 1

    # A getter with no queued responses would IndexError if called.
    second = FakeGetter([])
    result = _fetch(_client(tmp_path, second))

    assert result.from_cache is True
    assert second.calls == []


def test_hash_mismatch_triggers_redownload(tmp_path) -> None:
    first = FakeGetter([FakeResponse(200, content=b'{"ok":1}')])
    result = _fetch(_client(tmp_path, first))

    # Corrupt the cached file; manifest still records the original hash.
    result.path.write_bytes(b"corrupted-bytes")

    redo = FakeGetter([FakeResponse(200, content=b'{"ok":1}')])
    result2 = _fetch(_client(tmp_path, redo))

    assert result2.from_cache is False
    assert len(redo.calls) == 1
    assert result2.path.read_bytes() == b'{"ok":1}'


def test_transient_5xx_retries_then_succeeds(tmp_path) -> None:
    getter = FakeGetter(
        [FakeResponse(503), FakeResponse(503), FakeResponse(200, content=b"payload")]
    )
    result = _fetch(_client(tmp_path, getter))

    assert result.from_cache is False
    assert len(getter.calls) == 3
    assert result.path.read_bytes() == b"payload"


# --- Error paths -----------------------------------------------------------


def test_non_retryable_4xx_raises(tmp_path) -> None:
    getter = FakeGetter([FakeResponse(404)])
    with pytest.raises(AcquisitionError):
        _fetch(_client(tmp_path, getter))


def test_network_errors_retry_then_exhaust(tmp_path) -> None:
    getter = FakeGetter([httpx.ConnectError("boom")] * 4)
    with pytest.raises(AcquisitionError):
        _fetch(_client(tmp_path, getter))
    assert len(getter.calls) == 4  # max_attempts


# --- Manifest determinism & idempotency ------------------------------------


def test_manifest_round_trips(tmp_path) -> None:
    manifest = empty_manifest()
    manifest["entries"]["raw/x.json"] = {
        "source": "s",
        "city": "Lahore",
        "sha256": "abc",
    }
    path = tmp_path / "raw" / "manifest.json"
    save_manifest_atomic(manifest, path)
    assert load_manifest(path) == manifest


def test_manifest_serialization_is_order_independent(tmp_path) -> None:
    a = {"version": 1, "entries": {"raw/b.json": {"x": 1}, "raw/a.json": {"y": 2}}}
    b = {"entries": {"raw/a.json": {"y": 2}, "raw/b.json": {"x": 1}}, "version": 1}
    pa = tmp_path / "a" / "manifest.json"
    pb = tmp_path / "b" / "manifest.json"
    save_manifest_atomic(a, pa)
    save_manifest_atomic(b, pb)
    assert pa.read_bytes() == pb.read_bytes()


def test_rerun_produces_identical_manifest_and_zero_duplicate_calls(tmp_path) -> None:
    manifest_path = tmp_path / "raw" / "manifest.json"

    first = FakeGetter([FakeResponse(200, content=b'{"ok":1}')])
    _fetch(_client(tmp_path, first))
    bytes_after_first = manifest_path.read_bytes()
    assert len(first.calls) == 1

    second = FakeGetter([])  # no network allowed on re-run
    result = _fetch(_client(tmp_path, second))
    bytes_after_second = manifest_path.read_bytes()

    assert result.from_cache is True
    assert second.calls == []
    assert bytes_after_first == bytes_after_second
