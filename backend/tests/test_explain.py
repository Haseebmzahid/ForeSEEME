"""Tests for genuine feature attributions & confidence rationale
(Sprint 5, Prompt 5).

The attribution numbers must be **real** — an exact, additive decomposition of the
model's own probability — and deterministic. These tests assert:

- additivity: ``baseValue + Σ(every feature contribution) == confidence`` to
  machine precision (the stored top-N is only a slice of that full sum);
- the explained ``predictedClass`` / ``confidence`` match what the model predicts;
- determinism: identical input → byte-identical attributions;
- direction/magnitude are coherent (sign ⇔ direction, magnitude ⇔ |contribution|);
- the confidence rationale is derived from the class distribution (margin) and the
  forest (agreement), with a sensible qualitative strength;
- the whole thing serialises to a JSON-friendly additive object.
"""

from __future__ import annotations

import numpy as np
import pandas as pd
import pytest

from app import explain
from app.explain import AttributionSet, compute_attributions
from app.feature_builder import engineer_serving_features
from app.predict import (
    classify_dominant,
    load_bundle,
    resolve_artifact_path,
    resolve_low_confidence_threshold,
)

BUNDLE = load_bundle(resolve_artifact_path())
FEATURES = BUNDLE["feature_names"]


def _base(city: str = "Lahore", n_weeks: int = 10, start_week: int = 10) -> pd.DataFrame:
    """A trailing window of plausible weekly base rows (mirrors the job fixture)."""
    rows = []
    for i in range(n_weeks):
        rows.append({
            "city": city,
            "iso_year": 2026,
            "week_of_year": start_week + i,
            "days_in_week": 7,
            "temperature": 20.0 + i,
            "humidity": 55.0 + (i % 5),
            "precipitation": 3.0 + (i % 4),
            "pm2_5": 30.0 + i,
            "pm10": 50.0 + i,
            "us_aqi": 90.0 + 2 * i,
            "aqi_available": True,
        })
    return pd.DataFrame(rows)


def _latest_features(base: pd.DataFrame) -> pd.DataFrame:
    engineered = engineer_serving_features(base, FEATURES).sort_values(
        ["city", "iso_year", "week_of_year"]
    )
    return engineered.iloc[[-1]][FEATURES].astype(float)


def _dominant(base: pd.DataFrame) -> tuple[str, pd.DataFrame]:
    feats = _latest_features(base)
    disease, _level, _conf = classify_dominant(BUNDLE, feats)
    return disease, feats


# --- Additivity: the decomposition is exact (the core "genuine" guarantee) ---


def test_full_contributions_sum_to_confidence_exactly() -> None:
    """base + Σ(ALL feature contributions) == the predicted-class probability.

    This is the property that makes the attribution genuine rather than
    hand-authored: it reconstructs the model's own output exactly.
    """
    for disease in BUNDLE["diseases"]:
        feats = _latest_features(_base())
        pipeline = BUNDLE["models"][disease]
        rf = pipeline.named_steps["rf"]
        proba = pipeline.predict_proba(feats)[0]
        top_idx = int(np.argmax(proba))

        transformed = pipeline[:-1].transform(feats)
        base, contribs, _votes = explain._forest_decomposition(
            rf, transformed[0], len(FEATURES)
        )
        recon = base[top_idx] + contribs[:, top_idx].sum()
        assert recon == pytest.approx(proba[top_idx], abs=1e-9)


def test_stored_base_plus_all_contributions_recovers_confidence() -> None:
    """Using the public API's baseValue + the FULL contribution vector (not just the
    stored top-N) recovers the reported confidence."""
    disease, feats = _dominant(_base())
    # Ask for every feature so the stored slice is the whole sum.
    att = compute_attributions(BUNDLE, disease, feats, top_n=len(FEATURES))
    total = att.base_value + sum(c.contribution for c in att.top_contributors)
    assert total == pytest.approx(att.confidence_rationale.confidence, abs=1e-4)


# --- Alignment with the model's actual prediction ---------------------------


def test_predicted_class_and_confidence_match_the_model() -> None:
    disease, feats = _dominant(_base())
    pipeline = BUNDLE["models"][disease]
    proba = pipeline.predict_proba(feats)[0]
    classes = list(pipeline.named_steps["rf"].classes_)
    expected_class = classes[int(np.argmax(proba))]
    expected_conf = float(np.max(proba))

    att = compute_attributions(BUNDLE, disease, feats)
    assert att.predicted_class == expected_class
    assert att.confidence_rationale.confidence == pytest.approx(round(expected_conf, 4))
    assert att.disease == disease
    assert att.model_version == BUNDLE["model_version"]
    assert att.method == explain.METHOD


# --- Determinism ------------------------------------------------------------


def test_deterministic_for_fixed_input() -> None:
    disease, feats = _dominant(_base())
    first = compute_attributions(BUNDLE, disease, feats).model_dump(by_alias=True)
    second = compute_attributions(BUNDLE, disease, feats).model_dump(by_alias=True)
    assert first == second


# --- Top contributors: shape, ranking, direction/magnitude coherence --------


def test_top_contributors_are_ranked_and_coherent() -> None:
    disease, feats = _dominant(_base())
    att = compute_attributions(BUNDLE, disease, feats, top_n=6)

    assert len(att.top_contributors) == 6
    magnitudes = [c.magnitude for c in att.top_contributors]
    assert magnitudes == sorted(magnitudes, reverse=True)  # ranked by |contribution|

    for c in att.top_contributors:
        assert c.feature in FEATURES
        assert c.magnitude == pytest.approx(abs(c.contribution))
        assert c.direction == ("increases" if c.contribution >= 0 else "decreases")
        assert not np.isnan(c.value)  # real (imputed) value the model saw


def test_top_n_is_respected_and_capped() -> None:
    disease, feats = _dominant(_base())
    assert len(compute_attributions(BUNDLE, disease, feats, top_n=3).top_contributors) == 3
    big = compute_attributions(BUNDLE, disease, feats, top_n=999)
    assert len(big.top_contributors) == len(FEATURES)  # capped at available features


# --- Confidence rationale ---------------------------------------------------


def test_confidence_rationale_margin_and_agreement() -> None:
    disease, feats = _dominant(_base())
    pipeline = BUNDLE["models"][disease]
    proba = np.sort(pipeline.predict_proba(feats)[0])[::-1]

    r = compute_attributions(BUNDLE, disease, feats).confidence_rationale
    assert r.margin == pytest.approx(round(float(proba[0] - proba[1]), 4))
    assert 0.0 <= r.agreement <= 1.0
    assert 0.0 <= r.confidence <= 1.0
    assert r.runner_up_confidence <= r.confidence
    assert r.strength in {"strong", "moderate", "weak"}
    assert r.low_confidence == (r.confidence < resolve_low_confidence_threshold(BUNDLE))


def test_low_confidence_tracks_the_bundle_threshold_not_a_constant() -> None:
    """Sprint M6.1: `compute_attributions` must read the threshold off `bundle`,
    not a module-level constant — varying it (as a retrain with a different
    `config/model.yaml` value would) must change `lowConfidence` accordingly."""
    disease, feats = _dominant(_base())

    permissive = dict(BUNDLE)
    permissive["low_confidence_threshold"] = 0.0
    strict = dict(BUNDLE)
    strict["low_confidence_threshold"] = 1.0

    r_permissive = compute_attributions(permissive, disease, feats).confidence_rationale
    r_strict = compute_attributions(strict, disease, feats).confidence_rationale

    assert r_permissive.low_confidence is False
    assert r_strict.low_confidence is True
    assert r_permissive.confidence == r_strict.confidence  # unaffected by the threshold


def test_strength_bucketing_is_mechanical() -> None:
    # low confidence always weak, regardless of margin/agreement
    assert explain._strength(margin=0.9, agreement=0.9, low_confidence=True) == "weak"
    assert explain._strength(margin=0.6, agreement=0.8, low_confidence=False) == "strong"
    assert explain._strength(margin=0.3, agreement=0.2, low_confidence=False) == "moderate"
    assert explain._strength(margin=0.1, agreement=0.9, low_confidence=False) == "weak"


# --- Serialisation ----------------------------------------------------------


def test_serialises_to_json_friendly_additive_object() -> None:
    disease, feats = _dominant(_base())
    body = compute_attributions(BUNDLE, disease, feats).model_dump(
        by_alias=True, mode="json"
    )
    assert body["method"] == explain.METHOD
    assert set(body) == {
        "method", "modelVersion", "disease", "predictedClass",
        "baseValue", "topContributors", "confidenceRationale",
    }
    assert isinstance(body["topContributors"], list)
    rationale = body["confidenceRationale"]
    assert {"confidence", "predictedClass", "runnerUpClass", "runnerUpConfidence",
            "margin", "agreement", "strength", "lowConfidence"} == set(rationale)
    # round-trips back through the model
    assert AttributionSet(**body).method == explain.METHOD
