"""Data-quality observability layer for the ingestion pipeline (M5.2).

This module adds **visibility**, not validation: it aggregates figures the
pipeline already computes — acquisition's per-city results, cleaning's
``CityStats``/``VariableStats``, merge's column-missingness — into one
:class:`QualityReport` per dataset, persisted as JSON and rendered as a short
text summary. It never recomputes anything from raw data, never changes what
gets cleaned/dropped/imputed, and is never imported by ``features.py``,
``labels.py``, ``validate.py``, ``ml/training/``, or ``app/*`` (Module 6). If
this module disappeared, ingestion would behave identically; only visibility
into it would be lost.

Stage mapping (Goal 2 of M5.2): the pipeline does not have separate "parsing"
or "normalization" functions to instrument — parsing/structural-validation
happen inside acquisition (:func:`from_acquisition`) and normalization happens
inside cleaning (:func:`from_cleaning`), so their signals are folded into
those two stages' ``detail`` dicts rather than invented as new stages.

Honesty constraint: this pipeline never *drops* a row — cleaning flags
out-of-range/missing values as NaN and cleaning never shrinks the daily index,
merge's outer join never drops a week. So there is no real "rows
accepted/rejected" gate to report; ``rows_processed`` and the specific
existing counters (``missing_cells``, ``out_of_range_cells``,
``interpolated_cells``, ``duplicate_keys``, ...) are reported instead of a
fabricated accept/reject split. ``error_count`` is always 0 today because a
hard failure (e.g. an unknown city, an unreachable source) currently aborts
the run rather than being caught and counted — it is kept as a field so a
future soft-failure path has somewhere to report into, not because it is
observed today.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Protocol

from ml.pipelines.acquisition_base import write_raw_atomic

#: Bumped when the report's shape changes; recorded in every report and sidecar.
PIPELINE_VERSION = "m5.2"


# --- Duck-typed views onto existing result objects (no import-cycle risk) ---


class _AcquisitionResult(Protocol):
    clipped: bool
    from_cache: bool
    missing_variables: list[str]
    structural_issues: list[str]


class _VariableStats(Protocol):
    missing: int
    out_of_range: int
    interpolated: int


class _CityStats(Protocol):
    days: int
    variables: list[_VariableStats]
    aqi_available_days: int | None


# --- Model -------------------------------------------------------------------


@dataclass
class StageQuality:
    """Quality signal contributed by one pipeline stage, already computed."""

    stage: str  # "acquisition" | "cleaning" | "merge"
    duration_seconds: float
    warnings: int
    rows: int | None
    detail: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return {
            "stage": self.stage,
            "duration_seconds": round(self.duration_seconds, 3),
            "warnings": self.warnings,
            "rows": self.rows,
            "detail": self.detail,
        }

    @staticmethod
    def from_dict(raw: dict[str, Any]) -> "StageQuality":
        return StageQuality(
            stage=raw["stage"],
            duration_seconds=float(raw["duration_seconds"]),
            warnings=int(raw["warnings"]),
            rows=raw["rows"],
            detail=raw.get("detail", {}),
        )


@dataclass
class QualityReport:
    """Aggregated data-quality observability for one dataset's ingestion run.

    One report per source (``open_meteo_weather``, ``open_meteo_air_quality``)
    or per cross-source stage (``weekly_base`` for merge). Stages accumulate
    across separate process runs via :meth:`save`/:meth:`load` (re-running a
    stage replaces its own entry, matching the idempotent-update pattern
    already used by ``manifest.json``).
    """

    source: str
    generated_at: str
    pipeline_version: str = PIPELINE_VERSION
    stages: list[StageQuality] = field(default_factory=list)

    def add_stage(self, stage: StageQuality) -> None:
        """Add or replace (by stage name) one stage's contribution."""
        self.stages = [s for s in self.stages if s.stage != stage.stage] + [stage]
        self.generated_at = _utcnow_iso()

    @property
    def total_duration_seconds(self) -> float:
        return sum(s.duration_seconds for s in self.stages)

    @property
    def warning_count(self) -> int:
        return sum(s.warnings for s in self.stages)

    @property
    def error_count(self) -> int:
        # See module docstring: no soft-failure path exists yet upstream: a
        # hard failure currently aborts the run rather than being counted.
        return 0

    @property
    def rows_processed(self) -> int | None:
        """Rows processed by the most row-oriented stage present (cleaning/merge)."""
        for stage in reversed(self.stages):
            if stage.rows is not None:
                return stage.rows
        return None

    def to_dict(self) -> dict[str, Any]:
        return {
            "source": self.source,
            "generated_at": self.generated_at,
            "pipeline_version": self.pipeline_version,
            "rows_processed": self.rows_processed,
            "warning_count": self.warning_count,
            "error_count": self.error_count,
            "total_duration_seconds": round(self.total_duration_seconds, 3),
            "stages": [s.to_dict() for s in self.stages],
        }

    @staticmethod
    def from_dict(raw: dict[str, Any]) -> "QualityReport":
        return QualityReport(
            source=raw["source"],
            generated_at=raw["generated_at"],
            pipeline_version=raw.get("pipeline_version", PIPELINE_VERSION),
            stages=[StageQuality.from_dict(s) for s in raw.get("stages", [])],
        )

    def render_text(self) -> str:
        """Render the console/report summary block (Goal 3)."""
        bar = "=" * 44
        lines = [bar, f"{self.source} — Data Quality Report", bar]
        lines.append(f"Generated: {self.generated_at}")
        lines.append(f"Rows processed: {self.rows_processed}")
        lines.append(f"Warnings: {self.warning_count}")
        lines.append(f"Total duration: {self.total_duration_seconds:.2f}s")
        lines.append("")
        for stage in self.stages:
            lines.append(f"[{stage.stage}] duration={stage.duration_seconds:.2f}s "
                         f"warnings={stage.warnings}")
            for key, value in stage.detail.items():
                lines.append(f"  {key}: {value}")
        lines.append(bar)
        return "\n".join(lines)

    # -- persistence: JSON, atomic, idempotent stage-merge on re-run ---------

    def save(self, path: Path) -> None:
        """Merge this report's stages onto whatever is already on disk, atomically."""
        existing = QualityReport.load(path)
        merged = existing if existing is not None else self
        if existing is not None and existing is not self:
            for stage in self.stages:
                merged.add_stage(stage)
        merged.generated_at = _utcnow_iso()
        write_raw_atomic(
            path, (json.dumps(merged.to_dict(), indent=2, sort_keys=True) + "\n").encode()
        )

    @staticmethod
    def load(path: Path) -> "QualityReport | None":
        if not path.exists():
            return None
        return QualityReport.from_dict(json.loads(path.read_text(encoding="utf-8")))


def _utcnow_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def new_report(source: str) -> QualityReport:
    """Start a fresh in-memory report for ``source`` (before any stage is added)."""
    return QualityReport(source=source, generated_at=_utcnow_iso())


# --- Stage aggregators (pure aggregation of already-computed data) -----------


def from_acquisition(
    results: list[_AcquisitionResult], *, duration_seconds: float
) -> StageQuality:
    """Aggregate acquisition-stage quality from already-computed per-city results.

    Folds in what parsing + structural validation already detected
    (``missing_variables``, ``structural_issues``) — see module docstring.
    """
    cities = len(results)
    cache_hits = sum(1 for r in results if r.from_cache)
    clipped = sum(1 for r in results if r.clipped)
    missing_occurrences = sum(len(r.missing_variables) for r in results)
    structural_occurrences = sum(len(r.structural_issues) for r in results)
    warnings = clipped + missing_occurrences + structural_occurrences

    detail: dict[str, Any] = {
        "cities": cities,
        "cache_hits": cache_hits,
        "downloaded": cities - cache_hits,
        "clipped_windows": clipped,
        "missing_variable_occurrences": missing_occurrences,
        "structural_issue_occurrences": structural_occurrences,
    }
    partial = [r for r in results if hasattr(r, "partial_coverage")]
    if partial:
        n_partial = sum(1 for r in partial if getattr(r, "partial_coverage"))
        detail["partial_coverage_cities"] = n_partial
        warnings += n_partial

    return StageQuality(
        stage="acquisition", duration_seconds=duration_seconds, warnings=warnings,
        rows=None, detail=detail,
    )


def from_cleaning(stats: list[_CityStats], *, duration_seconds: float) -> StageQuality:
    """Aggregate cleaning-stage quality from already-computed CityStats/VariableStats.

    Folds in what the normalization/range/gap policy already detected
    (out-of-range values, interpolated cells) — see module docstring.
    """
    rows = sum(cs.days for cs in stats)
    missing = sum(v.missing for cs in stats for v in cs.variables)
    out_of_range = sum(v.out_of_range for cs in stats for v in cs.variables)
    interpolated = sum(v.interpolated for cs in stats for v in cs.variables)
    warnings = out_of_range  # out-of-range values are logged/flagged as anomalies

    detail: dict[str, Any] = {
        "cities": len(stats),
        "rows_processed": rows,
        "missing_cells": missing,
        "out_of_range_cells": out_of_range,
        "interpolated_cells": interpolated,
    }
    aqi_days = [cs.aqi_available_days for cs in stats if cs.aqi_available_days is not None]
    if aqi_days:
        detail["aqi_available_days"] = sum(aqi_days)

    return StageQuality(
        stage="cleaning", duration_seconds=duration_seconds, warnings=warnings,
        rows=rows, detail=detail,
    )


def from_merge(
    *,
    rows: int,
    cities: int,
    duplicate_keys: int,
    column_missing_pct: dict[str, float],
    duration_seconds: float,
) -> StageQuality:
    """Aggregate merge-stage quality from already-computed merge summary figures.

    Callers pass in numbers ``merge.py`` already computes (row count, city
    count, duplicate-key count, per-column missingness) — this function does
    not touch the DataFrame itself, so no extra pass over the data is added
    beyond merge.py's own (cheap, in-memory) summary computation.
    """
    warnings = duplicate_keys
    detail: dict[str, Any] = {
        "cities": cities,
        "duplicate_keys": duplicate_keys,
        "column_missing_pct": {k: round(v, 2) for k, v in column_missing_pct.items()},
    }
    return StageQuality(
        stage="merge", duration_seconds=duration_seconds, warnings=warnings,
        rows=rows, detail=detail,
    )
