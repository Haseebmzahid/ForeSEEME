"""Dataset lineage recording for Module 5 outputs (M5.4/M5.5).

Every parquet Module 5 writes — the per-city interim tables from ``clean.py``
and the final ``weekly_base`` table from ``merge.py`` — gets one lineage
entry recording what produced it, from what, and a checksum. Raw files
already have rich provenance via ``acquisition_base.py``'s ``manifest.json``;
this extends the same discipline to the downstream artifacts that had none.

Mirrors ``manifest.json``'s shape exactly — a dict of entries keyed by output
path, loaded/updated/saved atomically — rather than inventing a new pattern.
Reuses :func:`ml.pipelines.acquisition_base.sha256_file` for the checksum: no
second hashing implementation. Like ``quality_report.py``, this is
observability only: nothing in Module 6 imports it, and it never changes what
gets written to the parquet files themselves.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from ml.pipelines.acquisition_base import sha256_file, write_raw_atomic

#: Shape of the interim/weekly_base tables (columns, dtypes, key). Bump
#: manually if clean.py's or merge.py's output columns/dtypes change.
SCHEMA_VERSION = "1"

#: Ledger schema version, bumped if the entry shape changes (mirrors
#: acquisition_base.MANIFEST_VERSION's convention).
LEDGER_VERSION = 1


@dataclass(frozen=True)
class LineageRecord:
    """Provenance for one Module 5 output artifact."""

    dataset: str
    output_path: str
    sources: list[str]
    generated_at: str
    pipeline_version: str
    schema_version: str
    input_artifacts: list[str]
    row_count: int
    column_count: int
    sha256: str
    quality_report_path: str | None = None
    consumed_by: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "dataset": self.dataset,
            "output_path": self.output_path,
            "sources": self.sources,
            "generated_at": self.generated_at,
            "pipeline_version": self.pipeline_version,
            "schema_version": self.schema_version,
            "input_artifacts": self.input_artifacts,
            "row_count": self.row_count,
            "column_count": self.column_count,
            "sha256": self.sha256,
            "quality_report_path": self.quality_report_path,
            "consumed_by": self.consumed_by,
        }


def _utcnow_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _relpath(path: Path, data_dir: Path) -> str:
    """POSIX-style path relative to ``data_dir``, or the raw path if outside it."""
    try:
        return str(path.relative_to(data_dir)).replace("\\", "/")
    except ValueError:
        return str(path).replace("\\", "/")


def build_record(
    *,
    dataset: str,
    output_path: Path,
    data_dir: Path,
    sources: list[str],
    input_artifacts: list[Path],
    row_count: int,
    column_count: int,
    pipeline_version: str,
    quality_report_path: Path | None = None,
    consumed_by: str | None = None,
) -> LineageRecord:
    """Build a lineage record for an already-written output file.

    ``row_count``/``column_count`` must come from the DataFrame the caller
    already has in memory — this never re-reads the parquet to derive them.
    The checksum is the one new computation here, via the same
    :func:`sha256_file` acquisition_base.py already uses for raw files.
    """
    return LineageRecord(
        dataset=dataset,
        output_path=_relpath(output_path, data_dir),
        sources=sources,
        generated_at=_utcnow_iso(),
        pipeline_version=pipeline_version,
        schema_version=SCHEMA_VERSION,
        input_artifacts=[_relpath(p, data_dir) for p in input_artifacts],
        row_count=row_count,
        column_count=column_count,
        sha256=sha256_file(output_path),
        quality_report_path=(
            str(quality_report_path).replace("\\", "/") if quality_report_path else None
        ),
        consumed_by=consumed_by,
    )


def _empty_ledger() -> dict[str, Any]:
    return {"version": LEDGER_VERSION, "entries": {}}


def load_ledger(path: Path) -> dict[str, Any]:
    """Load the lineage ledger, or an empty one if it does not exist yet."""
    if not path.exists():
        return _empty_ledger()
    return json.loads(path.read_text(encoding="utf-8"))


def save_ledger(ledger: dict[str, Any], path: Path) -> None:
    """Write the ledger atomically and deterministically (sorted keys)."""
    text = json.dumps(ledger, indent=2, sort_keys=True) + "\n"
    write_raw_atomic(path, text.encode("utf-8"))


def record_lineage(path: Path, record: LineageRecord) -> dict[str, Any]:
    """Upsert one record into the ledger at ``path`` (idempotent on rerun)."""
    ledger = load_ledger(path)
    ledger["entries"][record.output_path] = record.to_dict()
    save_ledger(ledger, path)
    return ledger
