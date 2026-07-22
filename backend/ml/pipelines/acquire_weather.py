"""Weather data acquisition adapter (Sprint 2, Prompt 3).

First concrete source adapter on the Prompt 2 acquisition framework. It pulls
historical daily weather for all five cities across the project window and
stores **immutable raw** API responses — one file per city, no merging.

What it fetches (driven entirely by ``sources.yaml`` / ``pipeline.yaml``):

* temperature  -> daily ``temperature_2m_mean``  (°C)
* precipitation-> daily ``precipitation_sum``     (mm)
* humidity     -> **hourly** ``relative_humidity_2m`` (%)

Open-Meteo serves humidity as an hourly variable, so it is pulled hourly and
stored raw. It is aggregated to a daily mean **later, in the cleaning phase** —
never here (acquisition stays raw; ADR/Shared-Principle: derive aggregates
downstream). temperature and precipitation are genuine daily aggregates the API
computes server-side.

Guarantees inherited from :class:`AcquisitionBase`: idempotent caching (re-run is
a no-op), atomic writes, a hash manifest, retry/backoff, and request logging.

Beyond the raw blob, each city gets a small ``<city>.meta.json`` sidecar
documenting the retained variables, their units/granularity, and which were
present vs missing in the response (missing variables are logged and recorded,
never silently dropped).

Run (from ``backend/``)::

    python -m ml.pipelines.acquire_weather
"""

from __future__ import annotations

import json
import logging
from dataclasses import dataclass
from typing import Any

from ml.pipelines import paths
from ml.pipelines.acquisition_base import (
    AcquisitionBase,
    FetchResult,
    Window,
    write_raw_atomic,
)
from ml.pipelines.acquisition_common import (
    VariableSpec,
    check_variables,
    clip_to_coverage,
    read_raw_json,
    validate_payload_structure,
)
from ml.pipelines.acquisition_common import load_yaml as _load_yaml
from ml.pipelines.acquisition_common import variable_specs as _shared_variable_specs
from ml.pipelines.quality_report import (
    PIPELINE_VERSION,
    from_acquisition,
    new_report,
    record_pipeline_stage,
)

logger = logging.getLogger("foreseeme.ml.acquire_weather")

#: Manifest source key and the raw/ sub-directory for this source.
SOURCE_KEY = "open_meteo_weather"
SUBDIR = "weather"


# --- Config loading --------------------------------------------------------


def load_weather_source(path=paths.SOURCES_PATH) -> dict[str, Any]:
    """Return the ``open_meteo_weather`` source spec from sources.yaml."""
    return _load_yaml(path)["sources"][SOURCE_KEY]


def load_cities(path=paths.CITIES_PATH) -> list[dict[str, Any]]:
    """Return the list of city dicts from cities.yaml."""
    return _load_yaml(path)["cities"]


# --- Variable model --------------------------------------------------------


def variable_specs(source: dict[str, Any]) -> list[VariableSpec]:
    """Build the acquisition variable list, defaulting to daily granularity.

    Reads ``acquire_param`` / ``acquire_granularity`` per variable, defaulting to
    ``api_param`` at the source-level granularity. Thin wrapper over the shared
    :func:`ml.pipelines.acquisition_common.variable_specs`.
    """
    return _shared_variable_specs(source, default_granularity="daily")


# --- Result model ----------------------------------------------------------


@dataclass(frozen=True)
class CityWeatherResult:
    """Outcome of acquiring one city's weather."""

    city: str
    key: str
    from_cache: bool
    requested_window: tuple[str, str]
    effective_window: tuple[str, str]
    clipped: bool
    present_variables: list[str]
    missing_variables: list[str]
    structural_issues: list[str]


# --- Request building ------------------------------------------------------


def build_params(
    city: dict[str, Any], specs: list[VariableSpec], window: Window
) -> dict[str, Any]:
    """Build the Open-Meteo archive query for one city.

    Variables are grouped into ``daily=`` / ``hourly=`` by their granularity, so
    a single request returns daily temperature/precipitation and hourly humidity.
    """
    params: dict[str, Any] = {
        "latitude": city["lat"],
        "longitude": city["lon"],
        "start_date": window.start,
        "end_date": window.end,
        "timezone": "UTC",
    }
    for granularity in ("daily", "hourly"):
        names = [s.api_param for s in specs if s.granularity == granularity]
        if names:
            params[granularity] = ",".join(names)
    return params


# --- Sidecar ---------------------------------------------------------------


def _write_sidecar(
    client: AcquisitionBase,
    city: dict[str, Any],
    requested: Window,
    effective: Window,
    clipped: bool,
    specs: list[VariableSpec],
    present: list[str],
    missing: list[str],
    structural_issues: list[str],
    result: FetchResult,
) -> None:
    """Write the human-readable ``<city>.meta.json`` sidecar next to the raw file."""
    sidecar = {
        "source": SOURCE_KEY,
        "city": city["name"],
        "requested_window": {"start": requested.start, "end": requested.end},
        "effective_window": {"start": effective.start, "end": effective.end},
        "clipped_to_coverage": clipped,
        "raw_file": result.key,
        "sha256": result.entry.get("sha256"),
        "variables": [
            {
                "name": s.name,
                "api_param": s.api_param,
                "granularity": s.granularity,
                "units": s.units,
                "present": s.name in present,
            }
            for s in specs
        ],
        "missing_variables": missing,
        "structural_issues": structural_issues,
        "pipeline_version": PIPELINE_VERSION,
        "quality_report_path": str(paths.REPORTS_DIR / f"quality_{SOURCE_KEY}.json"),
        "note": (
            "Raw, unaggregated Open-Meteo response. Hourly humidity "
            "(relative_humidity_2m) is aggregated to a daily mean in the "
            "cleaning phase, not here."
        ),
    }
    path = paths.raw_path(
        SOURCE_KEY,
        city["name"],
        effective,
        ext="meta.json",
        data_dir=client.data_dir,
        subdir=SUBDIR,
    )
    write_raw_atomic(path, (json.dumps(sidecar, indent=2, sort_keys=True) + "\n").encode())


# --- Per-city acquisition --------------------------------------------------


def acquire_city(
    client: AcquisitionBase,
    source: dict[str, Any],
    city: dict[str, Any],
    window: Window,
) -> CityWeatherResult:
    """Acquire and persist one city's raw weather, returning a summary."""
    specs = variable_specs(source)
    effective, clipped = clip_to_coverage(window, source.get("coverage", {}))
    if clipped:
        logger.warning(
            "window_clipped_to_coverage",
            extra={
                "city": city["name"],
                "requested": [window.start, window.end],
                "effective": [effective.start, effective.end],
            },
        )

    params = build_params(city, specs, effective)
    result = client.fetch_with_cache(
        source=SOURCE_KEY,
        city=city["name"],
        window=effective,
        url=source["base_url"],
        params=params,
        subdir=SUBDIR,
    )

    payload = read_raw_json(result.path)
    present, missing = check_variables(payload, specs)
    for name in missing:
        logger.warning(
            "weather_variable_missing",
            extra={"city": city["name"], "variable": name},
        )

    issues = validate_payload_structure(payload, specs)
    for issue in issues:
        logger.warning(
            "weather_payload_structural_issue",
            extra={"city": city["name"], "variable": issue.variable, "kind": issue.kind,
                   "detail": issue.detail},
        )
    structural_issues = [str(issue) for issue in issues]

    _write_sidecar(
        client, city, window, effective, clipped, specs, present, missing,
        structural_issues, result,
    )

    return CityWeatherResult(
        city=city["name"],
        key=result.key,
        from_cache=result.from_cache,
        requested_window=(window.start, window.end),
        effective_window=(effective.start, effective.end),
        clipped=clipped,
        present_variables=present,
        missing_variables=missing,
        structural_issues=structural_issues,
    )


def acquire_all(
    client: AcquisitionBase | None = None,
    *,
    source: dict[str, Any] | None = None,
    cities: list[dict[str, Any]] | None = None,
) -> list[CityWeatherResult]:
    """Acquire raw weather for every city. Window comes from the client config."""
    client = client or AcquisitionBase()
    source = source or load_weather_source()
    cities = cities or load_cities()
    window = client.config.window
    return [acquire_city(client, source, city, window) for city in cities]


def main() -> None:
    """Acquire all cities' weather and print a one-line-per-city summary."""
    import time

    from app.logging_config import configure_logging

    client = AcquisitionBase()
    configure_logging(client.config.log_level)

    start = time.perf_counter()
    results = acquire_all(client)
    duration = time.perf_counter() - start

    for r in results:
        state = "cache" if r.from_cache else "downloaded"
        missing = f" missing={r.missing_variables}" if r.missing_variables else ""
        issues = f" issues={r.structural_issues}" if r.structural_issues else ""
        print(
            f"{r.city:11} {state:10} {r.effective_window[0]}..{r.effective_window[1]}"
            f" vars={r.present_variables}{missing}{issues}"
        )

    report_path = paths.REPORTS_DIR / f"quality_{SOURCE_KEY}.json"
    report = new_report(SOURCE_KEY)
    report.add_stage(from_acquisition(results, duration_seconds=duration))
    paths.ensure_dir(paths.REPORTS_DIR)
    report.save(report_path)
    print(report.render_text())

    record_pipeline_stage(
        paths.REPORTS_DIR / "pipeline_run.json", "weather_acquisition",
        duration_seconds=duration, warnings=report.warning_count,
    )


if __name__ == "__main__":
    main()
