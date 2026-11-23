"""Inputs from the same generation as the frozen model-training datasets."""

import pandas as pd
import pytest

from ml.pipelines import merge, paths
from fastapi.testclient import TestClient

from app.inference_auth import require_inference_caller


@pytest.fixture(scope="module")
def prediction_client():
    """Exercise the prediction contract separately from signed-token tests."""
    def create(app):
        app.dependency_overrides[require_inference_caller] = lambda: None
        return TestClient(app, base_url="https://testserver")

    return create


@pytest.fixture
def frozen_weekly_base(frozen_ml_file) -> pd.DataFrame:
    """Recover raw inputs from the exact precursor consumed by validate.freeze.

    Acquisition/merge may refresh weekly_base independently of model training.
    The retained labelled precursor reproduces the frozen train/test split and
    includes the initial history rows excluded from that split. Pass only raw
    merge columns: serving must recompute every engineered feature itself.
    """
    path = frozen_ml_file(paths.INTERIM_DIR / "weekly_labelled.parquet")
    precursor = pd.read_parquet(path)
    return precursor.loc[:, merge.COLUMNS].copy()
