"""Live-provider regressions with fake HTTP and isolated cache storage."""

import json
from datetime import datetime, timezone
from types import SimpleNamespace

import pytest

from app.jobs import compute_risk as job
from ml.pipelines.acquisition_base import Window


@pytest.fixture
def provider(monkeypatch, tmp_path):
    # Fail closed if a test accidentally reaches the HTTP seam.
    def no_http(*args, **kwargs):
        raise AssertionError("Unexpected HTTP request")

    return job.OpenMeteoWeeklyBaseProvider(data_dir=tmp_path, get=no_http)


def test_recent_window_uses_utc_archive_delay(monkeypatch, provider):
    class Clock:
        @staticmethod
        def now(tz):
            assert tz is timezone.utc
            return datetime(2026, 10, 12, 1, tzinfo=tz)

    monkeypatch.setattr(job, "datetime", Clock)
    assert provider._recent_window() == Window("2026-07-15", "2026-10-07")


@pytest.mark.parametrize("lookback,delay", [(0, 5), (-1, 5), (12, -1)])
def test_invalid_window_configuration_is_rejected(lookback, delay):
    with pytest.raises(ValueError, match="Lookback"):
        job.OpenMeteoWeeklyBaseProvider(lookback_weeks=lookback, data_delay_days=delay)


@pytest.mark.parametrize("source,subdir,aqi", [
    (job.WEATHER_SOURCE, "weather", False), (job.AQI_SOURCE, "aqi", True),
])
def test_live_fetch_does_not_clip_to_training_snapshot(monkeypatch, tmp_path, provider,
                                                     source, subdir, aqi):
    window = Window("2026-07-15", "2026-10-07")
    raw = tmp_path / "payload.json"
    raw.write_text("{}", encoding="utf-8")
    seen = []

    def fetch(**kwargs):
        seen.append(kwargs)
        return SimpleNamespace(path=raw)

    monkeypatch.setattr(provider._client, "fetch_with_cache", fetch)
    stats = SimpleNamespace(variables=[SimpleNamespace(coverage_end=window.end)])
    monkeypatch.setattr(job.clean, "clean_city", lambda *args, **kwargs: ("daily", stats))
    assert provider._fetch_clean_daily(source, subdir, {"name": "Lahore", "lat": 31.5,
                                                       "lon": 74.3}, window, aqi) == "daily"
    assert seen[0]["window"] == window
    assert seen[0]["params"]["start_date"] == window.start
    assert seen[0]["params"]["end_date"] == window.end


def test_no_coverage_overlap_fails_before_fetch(provider):
    with pytest.raises(ValueError, match="does not overlap"):
        provider._fetch_clean_daily(job.AQI_SOURCE, "aqi", {"name": "Lahore"},
                                   Window("2000-01-01", "2000-02-01"), True)


def test_provider_cache_and_manifest_use_writable_override(tmp_path):
    calls = []

    def get(url, params):
        calls.append(params)
        return SimpleNamespace(status_code=200, content=b'{"ok":true}')

    provider = job.OpenMeteoWeeklyBaseProvider(data_dir=tmp_path / "cache", get=get)
    client = provider._client
    kwargs = dict(source=job.WEATHER_SOURCE, city="Lahore",
                  window=Window("2026-07-15", "2026-10-07"),
                  url="https://example.test", params={})
    first = client.fetch_with_cache(**kwargs)
    second = client.fetch_with_cache(**kwargs)
    assert first.path.is_relative_to(tmp_path / "cache")
    assert client.manifest_path == tmp_path / "cache" / "raw" / "manifest.json"
    assert json.loads(client.manifest_path.read_text())["entries"][first.key]
    assert second.from_cache and len(calls) == 1
