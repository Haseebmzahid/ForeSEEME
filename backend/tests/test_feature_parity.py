"""Parity must compare raw inputs and expected features from one frozen generation."""

import hashlib
import json

import numpy as np
import pandas as pd
import pytest

from app import feature_builder, predict
from ml.pipelines import features, merge, paths


@pytest.mark.parametrize("split", ["train", "test"])
def test_frozen_inputs_reproduce_every_model_feature(frozen_weekly_base, split):
    manifest = json.loads((paths.PROCESSED_DIR / "split_manifest.json").read_text())
    path = paths.PROCESSED_DIR / f"{split}.parquet"
    # Expected vectors remain anchored to the immutable, manifest-verified split.
    assert hashlib.sha256(path.read_bytes()).hexdigest() == manifest[f"{split}_sha256"]
    expected = pd.read_parquet(path).set_index(features.KEY)
    bundle = predict.load_bundle(predict.resolve_artifact_path())
    assert bundle["reproducibility"][f"{split}_sha256"] == manifest[f"{split}_sha256"]
    columns = bundle["feature_names"]

    assert list(frozen_weekly_base.columns) == merge.COLUMNS
    assert not frozen_weekly_base.duplicated(features.KEY).any()
    # Preserve the history excluded from the split; train alone is not a base fixture.
    info = manifest["split"]
    assert len(frozen_weekly_base) == (
        info["train_rows"] + info["test_rows"] + info["excluded_insufficient_history_rows"]
    )
    actual = feature_builder.engineer_serving_features(frozen_weekly_base, columns)
    actual = actual.set_index(features.KEY).loc[expected.index, columns]
    assert actual.shape == expected[columns].shape
    assert np.allclose(actual.astype(float), expected[columns].astype(float), equal_nan=True)


def test_lahore_week_five_uses_frozen_aqi_and_prior_year_baseline(frozen_weekly_base):
    columns = ["us_aqi", "us_aqi_anom"]
    frozen = pd.read_parquet(paths.TRAIN_PATH).set_index(features.KEY)
    key = ("Lahore", 2024, 5)
    prior_key = ("Lahore", 2023, 5)
    raw = frozen_weekly_base.set_index(features.KEY)
    # Both the current observation and the prior-year baseline must be from the
    # frozen generation, not the independently refreshed acquisition cache.
    assert raw.loc[key, "us_aqi"] == frozen.loc[key, "us_aqi"]
    assert raw.loc[prior_key, "us_aqi"] == frozen.loc[prior_key, "us_aqi"]
    assert frozen.loc[key, "us_aqi_anom"] == (
        raw.loc[key, "us_aqi"] - raw.loc[prior_key, "us_aqi"]
    )
    bundle = predict.load_bundle(predict.resolve_artifact_path())
    actual = feature_builder.engineer_serving_features(
        frozen_weekly_base, bundle["feature_names"]
    ).set_index(features.KEY)
    np.testing.assert_array_equal(actual.loc[key, columns], frozen.loc[key, columns])
