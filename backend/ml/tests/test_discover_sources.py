"""Tests for the Sprint 2 data-source discovery pipeline.

Covers the Prompt 1 acceptance/testing requirements:
- ``cities.yaml`` and ``sources.yaml`` parse and contain all five cities and the
  required variables.
- The probing script records an unreachable endpoint as ``"unavailable"``
  instead of raising.

Plus a regression guard for the real finding of this prompt: the Air Quality
API declares a 2013 start that is *hollow* (null until 2022), so the discovery
must binary-search the true earliest non-null date and must NOT trust the
declared bound. All tests are offline — the network path is exercised only via
injected fakes.
"""

from __future__ import annotations

import datetime as dt

import httpx

from ml.pipelines import discover_sources as ds

EXPECTED_CITIES = {"Islamabad", "Rawalpindi", "Lahore", "Karachi", "Peshawar"}
EXPECTED_WEATHER_VARS = {"temperature", "humidity", "precipitation"}
EXPECTED_AQ_VARS = {"pm2_5", "pm10", "us_aqi"}


# --- Config parsing --------------------------------------------------------


def test_cities_yaml_has_all_five_cities_with_fields() -> None:
    cities = ds.load_cities()
    names = {c["name"] for c in cities}
    assert names == EXPECTED_CITIES
    for city in cities:
        assert isinstance(city["lat"], (int, float))
        assert isinstance(city["lon"], (int, float))
        assert city["province"]


def test_sources_yaml_training_sources_have_required_variables() -> None:
    sources = ds.training_sources()
    assert "open_meteo_weather" in sources
    assert "open_meteo_air_quality" in sources

    weather_vars = set(sources["open_meteo_weather"]["variables"])
    aq_vars = set(sources["open_meteo_air_quality"]["variables"])
    assert EXPECTED_WEATHER_VARS <= weather_vars
    assert EXPECTED_AQ_VARS <= aq_vars

    # Each variable maps to a concrete API parameter.
    for spec in sources.values():
        for var_spec in spec["variables"].values():
            assert var_spec["api_param"]


def test_sources_yaml_carries_no_embedded_keys() -> None:
    """GOLDEN_RULES #7: no secrets in source; keyless sources declare it."""
    everything = ds.load_yaml(ds.SOURCES_PATH)
    for spec in everything["sources"].values():
        access = spec["access"]
        assert access["auth"] == "none"
        assert access["api_key_env"] is None


def test_validation_sources_are_not_training_labels() -> None:
    everything = ds.load_yaml(ds.SOURCES_PATH)
    validation = everything["validation_only"]
    # The four catalogued disease/seasonality references are present and flagged
    # validation-only (never probed, never training labels).
    assert {"who_emro", "ihme_gbd", "punjab_dengue_surveillance"} <= set(validation)
    for spec in validation.values():
        assert spec["role"] == "validation_only"


def test_modeling_window_is_recorded_and_governed_by_air_quality() -> None:
    everything = ds.load_yaml(ds.SOURCES_PATH)
    window = everything["modeling_window"]
    assert window["start"] and window["end"]
    assert "air_quality" in window["governed_by"]


# --- Unreachable endpoint is recorded, not raised --------------------------


def _raising_getter(url: str, params: dict) -> httpx.Response:
    raise httpx.ConnectError("simulated unreachable endpoint")


def test_probe_records_unavailable_on_unreachable_endpoint() -> None:
    spec = ds.training_sources()["open_meteo_air_quality"]
    city = {"name": "Lahore", "lat": 31.5497, "lon": 74.3436}

    result = ds.probe_city_source(
        _raising_getter, "open_meteo_air_quality", spec, city, dt.date(2026, 6, 28)
    )

    assert result.status == "unavailable"
    assert result.variables == []
    assert result.error and "ConnectError" in result.error


def test_discover_all_does_not_raise_when_all_endpoints_fail() -> None:
    results = ds.discover_all(get=_raising_getter, today=dt.date(2026, 6, 28))
    assert len(results) == 10  # 5 cities x 2 training sources
    assert all(r.status == "unavailable" for r in results)


# --- Hollow declared start: must measure the real earliest -----------------


class _FakeResponse:
    def __init__(self, status_code: int, payload: dict | None = None, text: str = ""):
        self.status_code = status_code
        self._payload = payload or {}
        self.text = text

    def json(self) -> dict:
        return self._payload


def _make_fake_getter(
    declared: tuple[str, str], real_start: str, granularity: str, api_params: list[str]
):
    """Fake Open-Meteo getter: declares ``declared`` but data is null before
    ``real_start`` (a hollow declared start, like CAMS)."""
    declared_start, declared_end = declared
    real = dt.date.fromisoformat(real_start)

    def getter(url: str, params: dict) -> _FakeResponse:
        start = params["start_date"]
        if start == ds._TOO_EARLY_DATE:
            return _FakeResponse(
                400, text=f"allowed range from {declared_start} to {declared_end}"
            )
        s = dt.date.fromisoformat(start)
        e = dt.date.fromisoformat(params["end_date"])
        times: list[str] = []
        series: dict[str, list] = {p: [] for p in api_params}
        day = s
        while day <= e:
            stamps = (
                [f"{day.isoformat()}T{h:02d}:00" for h in range(24)]
                if granularity == "hourly"
                else [day.isoformat()]
            )
            for stamp in stamps:
                times.append(stamp)
                for p in api_params:
                    series[p].append(1.0 if day >= real else None)
            day += dt.timedelta(days=1)
        return _FakeResponse(200, {granularity: {"time": times, **series}})

    return getter


def test_discovery_finds_real_earliest_not_hollow_declared_start() -> None:
    """The declared start (2013) is hollow; real data begins 2022-08-04. The
    discovery must report the *real* date, never the declared one."""
    spec = {
        "name": "Fake Air Quality",
        "base_url": "https://example.test/air-quality",
        "granularity": "hourly",
        "variables": {
            "pm2_5": {"api_param": "pm2_5"},
            "pm10": {"api_param": "pm10"},
        },
    }
    getter = _make_fake_getter(
        declared=("2013-01-01", "2026-07-04"),
        real_start="2022-08-04",
        granularity="hourly",
        api_params=["pm2_5", "pm10"],
    )

    result = ds.probe_city_source(
        getter,
        "fake_aq",
        spec,
        {"name": "Lahore", "lat": 31.5, "lon": 74.3},
        dt.date(2026, 6, 28),
    )

    assert result.status == "available"
    assert result.declared_range == "2013-01-01 to 2026-07-04"
    for var in result.variables:
        assert var.earliest_confirmed == "2022-08-04", var.variable
        assert var.latest_confirmed == "2026-06-28"
