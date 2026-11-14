"""Focused independent inference tests; all I/O is local or fake."""
import json
from datetime import datetime, timezone

import numpy as np
import pytest

from app.disease_estimates import independent_estimates, SUPPORTED_DISEASES
from app.feature_builder import engineer_serving_features
from app.jobs.compute_risk import _document_body, estimate_for_city_full
from app.predict import classify_dominant, load_bundle, resolve_artifact_path
from app.schemas import RiskEstimateResponse
from tests.test_compute_risk import _fake_base

NOW = datetime(2026, 11, 14, tzinfo=timezone.utc)


class Pipeline:
    classes_ = np.array(['Medium', 'High', 'Low'])

    def __init__(self, row):
        self.row = row

    def predict_proba(self, _):
        return np.array([self.row])


def bundle():
    return dict(model_version='test', low_confidence_threshold=0.8,
                diseases=list(SUPPORTED_DISEASES), models={
                    'dengue': Pipeline([0.7, 0.2, 0.1]),
                    'smog': Pipeline([0.1, 0.85, 0.05]),
                    'influenza': Pipeline([0.2, 0.1, 0.7]),
                })


def test_independent_classes_confidence_and_order():
    b = bundle()
    before = classify_dominant(b, None)
    result = independent_estimates(b, None, NOW)
    assert [e['riskLevel'] for e in result] == ['Medium', 'High', 'Low']
    assert [e['confidence'] for e in result] == [0.7, 0.85, 0.7]
    assert result[0]['probabilities'] == dict(Medium=0.7, High=0.2, Low=0.1)
    assert [e['lowConfidence'] for e in result] == [True, False, True]
    assert all(e['modelVersion'] == 'test' and e['generatedAt'] == NOW.isoformat()
               for e in result)
    assert before == classify_dominant(b, None) == ('smog', 'High', 0.85)
    assert all('attributions' not in e for e in result)  # unsupported explanation


@pytest.mark.parametrize('row', [[float('nan'), 0, 1], [-0.1, 0.1, 1],
                                 [0.2, 0.2, 0.2], [0.5, 0.5], [0, 0, 1.1]])
def test_invalid_output_is_unavailable_never_low(row):
    b = bundle()
    b['models']['dengue'] = Pipeline(row)
    result = independent_estimates(b, None, NOW)
    assert result[0]['status'] == 'unavailable'
    assert 'riskLevel' not in result[0]
    assert result[1]['status'] == 'available'


def test_missing_model_and_invalid_class_are_explicit():
    b = bundle()
    del b['models']['dengue']
    b['models']['smog'].classes_ = ['Medium', 'Medium', 'Low']
    result = independent_estimates(b, None, NOW)
    assert [e['status'] for e in result] == ['unavailable', 'unavailable', 'available']


@pytest.mark.parametrize('city', ['Islamabad', 'Rawalpindi', 'Lahore', 'Karachi', 'Peshawar'])
def test_promoted_artifact_serialization_explanations_and_legacy(city):
    b = load_bundle(resolve_artifact_path())
    base = _fake_base(city)
    features = engineer_serving_features(base, b['feature_names']).sort_values(
        ['city', 'iso_year', 'week_of_year']).iloc[[-1]][b['feature_names']].astype(float)
    before = classify_dominant(b, features)
    full = estimate_for_city_full(b, city, base, NOW)
    body = _document_body(full)
    assert (full.response.disease.lower(), full.response.risk_level,
            full.response.confidence) == (before[0], before[1], round(before[2], 4))
    assert len(body['diseaseEstimates']) == 3
    for e in body['diseaseEstimates']:
        assert e['status'] == 'available'
        p = b['models'][e['disease']]
        actual = dict(zip(p.classes_, (round(float(v), 6) for v in p.predict_proba(features)[0])))
        assert e['probabilities'] == actual
        assert e['confidence'] == max(actual.values())
        assert e['modelVersion'] == body['modelVersion']
        assert datetime.fromisoformat(e['generatedAt']) == NOW
        assert e['attributions']['disease'] == e['disease']
        assert e['attributions']['predictedClass'] == e['riskLevel']
    assert len(json.dumps(body).encode()) < 32000  # ample Firestore 1 MiB headroom
    legacy = {k: v for k, v in body.items() if k != 'diseaseEstimates'}
    assert RiskEstimateResponse(**body) == RiskEstimateResponse(**legacy)
