"""Tests for the VALIDATION_ONLY disease reference and its import guard (Prompt 5).

Verifies:
- the reference data loads (in an allowed context);
- every reference entry carries a non-empty citation;
- the import guard raises if a feature / label / training module imports it.
"""

from __future__ import annotations

import importlib
import importlib.util
import sys

import pytest

MODULE = "ml.pipelines.acquire_disease_reference"


def _fresh_import():
    """Import the module fresh in this (allowed) test context."""
    sys.modules.pop(MODULE, None)
    return importlib.import_module(MODULE)


# --- Loads + every entry cited ---------------------------------------------


def test_reference_data_loads() -> None:
    mod = _fresh_import()
    document = mod.load_disease_reference()
    assert document["classification"] == "VALIDATION_ONLY"
    assert len(document["entries"]) >= 3
    # Mix of seasonal windows and documented outbreak years.
    signal_types = {e["signal_type"] for e in document["entries"]}
    assert "seasonal_window" in signal_types
    assert "documented_outbreak_year" in signal_types


def test_every_entry_carries_a_citation() -> None:
    mod = _fresh_import()
    document = mod.load_disease_reference()
    for entry in document["entries"]:
        cite = entry.get("citation")
        assert cite, f"entry {entry['id']} has no citation"
        assert cite.get("organization"), f"entry {entry['id']} citation has no organization"
        assert cite.get("basis"), f"entry {entry['id']} citation has no basis"
        assert cite.get("source_catalog_id"), f"entry {entry['id']} missing source_catalog_id"


def test_classification_flags_present() -> None:
    mod = _fresh_import()
    assert mod.VALIDATION_ONLY is True
    assert mod.CLASSIFICATION == "VALIDATION_ONLY"


# --- Import guard ----------------------------------------------------------


def _attempt_import_from_module(modname: str, tmp_path) -> None:
    """Import the reference module from a synthetic module named ``modname``.

    The synthetic module's name drives the guard, so naming it like a
    feature/label/training module must make the import raise.
    """
    src = tmp_path / f"{modname}.py"
    src.write_text(f"import {MODULE}\n", encoding="utf-8")
    # Force the guard to re-run by clearing any cached (allowed) import.
    sys.modules.pop(MODULE, None)
    spec = importlib.util.spec_from_file_location(modname, src)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[modname] = mod
    try:
        spec.loader.exec_module(mod)
    finally:
        sys.modules.pop(modname, None)
        sys.modules.pop(MODULE, None)


@pytest.mark.parametrize(
    "modname",
    ["foreseeme_feature_builder", "risk_label_generator", "train_risk_model"],
)
def test_import_guard_blocks_training_path_modules(modname, tmp_path) -> None:
    with pytest.raises(ImportError) as exc:
        _attempt_import_from_module(modname, tmp_path)
    assert "VALIDATION_ONLY" in str(exc.value)
    assert modname in str(exc.value)


def test_guard_allows_a_neutral_module(tmp_path) -> None:
    """A normally-named module (no feature/label/train token) may import it."""
    src = tmp_path / "validation_runner.py"
    src.write_text(f"import {MODULE} as r\nDOC = r.load_disease_reference()\n", encoding="utf-8")
    sys.modules.pop(MODULE, None)
    spec = importlib.util.spec_from_file_location("validation_runner", src)
    mod = importlib.util.module_from_spec(spec)
    sys.modules["validation_runner"] = mod
    try:
        spec.loader.exec_module(mod)  # must NOT raise
        assert mod.DOC["classification"] == "VALIDATION_ONLY"
    finally:
        sys.modules.pop("validation_runner", None)
        sys.modules.pop(MODULE, None)
