"""Air-quality data acquisition adapter (Sprint 2, Prompt 4).

Sibling of :mod:`acquire_weather`, on the same Prompt 2 framework. It pulls
historical hourly air quality for all five cities and stores **immutable raw**
API responses — one file per city, no merging.

What it fetches (driven by ``sources.yaml`` / ``pipeline.yaml``), all hourly:

* pm2_5  -> ``pm2_5``  (µg/m³)
* pm10   -> ``pm10``   (µg/m³)
* us_aqi -> ``us_aqi`` (US AQI)

Air quality is the **scarcest** source (Shared Principle 2): CAMS via Open-Meteo
declares a 2013 start but only returns real values from 2022-08 (see Prompt 1).
That measured coverage — in ``sources.yaml`` — governs the merged dataset's
usable range. This adapter therefore:

* **clips** the requested window to the AQI coverage (never requesting earlier
  dates the source cannot serve — back-filling is forbidden);
* **inspects** each response and records the *exact* covered window per variable
  in the sidecar, so a partial-coverage city is a documented fact, not a failure;
* treats the pre-coverage period as missing-by-design for downstream phases — it
  invents nothing.

Run (from ``backend/``)::

    python -m ml.pipelines.acquire_aqi
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
from ml.pipelines.quality_report import PIPELINE_VERSION, from_acquisition, new_report

logger = logging.getLogger("foreseeme.ml.acquire_aqi")

SOURCE_KEY = "open_meteo_air_quality"
SUBDIR = "aqi"


# --- Config loading --------------------------------------------------------


def load_aqi_source(path=paths.SOURCES_PATH) -> dict[str, Any]:
    """Return the ``open_meteo_air_quality`` source spec from sources.yaml."""
    return _load_yaml(path)["sources"][SOURCE_KEY]


def load_cities(path=paths.CITIES_PATH) -> list[dict[str, Any]]:
    """Return the list of city dicts from cities.yaml."""
    return _load_yaml(path)["cities"]


# --- Variable model --------------------------------------------------------


def variable_specs(source: dict[str, Any]) -> list[VariableSpec]:
    """Build the acquisition variable list, defaulting to hourly granularity.

    Thin wrapper over the shared
    :func:`ml.pipelines.acquisition_common.variable_specs`.
    """
    return _shared_variable_specs(source, default_granularity="hourly")


# --- Result model ----------------------------------------------------------


@dataclass(frozen=True)
class CityAqiResult:
    """Outcome of acquiring one city's air quality."""

    city: str
    key: str
    from_cache: bool
    requested_window: tuple[str, str]
    effective_window: tuple[str, str]
    clipped: bool
    present_variables: list[str]
    missing_variables: list[str]
    covered_window: tuple[str | None, str | None]
    partial_coverage: bool
    structural_issues: list[str]


# --- Request building ------------------------------------------------------


def build_params(
    city: dict[str, Any], specs: list[VariableSpec], window: Window
) -> dict[str, Any]:
    """Build the Open-Meteo air-quality query for one city (all hourly variables)."""
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


# --- Coverage inspection -----------------------------------------------------


def _first_nonnull_date(times: list[str], values: list[Any]) -> str | None:
    for ts, value in zip(times, values):
        if value is not None:
            return ts[:10]
    return None


def _last_nonnull_date(times: list[str], values: list[Any]) -> str | None:
    for ts, value in zip(reversed(times), reversed(values)):
        if value is not None:
            return ts[:10]
    return None


def variable_coverage(
    payload: dict[str, Any], specs: list[VariableSpec]
) -> tuple[dict[str, dict[str, Any]], str | None, str | None]:
    """Measure the *actual* covered window per variable from the raw response.

    Returns per-variable coverage plus the overall usable window — the scarcest
    common range (latest start, earliest end) across present variables. This is
    the exact AQI window recorded in the sidecar.
    """
    per_variable: dict[str, dict[str, Any]] = {}
    starts: list[str] = []
    ends: list[str] = []
    for spec in specs:
        block = payload.get(spec.granularity, {}) or {}
        times = block.get("time", []) or []
        values = block.get(spec.api_param, []) or []
        earliest = _first_nonnull_date(times, values)
        latest = _last_nonnull_date(times, values)
        nonnull = sum(1 for v in values if v is not None)
        per_variable[spec.name] = {
            "earliest": earliest,
            "latest": latest,
            "nonnull_points": nonnull,
            "total_points": len(values),
        }
        if earliest:
            starts.append(earliest)
        if latest:
            ends.append(latest)
    overall_start = max(starts) if starts else None
    overall_end = min(ends) if ends else None
    return per_variable, overall_start, overall_end


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
    per_variable: dict[str, dict[str, Any]],
    covered: tuple[str | None, str | None],
    partial: bool,
    structural_issues: list[str],
    result: FetchResult,
) -> None:
    """Write ``<city>.meta.json`` recording the exact AQI coverage limits."""
    sidecar = {
        "source": SOURCE_KEY,
        "city": city["name"],
        "requested_window": {"start": requested.start, "end": requested.end},
        "effective_window": {"start": effective.start, "end": effective.end},
        "clipped_to_coverage": clipped,
        "covered_window": {"start": covered[0], "end": covered[1]},
        "partial_coverage": partial,
        "raw_file": result.key,
        "sha256": result.entry.get("sha256"),
        "variables": [
            {
                "name": s.name,
                "api_param": s.api_param,
                "granularity": s.granularity,
                "units": s.units,
                "present": s.name in present,
                "coverage": per_variable.get(s.name),
            }
            for s in specs
        ],
        "missing_variables": missing,
        "structural_issues": structural_issues,
        "pipeline_version": PIPELINE_VERSION,
        "quality_report_path": str(paths.REPORTS_DIR / f"quality_{SOURCE_KEY}.json"),
        "note": (
            "Raw, unaggregated Open-Meteo air-quality response. AQI is the "
            "scarcest source; earlier values are NOT back-filled. The "
            "pre-coverage period is missing-by-design for downstream phases."
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
) -> CityAqiResult:
    """Acquire and persist one city's raw AQI, recording its coverage limits."""
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
            "aqi_variable_missing", extra={"city": city["name"], "variable": name}
        )

    issues = validate_payload_structure(payload, specs)
    for issue in issues:
        logger.warning(
            "aqi_payload_structural_issue",
            extra={"city": city["name"], "variable": issue.variable, "kind": issue.kind,
                   "detail": issue.detail},
        )
    structural_issues = [str(issue) for issue in issues]

    per_variable, cov_start, cov_end = variable_coverage(payload, specs)
    partial = _is_partial(effective, cov_start, cov_end)
    if partial:
        logger.warning(
            "aqi_partial_coverage",
            extra={
                "city": city["name"],
                "requested": [effective.start, effective.end],
                "covered": [cov_start, cov_end],
            },
        )

    _write_sidecar(
        client, city, window, effective, clipped, specs, present, missing,
        per_variable, (cov_start, cov_end), partial, structural_issues, result,
    )

    return CityAqiResult(
        city=city["name"],
        key=result.key,
        from_cache=result.from_cache,
        requested_window=(window.start, window.end),
        effective_window=(effective.start, effective.end),
        clipped=clipped,
        present_variables=present,
        missing_variables=missing,
        covered_window=(cov_start, cov_end),
        partial_coverage=partial,
        structural_issues=structural_issues,
    )


def _is_partial(
    effective: Window, cov_start: str | None, cov_end: str | None
) -> bool:
    """True when the actual covered window is narrower than what was requested
    (including the no-data case), i.e. a partial-coverage city."""
    if cov_start is None or cov_end is None:
        return True
    return cov_start > effective.start or cov_end < effective.end


def acquire_all(
    client: AcquisitionBase | None = None,
    *,
    source: dict[str, Any] | None = None,
    cities: list[dict[str, Any]] | None = None,
) -> list[CityAqiResult]:
    """Acquire raw AQI for every city. Window comes from the client config."""
    client = client or AcquisitionBase()
    source = source or load_aqi_source()
    cities = cities or load_cities()
    window = client.config.window
    return [acquire_city(client, source, city, window) for city in cities]


def main() -> None:
    """Acquire all cities' AQI and print a one-line-per-city summary."""
    import time

    from app.logging_config import configure_logging

    client = AcquisitionBase()
    configure_logging(client.config.log_level)

    start = time.perf_counter()
    results = acquire_all(client)
    duration = time.perf_counter() - start

    for r in results:
        state = "cache" if r.from_cache else "downloaded"
        flags = []
        if r.clipped:
            flags.append("clipped")
        if r.partial_coverage:
            flags.append("partial")
        if r.missing_variables:
            flags.append(f"missing={r.missing_variables}")
        if r.structural_issues:
            flags.append(f"issues={r.structural_issues}")
        suffix = f"  [{', '.join(flags)}]" if flags else ""
        print(
            f"{r.city:11} {state:10} covered={r.covered_window[0]}..{r.covered_window[1]}"
            f" vars={r.present_variables}{suffix}"
        )

    report_path = paths.REPORTS_DIR / f"quality_{SOURCE_KEY}.json"
    report = new_report(SOURCE_KEY)
    report.add_stage(from_acquisition(results, duration_seconds=duration))
    paths.ensure_dir(paths.REPORTS_DIR)
    report.save(report_path)
    print(report.render_text())


if __name__ == "__main__":
    main()
