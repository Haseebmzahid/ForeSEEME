"""Genuine per-prediction feature attributions & confidence rationale
(Sprint 5, Prompt 5 — the Explainable AI layer).

This module turns each risk estimate from a black box into a legible one by
decomposing the model's *own* probability into per-feature contributions and a
confidence rationale — **all model-derived, never hand-authored or generated**.

Attribution method — exact additive tree-path decomposition
-----------------------------------------------------------
For a Random Forest, the predicted class probability is an exact, additive sum of
a base value plus one contribution per feature along each tree's decision path
(the *Saabas / treeinterpreter* local decomposition):

    predict_proba(class)  ==  base_value(class)  +  Σ feature_contribution(class)

This is the **equivalent genuine attribution** the Sprint 5 playbook permits in
place of SHAP TreeExplainer: it is exact for a Random Forest (additivity holds to
machine precision — see the test suite), fully deterministic for a fixed input,
and — decisively — it introduces **no new dependency** (only the fitted trees,
numpy, and pydantic), honouring CLAUDE.md's "do NOT introduce new libraries" while
still being a real, model-derived attribution. SHAP could later be swapped behind
this same stored contract without changing readers.

The decomposition is computed on the features **as the trees see them** — i.e.
after the Pipeline's ``impute`` (and ``scale``) steps — so the contributions
reflect the actual model. Each contribution is mapped back to its named feature
(the impute/scale steps are per-feature, so feature index ``i`` is preserved), and
the real-unit (post-impute, pre-scale) value the model saw is attached for
legibility.

Confidence rationale
--------------------
Derived from the same class distribution: the ``margin`` between the top and
runner-up class probabilities and the forest ``agreement`` (the fraction of trees
whose own vote matches the predicted class). Both are genuine model quantities.

Scope & safety
--------------
Pure computation: no I/O, no Firestore, no network, no generative path. It does
not import the VALIDATION_ONLY disease reference. The output is a Pydantic model
serialised **additively** onto the ``riskEstimates`` document (a new
``attributions`` field) — the frozen risk contract's existing fields are
untouched, and readers that ignore unknown fields (old app builds, old documents)
are unaffected.
"""

from __future__ import annotations

from typing import Any

import numpy as np
import pandas as pd
from pydantic import BaseModel, ConfigDict, Field
from sklearn.pipeline import Pipeline

#: Identifier for the attribution method stored on each estimate. Documents the
#: provenance of the numbers and lets a future method (e.g. SHAP) be distinguished
#: by readers without changing the field shape.
METHOD = "tree_path_contributions"

#: How many top drivers (by absolute contribution) to store per estimate. Kept
#: small so documents stay lean and the "why this prediction" surface stays
#: legible; the full 36-feature vector is not stored per estimate.
TOP_N_DEFAULT = 6

#: Reliability threshold shared with the frozen contract (RISK_SCHEMA.md): a top
#: confidence below this flags ``lowConfidence``. Mirrors
#: ``app.predict.LOW_CONFIDENCE_THRESHOLD`` (imported lazily to avoid a cycle).
LOW_CONFIDENCE_THRESHOLD = 0.55

# Qualitative strength buckets for the confidence rationale. Deterministic
# functions of genuine model quantities (margin + agreement) — a labelling of the
# numbers, not a fabricated judgement. Prompt 6 renders these mechanically.
_STRONG_MARGIN = 0.50
_STRONG_AGREEMENT = 0.75
_MODERATE_MARGIN = 0.25


# --- Additive field schema (additive; the frozen contract is untouched) ------


class FeatureContribution(BaseModel):
    """One feature's genuine, signed contribution to the predicted risk class.

    ``contribution`` is the exact additive increment this feature adds to the
    predicted class's probability (positive → pushed risk *toward* the predicted
    level, negative → *away*). ``magnitude`` is its absolute value (ranking key);
    ``direction`` names the sign; ``value`` is the real-unit feature value the
    model actually saw (post-imputation).
    """

    model_config = ConfigDict(populate_by_name=True)

    feature: str
    contribution: float
    magnitude: float
    direction: str  # "increases" | "decreases"
    value: float


class ConfidenceRationale(BaseModel):
    """Why confidence is high or low — from the model's class distribution.

    All fields are genuine model quantities: ``confidence`` is the top class
    probability, ``margin`` its lead over the runner-up class, and ``agreement``
    the fraction of trees whose vote matches the predicted class.
    """

    model_config = ConfigDict(populate_by_name=True)

    confidence: float
    predicted_class: str = Field(..., alias="predictedClass")
    runner_up_class: str = Field(..., alias="runnerUpClass")
    runner_up_confidence: float = Field(..., alias="runnerUpConfidence")
    margin: float
    agreement: float
    strength: str  # "strong" | "moderate" | "weak"
    low_confidence: bool = Field(..., alias="lowConfidence")


class AttributionSet(BaseModel):
    """The additive ``attributions`` field stored on a ``riskEstimate``.

    ``baseValue + Σ (every feature contribution) == confidence`` exactly (the
    stored ``topContributors`` are only the largest slice of that full sum).
    """

    model_config = ConfigDict(populate_by_name=True)

    method: str
    model_version: str = Field(..., alias="modelVersion")
    disease: str
    predicted_class: str = Field(..., alias="predictedClass")
    base_value: float = Field(..., alias="baseValue")
    top_contributors: list[FeatureContribution] = Field(..., alias="topContributors")
    confidence_rationale: ConfidenceRationale = Field(..., alias="confidenceRationale")


# --- Exact tree-path decomposition ------------------------------------------


def _leaf_path(tree: Any, x: np.ndarray) -> list[int]:
    """Node ids visited root→leaf for a single sample (deterministic traversal)."""
    node = 0
    nodes = [0]
    while tree.children_left[node] != -1:  # -1 == _tree.TREE_LEAF (i.e. not a leaf)
        feature = tree.feature[node]
        if x[feature] <= tree.threshold[node]:
            node = tree.children_left[node]
        else:
            node = tree.children_right[node]
        nodes.append(node)
    return nodes


def _forest_decomposition(
    rf: Any, x: np.ndarray, n_features: int
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Decompose the forest's probability for one sample.

    Returns ``(base_value, contributions, votes)`` where, per class:
    ``base_value + contributions.sum(axis=0) == rf.predict_proba([x])[0]`` exactly.
    ``votes`` counts, per class, how many trees' own argmax leaf falls on it (the
    forest agreement signal). Shapes: base ``(n_classes,)``, contributions
    ``(n_features, n_classes)``, votes ``(n_classes,)``.
    """
    n_classes = len(rf.classes_)
    base = np.zeros(n_classes)
    contributions = np.zeros((n_features, n_classes))
    votes = np.zeros(n_classes)

    for estimator in rf.estimators_:
        tree = estimator.tree_
        # Per-node class probabilities: normalise the (weighted) class counts. This
        # is exactly what a single tree's predict_proba returns at its leaf.
        value = tree.value.reshape(tree.node_count, -1)
        node_proba = value / value.sum(axis=1, keepdims=True)

        nodes = _leaf_path(tree, x)
        base += node_proba[nodes[0]]  # root distribution = this tree's bias
        for parent, child in zip(nodes[:-1], nodes[1:]):
            contributions[tree.feature[parent]] += node_proba[child] - node_proba[parent]
        votes[int(np.argmax(node_proba[nodes[-1]]))] += 1  # this tree's hard vote

    n_trees = len(rf.estimators_)
    return base / n_trees, contributions / n_trees, votes / n_trees


def _strength(margin: float, agreement: float, low_confidence: bool) -> str:
    """Bucket the confidence into strong / moderate / weak (mechanical)."""
    if low_confidence:
        return "weak"
    if margin >= _STRONG_MARGIN and agreement >= _STRONG_AGREEMENT:
        return "strong"
    if margin >= _MODERATE_MARGIN:
        return "moderate"
    return "weak"


# --- Public API -------------------------------------------------------------


def compute_attributions(
    bundle: dict[str, Any],
    disease_key: str,
    features: pd.DataFrame,
    *,
    top_n: int = TOP_N_DEFAULT,
) -> AttributionSet:
    """Genuine attributions + confidence rationale for one prediction.

    ``disease_key`` is the dominant disease already chosen for the estimate (so the
    explained ``predictedClass`` / ``confidence`` match the stored ``riskLevel`` /
    ``confidence``); ``features`` is the single-row, model-ordered engineered
    feature frame (the same one classified). Deterministic for a fixed input.
    """
    pipeline: Pipeline = bundle["models"][disease_key]
    feature_names: list[str] = bundle["feature_names"]
    rf = pipeline.named_steps["rf"]
    classes = list(rf.classes_)

    proba = pipeline.predict_proba(features)[0]
    top_idx = int(np.argmax(proba))
    predicted_class = str(classes[top_idx])
    confidence = float(proba[top_idx])

    order = np.argsort(proba)[::-1]
    runner_idx = int(order[1])
    runner_up_class = str(classes[runner_idx])
    runner_up_confidence = float(proba[runner_idx])
    margin = confidence - runner_up_confidence

    # Transform to the space the trees see (impute → scale) and keep the imputed
    # real-unit values for display. ``pipeline[:-1]`` is every step but the rf.
    transformed = pipeline[:-1].transform(features)
    imputed = pipeline.named_steps["impute"].transform(features)[0]

    base, contributions, votes = _forest_decomposition(
        rf, transformed[0], len(feature_names)
    )
    class_contrib = contributions[:, top_idx]
    base_value = float(base[top_idx])
    agreement = float(votes[top_idx])

    ranked = np.argsort(np.abs(class_contrib))[::-1][:top_n]
    top_contributors = [
        FeatureContribution(
            feature=feature_names[i],
            contribution=round(float(class_contrib[i]), 6),
            magnitude=round(float(abs(class_contrib[i])), 6),
            direction="increases" if class_contrib[i] >= 0 else "decreases",
            value=round(float(imputed[i]), 4),
        )
        for i in ranked
    ]

    low_confidence = confidence < LOW_CONFIDENCE_THRESHOLD
    rationale = ConfidenceRationale(
        confidence=round(confidence, 4),
        predicted_class=predicted_class,
        runner_up_class=runner_up_class,
        runner_up_confidence=round(runner_up_confidence, 4),
        margin=round(float(margin), 4),
        agreement=round(agreement, 4),
        strength=_strength(margin, agreement, low_confidence),
        low_confidence=low_confidence,
    )

    return AttributionSet(
        method=METHOD,
        model_version=bundle["model_version"],
        disease=disease_key,
        predicted_class=predicted_class,
        base_value=round(base_value, 6),
        top_contributors=top_contributors,
        confidence_rationale=rationale,
    )
