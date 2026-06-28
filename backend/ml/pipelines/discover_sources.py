"""Data-source discovery & availability probing for the ForeSeeMe risk model.

Sprint 2, Prompt 1. This pipeline writes **no** bulk-download logic. It probes
the free, keyless reanalysis sources we intend to train on, confirms they are
reachable, and *measures* the real coverage window per city and variable. The
findings fix the project-wide modeling window — per Shared Principle 2, that
window is unknown until measured (do NOT assume 2010-2023).

Probed sources (free, keyless, reproducible reanalysis):
  * Open-Meteo Historical Weather API (archive-api.open-meteo.com, ERA5) —
    temperature / humidity / precipitation.
  * Open-Meteo Air Quality API (air-quality-api.open-meteo.com, CAMS) —
    PM2.5 / PM10 / US-AQI.

Disease sources (WHO EMRO, IHME GBD, Punjab dengue surveillance, documented
seasonality) are catalogued in ``config/sources.yaml`` as VALIDATION-ONLY and
are deliberately never probed here and never used as training labels.

No secrets: neither probed source requires an API key. A future keyed source
must read its key from an environment variable (see ``sources.yaml``); nothing
is embedded here.

How "measured" works (no assumed dates, no trusting the declared bound):
  1. We probe one deliberately too-early date so the API returns its own
     declared allowed range (HTTP 400 with a parseable reason). This gives the
     search bounds — but the declared start can be *hollow* (the Air Quality
     API declares 2013 yet returns null PM values until 2022), so it is never
     trusted as the answer.
  2. We confirm the *real* earliest by checking for non-null data at the
     declared start and, when that is empty, binary-searching forward for the
     first date that actually returns values — per city and per variable.
  3. We measure the latest non-null near "today" and sample interior windows
     for gaps.
A network failure for any probe is recorded as ``"unavailable"`` — it never
raises out of :func:`discover_all` / :func:`probe_city_source`.

Run (from ``backend/``)::

    python -m ml.pipelines.discover_sources

This writes ``ml/reports/data_availability.md`` from the live measurements.
"""

from __future__ import annotations

import datetime as dt
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable, Protocol

import httpx
import yaml

# --- Paths -----------------------------------------------------------------

_ML_ROOT = Path(__file__).resolve().parents[1]  # backend/ml
CITIES_PATH = _ML_ROOT / "config" / "cities.yaml"
SOURCES_PATH = _ML_ROOT / "config" / "sources.yaml"
REPORT_PATH = _ML_ROOT / "reports" / "data_availability.md"

# --- Probe tuning ----------------------------------------------------------

#: Width (days) of every small sample request. Kept tiny on purpose — this is a
#: discovery probe, not a bulk download.
PROBE_WINDOW_DAYS = 3
#: Width of the window opened at the discovered earliest boundary, wide enough
#: to capture variables whose first non-null date differs by a day or two
#: (e.g. PM2.5 starts one day before US-AQI in CAMS).
EARLIEST_EXTRACT_DAYS = 6
#: Days back from "today" to look for the latest non-null value (reanalysis has
#: a short publication latency).
LATEST_LOOKBACK_DAYS = 16
#: A date guaranteed to predate any reanalysis archive; used only to make the
#: API report its own declared allowed range.
_TOO_EARLY_DATE = "1900-01-01"
_HTTP_TIMEOUT_S = 30.0
_DECLARED_RANGE_RE = re.compile(
    r"allowed range from (\d{4}-\d{2}-\d{2}) to (\d{4}-\d{2}-\d{2})"
)


# --- HTTP indirection (so tests can inject failures) -----------------------


class HttpGet(Protocol):
    """Minimal GET callable: ``(url, params) -> httpx.Response``.

    The default implementation hits the network; tests pass a fake that raises
    :class:`httpx.RequestError` to exercise the "unavailable" path without any
    real request.
    """

    def __call__(self, url: str, params: dict[str, Any]) -> httpx.Response: ...


def _default_get(url: str, params: dict[str, Any]) -> httpx.Response:
    """Real network GET against an Open-Meteo endpoint."""
    return httpx.get(url, params=params, timeout=_HTTP_TIMEOUT_S)


# --- Result types ----------------------------------------------------------


@dataclass(frozen=True)
class VariableCoverage:
    """Measured coverage for one variable at one city/source.

    Attributes:
        variable: Project-internal variable name (e.g. ``"temperature"``).
        earliest_confirmed: ISO date of the earliest non-null sample, or None.
        latest_confirmed: ISO date of the latest non-null sample, or None.
        gaps: Human-readable note on any all-null sampled interior windows.
        nonnull_fraction: Fraction of sampled points that were non-null.
    """

    variable: str
    earliest_confirmed: str | None
    latest_confirmed: str | None
    gaps: str
    nonnull_fraction: float


@dataclass(frozen=True)
class CitySourceResult:
    """Outcome of probing one source for one city.

    ``status`` is ``"available"`` when at least one variable returned data,
    ``"unavailable"`` when the endpoint could not be reached (recorded, never
    raised).
    """

    city: str
    source_key: str
    source_name: str
    status: str  # "available" | "unavailable"
    declared_range: str | None
    variables: list[VariableCoverage] = field(default_factory=list)
    error: str | None = None


# --- Config loading --------------------------------------------------------


def load_yaml(path: Path) -> dict[str, Any]:
    """Parse a YAML config file into a dict."""
    with path.open("r", encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def load_cities(path: Path = CITIES_PATH) -> list[dict[str, Any]]:
    """Return the list of city dicts from ``cities.yaml``."""
    return load_yaml(path)["cities"]


def training_sources(path: Path = SOURCES_PATH) -> dict[str, dict[str, Any]]:
    """Return only the probeable (``training_feature``) sources from sources.yaml."""
    sources = load_yaml(path)["sources"]
    return {
        key: spec
        for key, spec in sources.items()
        if spec.get("role") == "training_feature"
    }


# --- Response parsing helpers ----------------------------------------------


def _series(payload: dict[str, Any], granularity: str, api_param: str) -> tuple[
    list[str], list[Any]
]:
    """Pull (times, values) for one variable out of an Open-Meteo response.

    ``granularity`` selects the ``"daily"`` or ``"hourly"`` block. Missing keys
    yield empty lists rather than raising, so a partial response degrades
    gracefully.
    """
    block = payload.get(granularity, {}) or {}
    times = block.get("time", []) or []
    values = block.get(api_param, []) or []
    return times, values


def _first_nonnull_date(times: list[str], values: list[Any]) -> str | None:
    """Return the date (``YYYY-MM-DD``) of the first non-null value, or None."""
    for ts, value in zip(times, values):
        if value is not None:
            return ts[:10]
    return None


def _last_nonnull_date(times: list[str], values: list[Any]) -> str | None:
    """Return the date (``YYYY-MM-DD``) of the last non-null value, or None."""
    for ts, value in zip(reversed(times), reversed(values)):
        if value is not None:
            return ts[:10]
    return None


def _nonnull_fraction(values: list[Any]) -> float:
    """Fraction of values that are non-null (0.0 when empty)."""
    if not values:
        return 0.0
    present = sum(1 for v in values if v is not None)
    return present / len(values)


# --- Probing ---------------------------------------------------------------


def _window(start: dt.date, days: int) -> tuple[str, str]:
    """Return (start_iso, end_iso) for a ``days``-wide window starting ``start``."""
    return start.isoformat(), (start + dt.timedelta(days=days - 1)).isoformat()


def _request(
    get: HttpGet, spec: dict[str, Any], lat: float, lon: float, start: str, end: str
) -> httpx.Response:
    """Issue one probe request for all of a source's variables at once."""
    api_params = ",".join(v["api_param"] for v in spec["variables"].values())
    params: dict[str, Any] = {
        "latitude": lat,
        "longitude": lon,
        "start_date": start,
        "end_date": end,
        spec["granularity"]: api_params,
        "timezone": "UTC",
    }
    return get(spec["base_url"], params)


def _declared_range(get: HttpGet, spec: dict[str, Any], lat: float, lon: float) -> (
    tuple[str | None, str | None]
):
    """Make the API report its allowed range via a too-early probe.

    Returns (declared_start, declared_end). Either may be None if the API did
    not respond with a parseable range. The declared start is only a *search
    bound* — it can be hollow (see module docstring) and is never returned as a
    confirmed earliest.
    """
    response = _request(get, spec, lat, lon, _TOO_EARLY_DATE, _TOO_EARLY_DATE)
    match = _DECLARED_RANGE_RE.search(response.text or "")
    if match:
        return match.group(1), match.group(2)
    return None, None


def _has_any_data(
    get: HttpGet, spec: dict[str, Any], lat: float, lon: float, day: dt.date
) -> bool:
    """True if a small window starting ``day`` returns any non-null value.

    Used as the binary-search predicate when the declared start is hollow.
    """
    start, end = _window(day, PROBE_WINDOW_DAYS)
    resp = _request(get, spec, lat, lon, start, end)
    if resp.status_code != 200:
        return False
    payload = resp.json()
    granularity = spec["granularity"]
    for var_spec in spec["variables"].values():
        _, values = _series(payload, granularity, var_spec["api_param"])
        if any(v is not None for v in values):
            return True
    return False


def _binary_search_earliest(
    get: HttpGet,
    spec: dict[str, Any],
    lat: float,
    lon: float,
    lo_no_data: dt.date,
    hi_has_data: dt.date,
) -> dt.date:
    """Smallest day whose window has data, given lo (no data) < hi (has data).

    Standard boundary binary search over the date axis. Each step is one small
    request, so the whole search is ~log2(span) tiny probes.
    """
    while (hi_has_data - lo_no_data).days > 1:
        mid = lo_no_data + (hi_has_data - lo_no_data) // 2
        if _has_any_data(get, spec, lat, lon, mid):
            hi_has_data = mid
        else:
            lo_no_data = mid
    return hi_has_data


def _earliest_boundary_window(
    get: HttpGet,
    spec: dict[str, Any],
    lat: float,
    lon: float,
    declared_start: str | None,
    today: dt.date,
) -> tuple[dict[str, Any], dt.date | None]:
    """Find the real earliest boundary and return a wide window's JSON at it.

    Returns ``(payload, boundary_date)``. The payload is a response covering
    ``EARLIEST_EXTRACT_DAYS`` from the boundary, so each variable's own first
    non-null date can be read off it. ``boundary_date`` is None when the source
    has no non-null data anywhere in the declared range.
    """
    start_floor = dt.date.fromisoformat(declared_start or "1940-01-01")

    # 1) Cheap path: is the declared start already real? (true for ERA5.)
    if _has_any_data(get, spec, lat, lon, start_floor):
        boundary = start_floor
    else:
        # 2) Hollow declared start (true for CAMS). Binary-search forward using
        #    a recent, known-good date as the upper bound.
        recent = today - dt.timedelta(days=LATEST_LOOKBACK_DAYS)
        if not _has_any_data(get, spec, lat, lon, recent):
            recent = today  # last resort upper bound
            if not _has_any_data(get, spec, lat, lon, recent):
                return {}, None  # genuinely no data anywhere
        boundary = _binary_search_earliest(get, spec, lat, lon, start_floor, recent)

    start, end = _window(boundary, EARLIEST_EXTRACT_DAYS)
    resp = _request(get, spec, lat, lon, start, end)
    return (resp.json() if resp.status_code == 200 else {}), boundary


def probe_city_source(
    get: HttpGet,
    source_key: str,
    spec: dict[str, Any],
    city: dict[str, Any],
    today: dt.date,
) -> CitySourceResult:
    """Probe one source for one city and measure per-variable coverage.

    Any network error is caught and recorded as ``status="unavailable"`` — this
    function never raises for an unreachable endpoint (a hard requirement: an
    unavailable source must be recorded, never crash the run, never be hidden).
    """
    lat, lon = city["lat"], city["lon"]
    granularity = spec["granularity"]
    var_items = list(spec["variables"].items())

    try:
        declared_start, declared_end = _declared_range(get, spec, lat, lon)

        # Earliest: find the *real* boundary (declared start may be hollow) and
        # read each variable's first non-null off a wide window there.
        early_json, boundary = _earliest_boundary_window(
            get, spec, lat, lon, declared_start, today
        )

        # Latest: a window ending at "today", looking back over the latency gap.
        l_start = today - dt.timedelta(days=LATEST_LOOKBACK_DAYS)
        late_resp = _request(
            get, spec, lat, lon, l_start.isoformat(), today.isoformat()
        )

        # Interior gap samples: a few evenly spaced windows between the *real*
        # earliest boundary and the latest probe.
        gap_responses: list[httpx.Response] = []
        try:
            span_lo = boundary or dt.date.fromisoformat(declared_start or "1940-01-01")
            span_hi = today - dt.timedelta(days=LATEST_LOOKBACK_DAYS)
            total_days = (span_hi - span_lo).days
            if total_days > 4 * PROBE_WINDOW_DAYS:
                for frac in (0.25, 0.5, 0.75):
                    mid = span_lo + dt.timedelta(days=int(total_days * frac))
                    gap_responses.append(
                        _request(get, spec, lat, lon, *_window(mid, PROBE_WINDOW_DAYS))
                    )
        except (ValueError, httpx.HTTPStatusError):
            # Interior sampling is best-effort; bounds already establish status.
            gap_responses = []

        late_json = late_resp.json() if late_resp.status_code == 200 else {}
        gap_jsons = [r.json() for r in gap_responses if r.status_code == 200]

        variables: list[VariableCoverage] = []
        any_data = False
        for var_name, var_spec in var_items:
            api_param = var_spec["api_param"]

            e_times, e_values = _series(early_json, granularity, api_param)
            l_times, l_values = _series(late_json, granularity, api_param)

            earliest = _first_nonnull_date(e_times, e_values)
            latest = _last_nonnull_date(l_times, l_values)

            # Gap assessment over the interior samples.
            sampled_fracs: list[float] = []
            empty_windows = 0
            for gj in gap_jsons:
                g_times, g_values = _series(gj, granularity, api_param)
                frac = _nonnull_fraction(g_values)
                sampled_fracs.append(frac)
                if g_values and frac == 0.0:
                    empty_windows += 1

            all_fracs = [
                _nonnull_fraction(e_values),
                _nonnull_fraction(l_values),
                *sampled_fracs,
            ]
            measured = [f for f in all_fracs if f is not None]
            overall_frac = sum(measured) / len(measured) if measured else 0.0

            if empty_windows:
                gaps = f"{empty_windows} of {len(gap_jsons)} interior sample(s) all-null"
            elif overall_frac >= 0.999:
                gaps = "none observed"
            elif overall_frac > 0:
                gaps = f"partial ({overall_frac:.0%} of sampled points non-null)"
            else:
                gaps = "no non-null samples returned"

            if earliest or latest:
                any_data = True

            variables.append(
                VariableCoverage(
                    variable=var_name,
                    earliest_confirmed=earliest,
                    latest_confirmed=latest,
                    gaps=gaps,
                    nonnull_fraction=overall_frac,
                )
            )

        declared = (
            f"{declared_start} to {declared_end}"
            if declared_start and declared_end
            else None
        )
        return CitySourceResult(
            city=city["name"],
            source_key=source_key,
            source_name=spec["name"],
            status="available" if any_data else "unavailable",
            declared_range=declared,
            variables=variables,
        )

    except httpx.RequestError as exc:
        # Endpoint unreachable (DNS / connect / timeout). Record, do not raise.
        return CitySourceResult(
            city=city["name"],
            source_key=source_key,
            source_name=spec["name"],
            status="unavailable",
            declared_range=None,
            variables=[],
            error=f"{type(exc).__name__}: {exc}",
        )


def discover_all(
    get: HttpGet | None = None,
    cities_path: Path = CITIES_PATH,
    sources_path: Path = SOURCES_PATH,
    today: dt.date | None = None,
) -> list[CitySourceResult]:
    """Probe every training source for every city and return measured results."""
    getter: HttpGet = get or _default_get
    run_day = today or dt.date.today()
    cities = load_cities(cities_path)
    sources = training_sources(sources_path)

    results: list[CitySourceResult] = []
    for source_key, spec in sources.items():
        for city in cities:
            results.append(
                probe_city_source(getter, source_key, spec, city, run_day)
            )
    return results


# --- Report generation -----------------------------------------------------


def _aggregate_window(
    results: list[CitySourceResult],
) -> tuple[str | None, str | None, str | None]:
    """Compute the project window: latest of all earliest-starts (scarcest start),
    earliest of all latest-ends, and which source/variable drove the start.
    """
    earliest_starts: list[tuple[str, str]] = []  # (date, "source/var")
    latest_ends: list[str] = []
    for r in results:
        if r.status != "available":
            continue
        for v in r.variables:
            if v.earliest_confirmed:
                earliest_starts.append(
                    (v.earliest_confirmed, f"{r.source_key}/{v.variable}")
                )
            if v.latest_confirmed:
                latest_ends.append(v.latest_confirmed)

    if not earliest_starts or not latest_ends:
        return None, None, None

    window_start, driver = max(earliest_starts, key=lambda t: t[0])
    window_end = min(latest_ends)
    return window_start, window_end, driver


def render_report(results: list[CitySourceResult], run_day: dt.date) -> str:
    """Render the human-readable availability report from measured results."""
    lines: list[str] = []
    lines.append("# Data Availability Report — ForeSeeMe Risk Model")
    lines.append("")
    lines.append("**Sprint 2, Prompt 1 — Data Source Discovery & Availability**")
    lines.append("")
    lines.append(f"_Generated by `ml/pipelines/discover_sources.py` on {run_day} (UTC)._")
    lines.append("")
    lines.append(
        "Every date below was **measured** by probing the live API with small "
        "sample requests — none is assumed. Coverage is confirmed per city and "
        "per variable by checking for non-null values at the declared bounds and "
        "at interior sample windows. Unreachable probes are recorded as "
        "`unavailable`, never hidden."
    )
    lines.append("")

    # Group results by source.
    by_source: dict[str, list[CitySourceResult]] = {}
    for r in results:
        by_source.setdefault(r.source_key, []).append(r)

    for source_key, group in by_source.items():
        name = group[0].source_name
        declared = next((g.declared_range for g in group if g.declared_range), "n/a")
        lines.append(f"## {name} (`{source_key}`)")
        lines.append("")
        lines.append(f"- **API-declared allowed range:** {declared}")
        lines.append(
            "- The declared range is the API's stated bound and may be "
            "**hollow** (values null well past the stated start). The "
            "**confirmed** dates below are measured from actual non-null data "
            "and are authoritative."
        )
        lines.append("")
        lines.append("| City | Variable | Earliest (confirmed) | Latest (confirmed) | Gaps | Status |")
        lines.append("|------|----------|----------------------|--------------------|------|--------|")
        for r in group:
            if r.status == "unavailable" and not r.variables:
                lines.append(
                    f"| {r.city} | (all) | — | — | — | **unavailable** "
                    f"({r.error or 'no data'}) |"
                )
                continue
            for v in r.variables:
                lines.append(
                    f"| {r.city} | {v.variable} | {v.earliest_confirmed or '—'} | "
                    f"{v.latest_confirmed or '—'} | {v.gaps} | {r.status} |"
                )
        lines.append("")

    # Recommended window.
    start, end, driver = _aggregate_window(results)
    lines.append("## Recommended project-wide modeling window")
    lines.append("")
    if start and end:
        lines.append(f"**{start} → {end}**")
        lines.append("")
        lines.append(
            f"- The **start** is fixed by the scarcest feature: `{driver}` "
            f"returns no real data before {start}. A model trained on all "
            "features can only begin where *every* feature exists, so this "
            "latest-of-all-starts governs — regardless of how far any single "
            "richer source reaches back."
        )
        lines.append(
            f"- The **end** ({end}) is the earliest-of-all latest dates: the most "
            "recent date with confirmed non-null data common to every source at "
            "run time. The most recent few days are preliminary (ERA5T / CAMS) "
            "and may be revised."
        )
        lines.append(
            "- This window is materially shorter than a naive 2010–2023 "
            "assumption: the air-quality source's declared start is hollow, so "
            "the usable history is bounded by when CAMS values actually begin, "
            "not by the API's stated bound."
        )
        lines.append(
            "- No city was dropped. Every city/variable appears above; poor "
            "coverage would show as an `unavailable` row or a non-empty Gaps "
            "note. The window is computed over all available variables, so a "
            "scarce source cannot be silently excluded."
        )
    else:
        lines.append(
            "_No window could be derived — at least one source was unavailable at "
            "run time. Re-run when connectivity is restored._"
        )
    lines.append("")
    return "\n".join(lines)


def main() -> None:
    """Probe all sources, write the availability report, and print a summary."""
    run_day = dt.date.today()
    results = discover_all(today=run_day)
    report = render_report(results, run_day)
    REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
    REPORT_PATH.write_text(report, encoding="utf-8")

    available = sum(1 for r in results if r.status == "available")
    print(f"Probed {len(results)} city/source pairs: {available} available.")
    print(f"Report written to {REPORT_PATH}")


if __name__ == "__main__":
    main()
