"""Pytest configuration for the ForeSeeMe backend.

Adds the ``backend/`` directory (this file's directory) to ``sys.path`` so the
tests can ``from app.schemas import ...`` whether pytest is invoked from the
repository root (``pytest backend/tests/test_schemas.py``) or from ``backend/``.
"""

import hashlib
import json
import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(__file__))


def pytest_addoption(parser):
    parser.addoption(
        "--require-frozen-ml-data",
        action="store_true",
        help="Fail dataset-dependent tests if a frozen ML input is missing.",
    )


@pytest.fixture
def frozen_ml_file(pytestconfig):
    """Use the actual frozen input when installed, with an explicit CI skip."""
    def require(path):
        if not path.is_file():
            message = f"Frozen ML input unavailable: {path.name}. See docs/ci.md."
            if pytestconfig.getoption("--require-frozen-ml-data"):
                pytest.fail(message)
            pytest.skip(message)
        return path

    return require


@pytest.fixture
def frozen_ml_split(frozen_ml_file):
    import pandas as pd
    from ml.pipelines import paths

    def load(split):
        path = frozen_ml_file({"train": paths.TRAIN_PATH, "test": paths.TEST_PATH}[split])
        # A split with missing or mismatched provenance is a failure, not an optional input.
        manifest = json.loads(paths.SPLIT_MANIFEST_PATH.read_text(encoding="utf-8"))
        with path.open("rb") as handle:
            actual = hashlib.file_digest(handle, "sha256").hexdigest()
            assert actual == manifest[f"{split}_sha256"], f"Frozen SHA-256 mismatch: {path}"
            handle.seek(0)
            return pd.read_parquet(handle)

    return load
