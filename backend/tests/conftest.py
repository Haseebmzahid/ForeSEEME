"""Inputs from the same generation as the frozen model-training datasets."""

import pandas as pd
import pytest

from ml.pipelines import merge, paths


@pytest.fixture
def frozen_weekly_base() -> pd.DataFrame:
    """Recover raw inputs from the exact precursor consumed by validate.freeze.

    Acquisition/merge may refresh weekly_base independently of model training.
    The retained labelled precursor reproduces the frozen train/test split and
    includes the initial history rows excluded from that split. Pass only raw
    merge columns: serving must recompute every engineered feature itself.
    """
    precursor = pd.read_parquet(paths.INTERIM_DIR / "weekly_labelled.parquet")
    return precursor.loc[:, merge.COLUMNS].copy()
