"""Additive independent intelligence; never changes dominant-risk selection."""
from __future__ import annotations

import logging
from datetime import datetime
from typing import Any

import numpy as np

from app.explain import compute_attributions
from app.predict import display_disease, resolve_low_confidence_threshold

SUPPORTED_DISEASES = ("dengue", "smog", "influenza")
LEVELS = {"Low", "Medium", "High"}
logger = logging.getLogger(__name__)


def independent_estimates(
    bundle: dict[str, Any], features: Any, generated_at: datetime,
) -> list[dict[str, Any]]:
    """Evaluate the same single feature row independently, with explicit failures.

    Confidence is the maximum *serving pipeline* class probability. No calibration
    is fitted here. A failure affects only the additive entry, never the summary.
    All entries inherit one model version and UTC computation timestamp.
    """
    results = []
    for disease in SUPPORTED_DISEASES:
        entry = {
            "disease": disease, "displayName": display_disease(disease),
            "modelVersion": bundle["model_version"],
            "generatedAt": generated_at.isoformat(),
            "status": "unavailable",
        }
        try:
            pipeline = bundle["models"][disease]
            classes = [str(c) for c in pipeline.classes_]
            probabilities = np.asarray(pipeline.predict_proba(features), dtype=float)
            if (len(classes) != 3 or set(classes) != LEVELS
                    or probabilities.shape != (1, 3)
                    or not np.isfinite(probabilities).all()
                    or (probabilities < 0).any() or (probabilities > 1).any()
                    or not np.isclose(probabilities.sum(), 1, atol=1e-6, rtol=0)):
                raise ValueError("Invalid independent class probabilities")
            row = probabilities[0]
            index = int(np.argmax(row))
            # Parallel forest reductions vary at machine epsilon. Quantize the
            # additive payload so identical daily reruns remain byte-identical.
            confidence = round(float(row[index]), 6)
            entry.update(
                status="available", riskLevel=classes[index],
                confidence=confidence,
                probabilities=dict(zip(classes, (round(float(v), 6) for v in row))),
                lowConfidence=confidence < resolve_low_confidence_threshold(bundle),
            )
        except Exception:
            logger.exception("independent_prediction_unavailable: %s", disease)
            results.append(entry)
            continue
        try:
            attribution = compute_attributions(bundle, disease, features)
            if (attribution.disease != disease
                    or attribution.model_version != entry["modelVersion"]
                    or attribution.predicted_class != entry["riskLevel"]
                    or abs(attribution.confidence_rationale.confidence - confidence) > 0.0001):
                raise ValueError("Attribution does not explain the serving output")
            entry["attributions"] = attribution.model_dump(by_alias=True, mode="json")
        except Exception:
            logger.exception("independent_explanation_unavailable: %s", disease)
        results.append(entry)
    return results
