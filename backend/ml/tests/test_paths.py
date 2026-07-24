"""Tests for artifact-path resolution & semver ordering (Sprint M6.2).

Covers the deployment risk the Module 6 audit identified: "latest artifact"
selection must be semver-aware, never filename string order (which silently
misorders past a two-digit version component, e.g. ``"10.0.0" < "2.0.0"`` as
plain strings). These are unit tests of the primitives in ``ml.pipelines.paths``
— ``app/predict.py``'s integration with them is covered in
``backend/tests/test_api.py``.
"""

from __future__ import annotations

from pathlib import Path

import pytest

from ml.pipelines import paths


# --- is_semver ----------------------------------------------------------------


def test_is_semver_accepts_and_rejects() -> None:
    assert paths.is_semver("1.0.0")
    assert paths.is_semver("2.3.4-rc.1")
    assert not paths.is_semver("1.0")
    assert not paths.is_semver("v1.0.0")
    assert not paths.is_semver("rf-1.0.0")


# --- semver_sort_key: the actual bug the audit flagged ------------------------


def test_version_10_sorts_after_version_9() -> None:
    assert paths.semver_sort_key("10.0.0") > paths.semver_sort_key("9.0.0")
    # Documents *why* this matters: plain lexicographic string order gets it
    # backwards — "10.0.0" sorts BEFORE "9.0.0" as a string ('1' < '9'). This is
    # exactly the bug `resolve_artifact_path()` used to have.
    assert sorted(["10.0.0", "9.0.0"]) == ["10.0.0", "9.0.0"]


def test_version_2_sorts_before_version_10() -> None:
    assert paths.semver_sort_key("2.0.0") < paths.semver_sort_key("10.0.0")


def test_semver_sort_key_orders_major_minor_patch_numerically() -> None:
    versions = ["1.0.0", "1.10.0", "1.2.0", "10.0.0", "2.0.0", "1.0.10", "1.0.2"]
    ordered = sorted(versions, key=paths.semver_sort_key)
    assert ordered == ["1.0.0", "1.0.2", "1.0.10", "1.2.0", "1.10.0", "2.0.0", "10.0.0"]


def test_semver_sort_key_release_outranks_its_own_prereleases() -> None:
    assert paths.semver_sort_key("1.0.0-rc.1") < paths.semver_sort_key("1.0.0")
    assert paths.semver_sort_key("1.0.0-alpha") < paths.semver_sort_key("1.0.0")


def test_semver_sort_key_rejects_invalid_version() -> None:
    with pytest.raises(ValueError, match="not valid semver"):
        paths.semver_sort_key("not-a-version")


# --- model_artifact_version: filename parsing ----------------------------------


def test_model_artifact_version_parses_valid_filenames() -> None:
    assert paths.model_artifact_version(Path("model_1.0.0.joblib")) == "1.0.0"
    assert paths.model_artifact_version(Path("model_2.3.4-rc.1.joblib")) == "2.3.4-rc.1"


def test_model_artifact_version_rejects_non_matching_filenames() -> None:
    # Wrong prefix (e.g. the unversioned candidate artifact from training).
    assert paths.model_artifact_version(Path("candidate_model.joblib")) is None
    # Right prefix, non-semver suffix — a stray/malformed file, not a crash.
    assert paths.model_artifact_version(Path("model_bogus.joblib")) is None
    assert paths.model_artifact_version(Path("model_v1.0.0.joblib")) is None


# --- latest_model_artifact: the end-to-end selection ---------------------------


def _touch(dir_: Path, name: str) -> Path:
    p = dir_ / name
    p.write_bytes(b"")  # content is irrelevant to selection, only the filename is
    return p


def test_latest_model_artifact_picks_the_highest_semver_not_the_last_sorted_string(
    tmp_path: Path,
) -> None:
    """The exact scenario the audit flagged: a two-digit major version must win
    even though it sorts first as a plain string."""
    _touch(tmp_path, "model_1.0.0.joblib")
    _touch(tmp_path, "model_2.0.0.joblib")
    ten = _touch(tmp_path, "model_10.0.0.joblib")

    assert paths.latest_model_artifact(tmp_path) == ten


def test_latest_model_artifact_ignores_malformed_filenames(tmp_path: Path) -> None:
    good = _touch(tmp_path, "model_1.2.3.joblib")
    _touch(tmp_path, "model_bogus.joblib")           # not semver -> skipped
    _touch(tmp_path, "candidate_model.joblib")        # wrong prefix -> skipped
    _touch(tmp_path, "model_1.2.3.joblib.bak")        # wrong suffix -> skipped

    assert paths.latest_model_artifact(tmp_path) == good


def test_latest_model_artifact_returns_none_when_no_artifact_present(
    tmp_path: Path,
) -> None:
    assert paths.latest_model_artifact(tmp_path) is None


def test_latest_model_artifact_defaults_to_the_configured_artifacts_dir() -> None:
    """With no explicit ``artifacts_dir``, resolution falls back to
    ``paths.ARTIFACTS_DIR`` (env-overridable) — the same directory every other
    artifact-writing/reading module in the pipeline already uses."""
    result = paths.latest_model_artifact()
    if result is not None:  # environment-dependent: only assert *if* one exists
        assert result.parent == paths.ARTIFACTS_DIR
        assert paths.model_artifact_version(result) is not None
