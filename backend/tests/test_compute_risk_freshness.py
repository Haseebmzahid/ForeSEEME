"""Freshness checks traverse real caching/cleaning with fake source payloads."""

import json
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import Mock

import pandas as pd
import pytest

from app.jobs import compute_risk as job
from app.predict import load_bundle, resolve_artifact_path

BUNDLE = load_bundle(resolve_artifact_path())
CITY = {"name": "Lahore", "lat": 31.5, "lon": 74.3}


@pytest.fixture
def clock(monkeypatch):
    class Clock(datetime):
        current = datetime(2026, 10, 12, 0, tzinfo=timezone.utc)

        @classmethod
        def now(cls, tz):
            return cls.current.astimezone(tz)

    monkeypatch.setattr(job, "datetime", Clock)
    return Clock


def payloads(end="2026-10-07", days=15, aqi=80.0):
    dates = pd.date_range(end=end, periods=days).strftime("%Y-%m-%d").tolist()
    return {
        job.WEATHER_SOURCE: {
            "daily": {"time": dates, "temperature_2m_mean": [25.0] * days,
                      "precipitation_sum": [2.0] * days},
            "hourly": {"time": dates, "relative_humidity_2m": [60.0] * days},
        },
        job.AQI_SOURCE: {"hourly": {"time": dates, "pm2_5": [20.0] * days,
                                    "pm10": [30.0] * days, "us_aqi": [aqi] * days}},
    }


def make_provider(tmp_path, raw, **kwargs):
    def get(url, params):
        key = job.AQI_SOURCE if "air-quality" in url else job.WEATHER_SOURCE
        return SimpleNamespace(status_code=200, content=json.dumps(raw[key]).encode())

    getter = Mock(side_effect=get)
    provider = job.OpenMeteoWeeklyBaseProvider(data_dir=tmp_path, get=getter,
                                             lookback_weeks=2, **kwargs)
    return provider, getter


@pytest.mark.parametrize("aqi", [0.0, 80.0])
def test_fresh_inputs_write_unchanged_schema_and_preserve_zero(tmp_path, clock, aqi):
    provider, _ = make_provider(tmp_path, payloads(aqi=aqi))
    repo = Mock()
    outcomes = job.run(provider, repo, cities=[CITY], bundle=BUNDLE)
    assert outcomes[0].status == "written"
    body = repo.upsert.call_args.args[1]
    assert body["aqi"] == aqi
    assert body["generatedAt"] == "2026-10-12T00:00:00Z"
    assert set(body) == {"city", "riskLevel", "disease", "confidence", "temperature",
                         "humidity", "aqi", "generatedAt", "modelVersion",
                         "lowConfidence", "attributions"}


@pytest.mark.parametrize("source,variable", [
    (job.WEATHER_SOURCE, "temperature_2m_mean"),
    (job.WEATHER_SOURCE, "precipitation_sum"),
    (job.WEATHER_SOURCE, "relative_humidity_2m"),
    (job.AQI_SOURCE, "us_aqi"), (job.AQI_SOURCE, "pm2_5"), (job.AQI_SOURCE, "pm10"),
])
def test_missing_trailing_values_skip_before_prediction_or_serialization(
        tmp_path, clock, monkeypatch, caplog, source, variable):
    raw = payloads()
    for block in raw[source].values():
        if variable in block:
            block[variable][-3:] = [None] * 3  # Older values remain in the window.
    provider, _ = make_provider(tmp_path, raw)
    predict = Mock(side_effect=AssertionError("Stale prediction forbidden"))
    serialize = Mock(side_effect=AssertionError("Stale serialization forbidden"))
    monkeypatch.setattr(job, "estimate_for_city_full", predict)
    monkeypatch.setattr(job, "_document_body", serialize)
    repo = Mock()
    assert job.run(provider, repo, cities=[CITY], bundle=BUNDLE)[0].status == "skipped_insufficient"
    predict.assert_not_called()
    serialize.assert_not_called()
    repo.upsert.assert_not_called()
    record = next(r for r in caplog.records if r.getMessage() == "city_skipped_observations")
    assert record.reason == "stale" and record.requested_end == "2026-10-07"
    assert record.last_observation == "2026-10-04"


@pytest.mark.parametrize("source", [job.WEATHER_SOURCE, job.AQI_SOURCE])
def test_empty_source_response_is_unavailable(tmp_path, clock, caplog, source):
    raw = payloads()
    raw[source] = {}
    provider, _ = make_provider(tmp_path, raw)
    repo = Mock()
    assert job.run(provider, repo, cities=[CITY], bundle=BUNDLE)[0].status == "skipped_insufficient"
    repo.upsert.assert_not_called()
    assert any(getattr(r, "reason", None) == "unavailable" for r in caplog.records)


def test_missing_aqi_is_not_zero(tmp_path, clock):
    raw = payloads(aqi=None)
    provider, _ = make_provider(tmp_path, raw)
    with pytest.raises(job.InsufficientObservations):
        provider.recent_weekly_base(CITY)


def test_partial_history_with_fresh_tail_is_accepted(tmp_path, clock):
    provider, _ = make_provider(tmp_path, payloads(days=2))
    assert not provider.recent_weekly_base(CITY).empty


def test_configurable_source_tolerance_is_separate_from_request_delay(tmp_path, clock, monkeypatch):
    raw = payloads()
    raw[job.AQI_SOURCE]["hourly"]["us_aqi"][-1] = None
    monkeypatch.setenv("RISK_AQI_MAX_TRAILING_GAP_DAYS", "1")
    provider, _ = make_provider(tmp_path, raw)
    assert provider._recent_window().end == "2026-10-07"
    assert not provider.recent_weekly_base(CITY).empty


@pytest.mark.parametrize("key", ["RISK_WEATHER_MAX_TRAILING_GAP_DAYS", "RISK_AQI_MAX_TRAILING_GAP_DAYS"])
def test_negative_freshness_policy_is_rejected(tmp_path, monkeypatch, key):
    monkeypatch.setenv(key, "-1")
    with pytest.raises(ValueError, match="Freshness trailing gaps"):
        make_provider(tmp_path, payloads())


def test_incomplete_cached_payload_is_rechecked_without_stale_write(tmp_path, clock):
    raw = payloads()
    raw[job.AQI_SOURCE]["hourly"]["us_aqi"][-1] = None
    provider, getter = make_provider(tmp_path, raw)
    for _ in range(2):
        with pytest.raises(job.InsufficientObservations):
            provider.recent_weekly_base(CITY)
    assert getter.call_count == 2  # One weather + one AQI download; then cache hits.
    clock.current += timedelta(days=1)
    with pytest.raises(job.InsufficientObservations):
        provider.recent_weekly_base(CITY)
    assert getter.call_count == 3  # New weather window is fetched and rejected before AQI.


@pytest.mark.parametrize("instant,end", [
    (datetime(2026, 1, 1, 0, tzinfo=timezone.utc), "2025-12-27"),
    (datetime(2026, 10, 11, 23, 59, tzinfo=timezone.utc), "2026-10-06"),
    (datetime(2026, 10, 12, 0, tzinfo=timezone.utc), "2026-10-07"),
])
def test_utc_boundary_keeps_five_day_request_policy(tmp_path, clock, instant, end):
    clock.current = instant
    provider, _ = make_provider(tmp_path, payloads(end=end))
    assert provider._recent_window().end == end
    assert not provider.recent_weekly_base(CITY).empty


@pytest.mark.parametrize("missing", [float("nan"), None, pd.NA, float("inf")])
def test_latest_week_missing_conditions_cannot_use_older_week(monkeypatch, missing):
    base = pd.DataFrame([
        {"city": "Lahore", "iso_year": 2026, "week_of_year": 39,
         "temperature": 25, "humidity": 60, "us_aqi": 80},
        {"city": "Lahore", "iso_year": 2026, "week_of_year": 40,
         "temperature": 25, "humidity": 60, "us_aqi": missing},
    ])
    predict = Mock(side_effect=AssertionError("Missing inputs must not be predicted"))
    monkeypatch.setattr(job, "classify_dominant", predict)
    assert job.estimate_for_city_full(BUNDLE, "Lahore", base, datetime.now(timezone.utc)) is None
    predict.assert_not_called()
