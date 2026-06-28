"""Disease / seasonality reference — VALIDATION_ONLY (Sprint 2, Prompt 5).

This module encodes sparse, **public, citable** disease-seasonality signals for
Pakistan. Its sole purpose is to let a later phase (Prompt 12) check whether
generated risk labels are epidemiologically sensible. It is an external
*yardstick*, never a model input.

╔══════════════════════════════════════════════════════════════════════════╗
║  CLASSIFICATION: VALIDATION_ONLY                                          ║
║  This dataset MUST NEVER be used as a training feature or label. A guard  ║
║  below raises :class:`ValidationOnlyAccessError` (an ``ImportError``) if   ║
║  any feature / label / training module imports or loads it.              ║
╚══════════════════════════════════════════════════════════════════════════╝

Why this exists (the R1 reframe): generated labels need an independent
plausibility test. Known seasonality (dengue post-monsoon, Punjab smog winter,
influenza winter) and documented outbreak years are that test. Where only
*qualitative* seasonality is public, it is encoded here as a structured, sourced
table — every entry carries a citation. Nothing is fabricated: claims are
attributed to the responsible public-health / government body or to documented
seasonality, with canonical URLs where available.

Run (from ``backend/``)::

    python -m ml.pipelines.acquire_disease_reference
"""

from __future__ import annotations

import inspect
import json
import logging
from pathlib import Path
from typing import Any

from ml.pipelines import paths

logger = logging.getLogger("foreseeme.ml.disease_reference")

#: Machine-readable classification. Checked by tests and downstream code.
CLASSIFICATION = "VALIDATION_ONLY"
VALIDATION_ONLY = True

#: Date this reference was encoded (kept constant so the on-disk artifact is
#: reproducible across re-runs — this is a curated, committed dataset).
ENCODED_ON = "2026-06-28"

REFERENCE_DIR = paths.RAW_DIR / "disease_reference"
TABLE_PATH = REFERENCE_DIR / "seasonality.json"
SIDECAR_PATH = REFERENCE_DIR / "seasonality.sidecar.json"
NOTES_PATH = paths.REPORTS_DIR / "disease_reference_notes.md"


# ===========================================================================
# Import / access guard — structurally bars the training path
# ===========================================================================


class ValidationOnlyAccessError(ImportError):
    """Raised when feature/label/training code imports or loads this dataset.

    Subclasses :class:`ImportError` so it surfaces naturally when a forbidden
    module's ``import`` statement triggers it.
    """


#: A module is forbidden if its dotted name contains any of these tokens. These
#: name the training path: feature engineering, label generation, model training.
_FORBIDDEN_TOKENS = ("feature", "label", "train")


def _forbidden_caller() -> str | None:
    """Return the name of a forbidden module in the import/call stack, or None.

    Scans caller frames (skipping the stdlib import machinery and installed
    packages) and flags any whose *module name* indicates the training path.
    """
    for frame_info in inspect.stack():
        glb = frame_info.frame.f_globals
        name = (glb.get("__name__") or "")
        file = (glb.get("__file__") or "").replace("\\", "/")
        if not name or name.startswith("importlib") or "<frozen" in file:
            continue
        if "site-packages" in file or "/lib/python" in file:
            continue
        lowered = name.lower()
        if any(token in lowered for token in _FORBIDDEN_TOKENS):
            return name
    return None


def assert_validation_only_context() -> None:
    """Raise if a feature/label/training module is importing or loading this.

    Runs at import time (below) and again inside :func:`load_disease_reference`,
    so even a cached module cannot be loaded from the training path at runtime.
    """
    caller = _forbidden_caller()
    if caller is not None:
        raise ValidationOnlyAccessError(
            f"'{__name__}' is {CLASSIFICATION} and must never be imported or "
            f"used by feature/label/training code. Blocked caller: '{caller}'. "
            "Disease-seasonality signals validate label plausibility (Prompt 12) "
            "and are never training inputs."
        )


# Enforce on import.
assert_validation_only_context()


# ===========================================================================
# The encoded reference table (every entry is cited)
# ===========================================================================

_ALL_CITIES = ["Islamabad", "Rawalpindi", "Lahore", "Karachi", "Peshawar"]

#: Each entry MUST carry a non-empty ``citation`` with ``organization`` and
#: ``basis``. ``source_catalog_id`` links to a ``validation_only`` source in
#: config/sources.yaml for traceability. ``url`` is included only where a stable
#: canonical link is known; otherwise it is null and the basis stands alone.
_ENTRIES: list[dict[str, Any]] = [
    {
        "id": "dengue_post_monsoon",
        "disease": "Dengue",
        "signal_type": "seasonal_window",
        "months": [8, 9, 10, 11],
        "months_label": "August–November (post-monsoon)",
        "applies_to_cities": _ALL_CITIES,
        "description": (
            "Aedes aegypti dengue transmission rises after the monsoon, as "
            "standing water enables breeding; reported cases peak in the "
            "post-monsoon months (~Aug–Nov) and decline through winter. "
            "Strongest in Punjab and Sindh urban centres (Lahore, Rawalpindi, "
            "Islamabad, Karachi)."
        ),
        "citation": {
            "source_catalog_id": "who_emro",
            "organization": "WHO Regional Office for the Eastern Mediterranean (EMRO) — Pakistan",
            "url": "https://www.emro.who.int/pak/",
            "type": "public_health_authority",
            "basis": (
                "WHO EMRO Pakistan dengue situation updates and provincial "
                "surveillance consistently document a post-monsoon (Aug–Nov) "
                "seasonal peak in dengue transmission."
            ),
            "accessed": ENCODED_ON,
        },
        "additional_citations": [
            {
                "source_catalog_id": "punjab_dengue_surveillance",
                "organization": "Government of Punjab, Directorate General Health Services",
                "url": "https://dghs.punjab.gov.pk/",
                "type": "government_surveillance",
                "basis": "Provincial dengue surveillance reporting for Punjab.",
                "accessed": ENCODED_ON,
            }
        ],
    },
    {
        "id": "punjab_smog_winter",
        "disease": "Air-quality hazard (smog / particulate exposure)",
        "signal_type": "seasonal_window",
        "months": [10, 11, 12, 1],
        "months_label": "October–January (smog season)",
        "applies_to_cities": ["Lahore", "Rawalpindi", "Islamabad"],
        "description": (
            "Punjab's smog season runs roughly October–January, when cooler "
            "temperatures, low wind, temperature inversions and seasonal "
            "crop-residue burning trap particulates — elevating PM2.5/PM10 and "
            "associated respiratory risk, most severely in Lahore."
        ),
        "citation": {
            "source_catalog_id": "documented_seasonality",
            "organization": "Government of Punjab (Environmental Protection Department) — smog-season advisories; documented air-quality literature",
            "url": None,
            "type": "documented_seasonality",
            "basis": (
                "Government of Punjab smog advisories and published air-quality "
                "studies document a recurring Oct–Jan smog season over Punjab, "
                "centred on Lahore. URL omitted rather than cite a non-canonical "
                "link; attribution is to the responsible authority and "
                "documented seasonality."
            ),
            "accessed": ENCODED_ON,
        },
    },
    {
        "id": "influenza_winter",
        "disease": "Influenza (seasonal)",
        "signal_type": "seasonal_window",
        "months": [12, 1, 2],
        "months_label": "December–February (winter)",
        "applies_to_cities": _ALL_CITIES,
        "description": (
            "In Pakistan's northern subtropical/temperate climate, seasonal "
            "influenza activity rises in the colder months and peaks in winter "
            "(~Dec–Feb)."
        ),
        "citation": {
            "source_catalog_id": "documented_seasonality",
            "organization": "WHO Global Influenza Programme",
            "url": "https://www.who.int/teams/global-influenza-programme",
            "type": "public_health_authority",
            "basis": (
                "WHO influenza-seasonality guidance describes winter-peaking "
                "influenza activity in northern-hemisphere temperate/subtropical "
                "zones, which includes northern Pakistan."
            ),
            "accessed": ENCODED_ON,
        },
    },
    {
        "id": "dengue_epidemic_2011_punjab",
        "disease": "Dengue",
        "signal_type": "documented_outbreak_year",
        "year": 2011,
        "applies_to_cities": ["Lahore"],
        "description": (
            "2011 saw a major dengue epidemic in Punjab, centred on Lahore — "
            "one of the largest recorded dengue outbreaks in Pakistan. Recorded "
            "qualitatively (no case counts asserted here)."
        ),
        "citation": {
            "source_catalog_id": "who_emro",
            "organization": "WHO EMRO Pakistan / Government of Punjab dengue response",
            "url": "https://www.emro.who.int/pak/",
            "type": "public_health_authority",
            "basis": (
                "The 2011 Lahore/Punjab dengue epidemic is widely documented by "
                "WHO EMRO and the Government of Punjab as a major outbreak year."
            ),
            "accessed": ENCODED_ON,
        },
    },
    {
        "id": "dengue_surge_2019_pakistan",
        "disease": "Dengue",
        "signal_type": "documented_outbreak_year",
        "year": 2019,
        "applies_to_cities": ["Islamabad", "Rawalpindi", "Karachi", "Lahore"],
        "description": (
            "2019 saw a marked nationwide dengue surge across Pakistan, with "
            "notable activity around Islamabad/Rawalpindi and other cities. "
            "Recorded qualitatively."
        ),
        "citation": {
            "source_catalog_id": "who_emro",
            "organization": "WHO EMRO Pakistan",
            "url": "https://www.emro.who.int/pak/",
            "type": "public_health_authority",
            "basis": (
                "WHO EMRO Pakistan reporting documents an elevated 2019 dengue "
                "season nationally."
            ),
            "accessed": ENCODED_ON,
        },
    },
]


def _reference_document() -> dict[str, Any]:
    """Assemble the full, structured reference document."""
    return {
        "dataset": "disease_seasonality_reference",
        "classification": CLASSIFICATION,
        "purpose": (
            "Validate the epidemiological plausibility of generated risk labels "
            "(Prompt 12). NEVER a training feature or label."
        ),
        "barred_from": ["feature engineering", "label generation", "model training"],
        "region": "Pakistan — Islamabad, Rawalpindi, Lahore, Karachi, Peshawar",
        "encoded_on": ENCODED_ON,
        "version": 1,
        "entries": _ENTRIES,
    }


# ===========================================================================
# Loading (guarded) and persistence
# ===========================================================================


def load_disease_reference() -> dict[str, Any]:
    """Return the validation-only reference document.

    Re-checks the access guard at call time, so a forbidden module cannot reach
    the data even if this module was already imported in an allowed context.
    """
    assert_validation_only_context()
    return _reference_document()


def _write_atomic_text(path: Path, text: str) -> None:
    paths.ensure_dir(path.parent)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    tmp.replace(path)


def _sidecar(document: dict[str, Any]) -> dict[str, Any]:
    """Build the citations/provenance sidecar for the reference table."""
    citations: list[dict[str, Any]] = []
    for entry in document["entries"]:
        for cite in [entry["citation"], *entry.get("additional_citations", [])]:
            citations.append(
                {
                    "entry_id": entry["id"],
                    "disease": entry["disease"],
                    **cite,
                }
            )
    return {
        "dataset": document["dataset"],
        "classification": CLASSIFICATION,
        "purpose": document["purpose"],
        "barred_from": document["barred_from"],
        "guard": (
            "Importing or loading this dataset from a module whose name contains "
            "'feature', 'label' or 'train' raises ValidationOnlyAccessError."
        ),
        "encoded_on": document["encoded_on"],
        "entry_count": len(document["entries"]),
        "citation_count": len(citations),
        "citations": citations,
    }


def write_reference() -> dict[str, Path]:
    """Write the reference table, citations sidecar, and notes report.

    Deterministic: re-running produces byte-identical files (committed dataset).
    Returns the paths written.
    """
    document = _reference_document()
    _write_atomic_text(
        TABLE_PATH, json.dumps(document, indent=2, ensure_ascii=False) + "\n"
    )
    _write_atomic_text(
        SIDECAR_PATH,
        json.dumps(_sidecar(document), indent=2, ensure_ascii=False) + "\n",
    )
    _write_atomic_text(NOTES_PATH, render_notes(document))
    return {"table": TABLE_PATH, "sidecar": SIDECAR_PATH, "notes": NOTES_PATH}


# ===========================================================================
# Human-readable notes (reports/disease_reference_notes.md)
# ===========================================================================


def render_notes(document: dict[str, Any]) -> str:
    """Render the validation-only reference notes from the table."""
    lines: list[str] = []
    lines.append("# Disease & Seasonality Reference — VALIDATION ONLY")
    lines.append("")
    lines.append(f"> **CLASSIFICATION: {CLASSIFICATION}**")
    lines.append(">")
    lines.append(
        "> This dataset exists **solely** to validate the epidemiological "
        "plausibility of generated risk labels (Prompt 12). It is **never** a "
        "training feature or label. A code guard "
        "(`ValidationOnlyAccessError`) blocks any module named like "
        "`*feature*`, `*label*`, or `*train*` from importing or loading it."
    )
    lines.append("")
    lines.append(f"_Encoded {document['encoded_on']}. Region: {document['region']}._")
    lines.append("")
    lines.append(
        "Where only qualitative seasonality is public, it is encoded as a "
        "structured, sourced table. Every entry is attributed to the responsible "
        "public-health / government body or to documented seasonality — nothing "
        "here is fabricated, and no uncited claims are included."
    )
    lines.append("")
    lines.append("## Seasonal windows")
    lines.append("")
    lines.append("| Disease / signal | Window | Cities | Citation |")
    lines.append("|------------------|--------|--------|----------|")
    for e in document["entries"]:
        if e["signal_type"] != "seasonal_window":
            continue
        cite = e["citation"]
        link = f"[{cite['organization']}]({cite['url']})" if cite.get("url") else cite["organization"]
        cities = ", ".join(e["applies_to_cities"])
        lines.append(f"| {e['disease']} | {e['months_label']} | {cities} | {link} |")
    lines.append("")
    lines.append("## Documented outbreak years")
    lines.append("")
    lines.append("| Year | Disease | Region | Citation |")
    lines.append("|------|---------|--------|----------|")
    for e in document["entries"]:
        if e["signal_type"] != "documented_outbreak_year":
            continue
        cite = e["citation"]
        link = f"[{cite['organization']}]({cite['url']})" if cite.get("url") else cite["organization"]
        cities = ", ".join(e["applies_to_cities"])
        lines.append(f"| {e['year']} | {e['disease']} | {cities} | {link} |")
    lines.append("")
    lines.append("## Full citations")
    lines.append("")
    for e in document["entries"]:
        lines.append(f"- **{e['id']}** — {e['description']}")
        for cite in [e["citation"], *e.get("additional_citations", [])]:
            url = cite.get("url") or "(no canonical URL; attributed to authority/documented seasonality)"
            lines.append(
                f"  - {cite['organization']} — {cite['basis']} "
                f"(`{cite['source_catalog_id']}`) {url}"
            )
    lines.append("")
    lines.append("## How this is used (and not used)")
    lines.append("")
    lines.append(
        "- **Used** (Prompt 12 only): compare the seasonality/timing of generated "
        "labels against these windows and outbreak years to flag implausible "
        "output."
    )
    lines.append(
        "- **Never used**: as a feature, as a label, or anywhere in model "
        "training. The import guard enforces this structurally; see "
        "`acquire_disease_reference.py` and `test_disease_reference_guard.py`."
    )
    lines.append("")
    return "\n".join(lines)


def main() -> None:
    """Write the reference dataset, sidecar, and notes; print a summary."""
    from app.logging_config import configure_logging

    configure_logging("INFO")
    written = write_reference()
    document = _reference_document()
    logger.info(
        "disease_reference_written",
        extra={"entries": len(document["entries"]), "files": [str(p) for p in written.values()]},
    )
    for label, path in written.items():
        print(f"{label:8} -> {path}")
    print(f"entries: {len(document['entries'])} (all {CLASSIFICATION})")


if __name__ == "__main__":
    main()
