"""Shared adapter helpers for the keyless HTTP JSON sources (M5.1).

``acquire_weather.py`` and ``acquire_aqi.py`` had each grown identical copies of
YAML loading, variable-spec derivation, coverage clipping, and variable-presence
checking. This module is the single place that logic lives now; both adapters
import from here instead of duplicating it. Nothing about their behaviour,
public API, or output changes — this is a pure extraction.

Also holds :func:`validate_payload_structure`, the one piece of *new* ingestion
validation this sprint adds: a raw Open-Meteo response is structurally sound
(matching time/value array lengths, parseable timestamps) before it is trusted
by the cleaning phase. Like the rest of the pipeline, it never raises — issues
are returned, logged, and recorded, never silently dropped.
"""

from __future__ import annotations

import datetime as dt
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml

from ml.pipelines.acquisition_base import Window

# --- YAML / raw-file loading -------------------------------------------------


def load_yaml(path: Path) -> dict[str, Any]:
    """Parse a YAML config file into a dict."""
    with path.open("r", encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def load_cities(path: Path) -> list[dict[str, Any]]:
    """Return the list of city dicts from ``cities.yaml``."""
    return load_yaml(path)["cities"]


def read_raw_json(path: Path) -> dict[str, Any]:
    """Read and parse a raw JSON blob written by ``fetch_with_cache``."""
    return json.loads(path.read_text(encoding="utf-8"))


# --- Variable model -----------------------------------------------------------


@dataclass(frozen=True)
class VariableSpec:
    """One retained source variable and how it is acquired."""

    name: str
    api_param: str
    granularity: str  # "daily" | "hourly"
    units: str


def variable_specs(
    source: dict[str, Any], *, default_granularity: str
) -> list[VariableSpec]:
    """Build the acquisition variable list from a source spec.

    Reads ``acquire_param`` / ``acquire_granularity`` per variable, defaulting to
    ``api_param`` at ``default_granularity`` (or the source's own declared
    ``granularity``, if present).
    """
    granularity = source.get("granularity", default_granularity)
    return [
        VariableSpec(
            name=name,
            api_param=var.get("acquire_param", var["api_param"]),
            granularity=var.get("acquire_granularity", granularity),
            units=var.get("units", ""),
        )
        for name, var in source["variables"].items()
    ]


# --- Window clipping ----------------------------------------------------------


def clip_to_coverage(window: Window, coverage: dict[str, Any]) -> tuple[Window, bool]:
    """Clip a requested window to a source's confirmed coverage.

    Never request dates the source cannot serve. Returns the (possibly clipped)
    window and a flag indicating whether clipping occurred. ISO ``YYYY-MM-DD``
    strings sort lexicographically, so plain string min/max is correct.
    """
    earliest = coverage.get("earliest_confirmed")
    latest = coverage.get("latest_confirmed")
    start = max(window.start, earliest) if earliest else window.start
    end = min(window.end, latest) if latest else window.end
    clipped = (start != window.start) or (end != window.end)
    return Window(start=start, end=end), clipped


# --- Variable presence --------------------------------------------------------


def check_variables(
    payload: dict[str, Any], specs: list[VariableSpec]
) -> tuple[list[str], list[str]]:
    """Split expected variables into (present, missing) for one response.

    A variable is *present* when its parameter key appears in the matching
    (daily/hourly) block. Absence is recorded, never silently dropped.
    """
    present: list[str] = []
    missing: list[str] = []
    for spec in specs:
        block = payload.get(spec.granularity, {}) or {}
        (present if spec.api_param in block else missing).append(spec.name)
    return present, missing


# --- Structural validation (new in M5.1) --------------------------------------


@dataclass(frozen=True)
class PayloadIssue:
    """One structural defect found in a raw response for one variable."""

    variable: str
    kind: str  # "length_mismatch" | "invalid_timestamp"
    detail: str

    def __str__(self) -> str:  # human-readable, used in logs/sidecars
        return f"{self.variable}: {self.kind} — {self.detail}"


def validate_payload_structure(
    payload: dict[str, Any], specs: list[VariableSpec]
) -> list[PayloadIssue]:
    """Structurally validate a raw response before it is trusted downstream.

    For every *present* variable (absence is already handled by
    :func:`check_variables`): the ``time`` and value arrays must be the same
    length, and every timestamp must parse as an ISO date. Never raises — a
    malformed variable is reported as an issue, not an exception, so one bad
    variable never aborts acquisition of the rest.
    """
    issues: list[PayloadIssue] = []
    for spec in specs:
        block = payload.get(spec.granularity, {}) or {}
        if spec.api_param not in block:
            continue
        times = block.get("time", []) or []
        values = block[spec.api_param] or []
        if len(times) != len(values):
            issues.append(
                PayloadIssue(
                    variable=spec.name,
                    kind="length_mismatch",
                    detail=(
                        f"time has {len(times)} points, "
                        f"{spec.api_param} has {len(values)} points"
                    ),
                )
            )
            continue
        bad = sum(1 for ts in times if not _is_iso_date(ts))
        if bad:
            issues.append(
                PayloadIssue(
                    variable=spec.name,
                    kind="invalid_timestamp",
                    detail=f"{bad} of {len(times)} timestamps are not valid ISO dates",
                )
            )
    return issues


def _is_iso_date(timestamp: str) -> bool:
    """True if the first 10 characters of ``timestamp`` parse as an ISO date."""
    try:
        dt.date.fromisoformat(str(timestamp)[:10])
        return True
    except ValueError:
        return False
