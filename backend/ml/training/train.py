"""Model training, hyperparameter tuning & temporal cross-validation
(Sprint 2, Prompt 11).

Trains the candidate Random Forest for ForeSeeMe. One self-contained sklearn
``Pipeline`` per disease family (dengue / smog / influenza) — imputation +
scaling + ``RandomForestClassifier`` — is tuned with a randomised search over a
**time-aware** ``TimeSeriesSplit`` (never plain K-fold: lagged features make a
shuffled split leak the future into the past). The three fitted Pipelines are
bundled into a single ``candidate_model.joblib`` behind one stable prediction
interface that returns ``RiskLevel`` / ``Confidence`` / ``ModelVersion`` (the
Sprint 1 contract).

Scope guardrails (enforced in code):

* Reads ``train.parquet`` ONLY. ``test.parquet`` is never opened here — the
  held-out evaluation is Prompt 12. (See :func:`load_train`.)
* Preprocessing lives INSIDE the Pipeline, so the saved artifact is
  self-sufficient at serving time (Prompt 14 loads it unchanged).
* Everything is seeded (forest, search sampler, per-fold clones): same seed ->
  same chosen hyperparameters -> same artifact.
* All hyperparameters and the search space come from ``config/model.yaml``.

This prompt produces the *candidate* artifact and a training log of the search
and the winner. It does not modify FastAPI, the Sprint 1 stub, or any serving
path — that is Prompt 14.

Run (from ``backend/``)::

    python -m ml.training.train
"""

from __future__ import annotations

import hashlib
import json
import logging
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import matplotlib

matplotlib.use("Agg")  # headless: write PNGs, never open a window
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
import pandas as pd  # noqa: E402
import sklearn  # noqa: E402
import yaml  # noqa: E402
from joblib import dump, load  # noqa: E402
from sklearn.base import clone  # noqa: E402
from sklearn.ensemble import RandomForestClassifier  # noqa: E402
from sklearn.impute import SimpleImputer  # noqa: E402
from sklearn.metrics import (  # noqa: E402
    accuracy_score,
    classification_report,
    confusion_matrix,
    f1_score,
    precision_score,
    recall_score,
    roc_auc_score,
)
from sklearn.model_selection import (  # noqa: E402
    GridSearchCV,
    RandomizedSearchCV,
    TimeSeriesSplit,
)
from sklearn.pipeline import Pipeline  # noqa: E402
from sklearn.preprocessing import StandardScaler  # noqa: E402

from ml.pipelines import paths  # noqa: E402

logger = logging.getLogger("foreseeme.ml.train")

KEY = ["iso_year", "week_of_year", "city"]
#: Severity order for the risk classes (the Sprint 1 ``riskLevel`` enum). Used
#: for fixed-order confusion matrices / reports; sklearn internally sorts classes
#: alphabetically, so proba columns are always remapped back to this order.
DEFAULT_CLASSES = ["Low", "Medium", "High"]


# --- Config -----------------------------------------------------------------


def load_model_config(path: Path | None = None) -> dict[str, Any]:
    """Load ``config/model.yaml`` (the single knob-board for training)."""
    path = path or paths.MODEL_PATH
    with Path(path).open("r", encoding="utf-8") as handle:
        return yaml.safe_load(handle)


# --- Feature selection ------------------------------------------------------


def select_feature_columns(df: pd.DataFrame, feat_cfg: dict[str, Any]) -> list[str]:
    """Resolve the model's feature columns from the config rules, in a stable order.

    Only the documented feature families are kept (raw same-week values, lags,
    rollings, anomalies, cyclical week encoding, city one-hots). Keys, QA/helper
    columns, validity flags, and every label/score/prob column are excluded by
    construction (they are simply never selected).
    """
    cols = list(df.columns)
    selected: list[str] = []

    def add(name: str) -> None:
        if name in df.columns and name not in selected:
            selected.append(name)

    for name in feat_cfg.get("raw", []):
        add(name)
    for pattern in feat_cfg.get("include_patterns", {}).values():
        rx = re.compile(pattern)
        for c in cols:
            if rx.search(c):
                add(c)
    for name in feat_cfg.get("cyclical", []):
        add(name)
    prefix = feat_cfg.get("city_onehot_prefix")
    if prefix:
        for c in cols:
            if c.startswith(prefix):
                add(c)
    if not selected:
        raise ValueError("feature selection resolved to zero columns")
    return selected


def feature_frame(df: pd.DataFrame, feature_names: list[str]) -> pd.DataFrame:
    """Project to the feature columns as floats (bool/int -> float; NaNs kept)."""
    return df[feature_names].astype(float)


# --- Estimator & CV ---------------------------------------------------------


def build_estimator(cfg: dict[str, Any]) -> Pipeline:
    """A single self-contained Pipeline: impute -> (optional) scale -> RF.

    Imputation is mandatory (first-cycle anomaly columns are NaN by design) and
    must live inside the Pipeline so serving imputes identically. Scaling is a
    no-op for trees but is included to satisfy the "scaling inside the Pipeline"
    contract and keep the artifact estimator-agnostic.
    """
    pre = cfg.get("preprocessing", {})
    rf_cfg = cfg.get("random_forest", {})
    steps: list[tuple[str, Any]] = [
        # keep_empty_features: in the earliest temporal CV folds the anomaly
        # columns are wholly NaN (first-cycle climatology); keeping them (filled
        # neutral) holds the feature space fixed across folds and at serving,
        # instead of silently dropping columns fold-to-fold.
        (
            "impute",
            SimpleImputer(
                strategy=pre.get("numeric_impute_strategy", "median"),
                keep_empty_features=True,
            ),
        ),
    ]
    if pre.get("scale", True):
        steps.append(("scale", StandardScaler()))
    steps.append(
        (
            "rf",
            RandomForestClassifier(
                class_weight=rf_cfg.get("class_weight", "balanced"),
                bootstrap=rf_cfg.get("bootstrap", True),
                n_jobs=rf_cfg.get("n_jobs", -1),
                random_state=int(cfg["random_state"]),
            ),
        )
    )
    return Pipeline(steps)


def build_cv(search_cfg: dict[str, Any]) -> TimeSeriesSplit:
    """Construct the temporal splitter. Rejects non-temporal splitters explicitly."""
    cv_cfg = search_cfg.get("cv", {})
    splitter = cv_cfg.get("splitter", "time_series")
    if splitter != "time_series":
        raise ValueError(
            f"temporal data requires a time-aware splitter; got {splitter!r}. "
            "Plain K-fold leaks the future into the past (Prompt 11 constraint)."
        )
    return TimeSeriesSplit(n_splits=int(cv_cfg.get("n_splits", 5)))


def time_sort(df: pd.DataFrame) -> pd.DataFrame:
    """Sort rows into strict temporal order so contiguous CV blocks are causal.

    ``TimeSeriesSplit`` slices the row index into ordered blocks; that is only a
    valid past->future split if the rows are time-ordered first. Ties within a
    week are ordered by city (deterministic, time-neutral).
    """
    return df.sort_values(KEY, kind="mergesort").reset_index(drop=True)


def _param_grid(search_cfg: dict[str, Any]) -> dict[str, list[Any]]:
    """Map config grid keys to the Pipeline's ``rf__<param>`` namespace."""
    return {f"rf__{k}": v for k, v in search_cfg["param_grid"].items()}


def run_search(
    estimator: Pipeline,
    X: pd.DataFrame,
    y: pd.Series,
    cfg: dict[str, Any],
) -> RandomizedSearchCV | GridSearchCV:
    """Tune ``estimator`` over the config search space with temporal CV."""
    search_cfg = cfg["search"]
    cv = build_cv(search_cfg)
    grid = _param_grid(search_cfg)
    seed = int(cfg["random_state"])
    method = search_cfg.get("method", "randomized")
    common = dict(
        estimator=estimator,
        scoring=search_cfg.get("scoring", "f1_macro"),
        cv=cv,
        refit=bool(search_cfg.get("refit", True)),
        n_jobs=search_cfg.get("n_jobs", -1),
    )
    if method == "grid":
        search: Any = GridSearchCV(param_grid=grid, **common)
    elif method == "randomized":
        search = RandomizedSearchCV(
            param_distributions=grid,
            n_iter=int(search_cfg.get("n_iter", 30)),
            random_state=seed,
            **common,
        )
    else:
        raise ValueError(f"unknown search.method {method!r} (use grid|randomized)")
    search.fit(X, y)
    return search


# --- Time-aware out-of-fold evaluation (train only) -------------------------


def _remap_proba(
    fold_proba: np.ndarray, fold_classes: np.ndarray, classes: list[str]
) -> np.ndarray:
    """Align a fold's proba columns to the fixed severity-ordered ``classes``."""
    out = np.zeros((fold_proba.shape[0], len(classes)), dtype=float)
    index = {c: i for i, c in enumerate(fold_classes)}
    for j, cls in enumerate(classes):
        if cls in index:
            out[:, j] = fold_proba[:, index[cls]]
    return out


@dataclass
class OOFResult:
    """Out-of-fold (temporal) predictions over the covered train rows."""

    y_true: np.ndarray
    y_pred: np.ndarray
    proba: np.ndarray            # shape (n_covered, n_classes), severity order
    classes: list[str]
    n_covered: int
    n_total: int


def temporal_oof(
    estimator: Pipeline,
    X: pd.DataFrame,
    y: pd.Series,
    cv: TimeSeriesSplit,
    classes: list[str],
) -> OOFResult:
    """Out-of-fold predictions under ``TimeSeriesSplit``.

    Each fold trains on its past block and predicts its (strictly later) test
    block; predictions are accumulated. This is an honest temporal generalisation
    estimate that never touches ``test.parquet``. The earliest block is never in
    any test fold, so it is (by construction) uncovered — reported as such.
    """
    Xv = X.reset_index(drop=True)
    yv = y.reset_index(drop=True).to_numpy()
    n = len(Xv)
    pred = np.empty(n, dtype=object)
    proba = np.zeros((n, len(classes)), dtype=float)
    covered = np.zeros(n, dtype=bool)

    for tr_idx, te_idx in cv.split(Xv):
        model = clone(estimator)
        model.fit(Xv.iloc[tr_idx], yv[tr_idx])
        pred[te_idx] = model.predict(Xv.iloc[te_idx])
        proba[te_idx] = _remap_proba(
            model.predict_proba(Xv.iloc[te_idx]), model.classes_, classes
        )
        covered[te_idx] = True

    return OOFResult(
        y_true=yv[covered],
        y_pred=pred[covered].astype(object),
        proba=proba[covered],
        classes=classes,
        n_covered=int(covered.sum()),
        n_total=n,
    )


def _multiclass_brier(y_true: np.ndarray, proba: np.ndarray, classes: list[str]) -> float:
    """Mean squared error between one-hot truth and predicted probabilities."""
    onehot = np.zeros_like(proba)
    index = {c: i for i, c in enumerate(classes)}
    for i, label in enumerate(y_true):
        onehot[i, index[label]] = 1.0
    return float(np.mean(np.sum((proba - onehot) ** 2, axis=1)))


def evaluate_oof(oof: OOFResult, low_conf_threshold: float) -> dict[str, Any]:
    """Full metric suite over the out-of-fold (temporal) train predictions."""
    classes = oof.classes
    yt, yp = oof.y_true, oof.y_pred
    report = classification_report(
        yt, yp, labels=classes, output_dict=True, zero_division=0
    )
    cm = confusion_matrix(yt, yp, labels=classes).tolist()

    present = set(yt)
    roc_auc: float | None = None
    if present.issuperset(classes):  # OvR macro AUC needs every class in truth
        # roc_auc_score requires `labels` sorted; permute proba columns from our
        # severity order to alphabetical so labels/columns stay aligned (the OvR
        # macro value itself is order-invariant).
        ordered = sorted(classes)
        perm = [classes.index(c) for c in ordered]
        try:
            roc_auc = float(
                roc_auc_score(yt, oof.proba[:, perm], multi_class="ovr",
                              average="macro", labels=ordered)
            )
        except ValueError:
            roc_auc = None

    confidences = oof.proba.max(axis=1)
    metrics: dict[str, Any] = {
        "n_eval_rows": oof.n_covered,
        "n_train_rows": oof.n_total,
        "coverage_note": (
            f"out-of-fold over {oof.n_covered}/{oof.n_total} train rows "
            "(earliest CV block is never a test fold)"
        ),
        "accuracy": float(accuracy_score(yt, yp)),
        "precision_macro": float(precision_score(yt, yp, labels=classes,
                                                 average="macro", zero_division=0)),
        "recall_macro": float(recall_score(yt, yp, labels=classes,
                                           average="macro", zero_division=0)),
        "f1_macro": float(f1_score(yt, yp, labels=classes,
                                   average="macro", zero_division=0)),
        "f1_weighted": float(f1_score(yt, yp, labels=classes,
                                      average="weighted", zero_division=0)),
        "roc_auc_ovr_macro": roc_auc,
        "brier_multiclass": _multiclass_brier(yt, oof.proba, classes),
        "mean_confidence": float(confidences.mean()),
        "low_confidence_rate": float(np.mean(confidences < low_conf_threshold)),
        "confusion_matrix": {"labels": classes, "matrix": cm},
        "per_class": {
            cls: {
                "precision": float(report[cls]["precision"]),
                "recall": float(report[cls]["recall"]),
                "f1": float(report[cls]["f1-score"]),
                "support": int(report[cls]["support"]),
            }
            for cls in classes
        },
        "classification_report": report,
    }
    return metrics


# --- Plots ------------------------------------------------------------------


def plot_confusion(cm: list[list[int]], classes: list[str], title: str, out: Path) -> None:
    arr = np.array(cm, dtype=float)
    fig, ax = plt.subplots(figsize=(4.5, 4))
    im = ax.imshow(arr, cmap="Blues")
    ax.set_xticks(range(len(classes)), labels=classes)
    ax.set_yticks(range(len(classes)), labels=classes)
    ax.set_xlabel("Predicted")
    ax.set_ylabel("True")
    ax.set_title(title)
    thresh = arr.max() / 2 if arr.max() else 0.5
    for i in range(arr.shape[0]):
        for j in range(arr.shape[1]):
            ax.text(j, i, int(arr[i, j]), ha="center", va="center",
                    color="white" if arr[i, j] > thresh else "black")
    fig.colorbar(im, ax=ax, fraction=0.046, pad=0.04)
    fig.tight_layout()
    fig.savefig(out, dpi=120)
    plt.close(fig)


def plot_importances(
    names: list[str], importances: np.ndarray, top_n: int, title: str, out: Path
) -> None:
    order = np.argsort(importances)[::-1][:top_n]
    fig, ax = plt.subplots(figsize=(6, 0.35 * len(order) + 1))
    ax.barh([names[i] for i in order][::-1], importances[order][::-1], color="#2b6cb0")
    ax.set_xlabel("Gini importance")
    ax.set_title(title)
    fig.tight_layout()
    fig.savefig(out, dpi=120)
    plt.close(fig)


def plot_calibration(
    y_true: np.ndarray, proba: np.ndarray, classes: list[str],
    positive: str, bins: int, title: str, out: Path,
) -> None:
    """Reliability curve for one class one-vs-rest (a calibration *assessment*)."""
    from sklearn.calibration import calibration_curve

    j = classes.index(positive)
    y_bin = (y_true == positive).astype(int)
    fig, ax = plt.subplots(figsize=(4.5, 4.5))
    ax.plot([0, 1], [0, 1], "--", color="grey", label="perfect")
    if y_bin.sum() and y_bin.sum() < len(y_bin):
        frac_pos, mean_pred = calibration_curve(
            y_bin, proba[:, j], n_bins=bins, strategy="uniform"
        )
        ax.plot(mean_pred, frac_pos, "o-", color="#c05621", label=f"{positive} (OvR)")
    ax.set_xlabel("Mean predicted probability")
    ax.set_ylabel("Observed frequency")
    ax.set_title(title)
    ax.legend(loc="best")
    fig.tight_layout()
    fig.savefig(out, dpi=120)
    plt.close(fig)


# --- Per-disease training ---------------------------------------------------


@dataclass
class DiseaseRun:
    disease: str
    pipeline: Pipeline
    best_params: dict[str, Any]
    best_cv_score: float
    scoring: str
    n_trials: int
    trials: list[dict[str, Any]]
    class_distribution: dict[str, int]
    metrics: dict[str, Any]
    importances: dict[str, float] = field(default_factory=dict)


def _trial_records(search: Any) -> list[dict[str, Any]]:
    """Flatten ``cv_results_`` into JSON-friendly per-trial rows, best first."""
    res = search.cv_results_
    rows: list[dict[str, Any]] = []
    for i in range(len(res["params"])):
        params = {k.replace("rf__", ""): v for k, v in res["params"][i].items()}
        rows.append({
            "rank": int(res["rank_test_score"][i]),
            "mean_cv_score": float(res["mean_test_score"][i]),
            "std_cv_score": float(res["std_test_score"][i]),
            "params": params,
        })
    rows.sort(key=lambda r: r["rank"])
    return rows


def train_disease(
    df: pd.DataFrame, disease: str, feature_names: list[str], cfg: dict[str, Any]
) -> DiseaseRun:
    """Tune + fit one disease's Pipeline and evaluate it out-of-fold (train only)."""
    classes = cfg.get("classes", DEFAULT_CLASSES)
    target_col = f"{disease}_{cfg['target_label']}"
    if target_col not in df.columns:
        raise KeyError(f"target column {target_col!r} not in train data")

    ordered = time_sort(df)
    y_all = ordered[target_col]
    mask = y_all.notna().to_numpy()
    X = feature_frame(ordered, feature_names)[mask].reset_index(drop=True)
    y = y_all[mask].astype(str).reset_index(drop=True)

    logger.info("[%s] tuning over %d rows, %d features", disease, len(X), len(feature_names))
    search = run_search(build_estimator(cfg), X, y, cfg)
    best: Pipeline = search.best_estimator_

    cv = build_cv(cfg["search"])
    oof = temporal_oof(build_estimator(cfg).set_params(**search.best_params_), X, y, cv, classes)
    metrics = evaluate_oof(oof, float(cfg["evaluation"]["low_confidence_threshold"]))

    importances = best.named_steps["rf"].feature_importances_
    imp_map = {feature_names[i]: float(importances[i]) for i in range(len(feature_names))}

    return DiseaseRun(
        disease=disease,
        pipeline=best,
        best_params={k.replace("rf__", ""): v for k, v in search.best_params_.items()},
        best_cv_score=float(search.best_score_),
        scoring=cfg["search"].get("scoring", "f1_macro"),
        n_trials=len(search.cv_results_["params"]),
        trials=_trial_records(search),
        class_distribution={c: int((y == c).sum()) for c in classes},
        metrics=metrics,
        importances=imp_map,
    )


# --- Orchestration & persistence --------------------------------------------


def load_train(train_path: Path | None = None) -> pd.DataFrame:
    """Read the frozen training set — and ONLY the training set.

    ``test.parquet`` is deliberately not referenced anywhere in this module; the
    held-out evaluation is Prompt 12.
    """
    train_path = train_path or paths.TRAIN_PATH
    return pd.read_parquet(train_path)


def _sha256_file(path: Path) -> str | None:
    if not Path(path).exists():
        return None
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _round_floats(obj: Any, ndigits: int = 10) -> Any:
    """Recursively round floats so serialized metrics are byte-stable.

    The forest is byte-identical across runs, but parallel ``predict_proba``
    reduction can wobble probability sums by ~1 ULP, which leaks into proba-derived
    aggregates (mean confidence, Brier). Rounding to 10 decimals absorbs that
    without any material precision loss.
    """
    if isinstance(obj, float):
        return round(obj, ndigits)
    if isinstance(obj, dict):
        return {k: _round_floats(v, ndigits) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_round_floats(v, ndigits) for v in obj]
    return obj


def _split_manifest() -> dict[str, Any]:
    if Path(paths.SPLIT_MANIFEST_PATH).exists():
        return json.loads(Path(paths.SPLIT_MANIFEST_PATH).read_text(encoding="utf-8"))
    return {}


def build_bundle(
    runs: list[DiseaseRun], feature_names: list[str], cfg: dict[str, Any]
) -> dict[str, Any]:
    """Assemble the reloadable artifact bundle (a plain dict — no custom class).

    Storing a dict (not a bespoke object) means ``joblib.load`` works anywhere
    without importing this module, which keeps Prompt 14's serving load trivial.

    Carries ``low_confidence_threshold`` from ``config/model.yaml`` (Sprint M6.1,
    the single source of truth) so every inference component reads the value the
    model was actually evaluated against, instead of a locally hardcoded copy.
    """
    return {
        "schema_version": 1,
        "model_version": cfg["model_version"],
        "random_state": int(cfg["random_state"]),
        "target_label": cfg["target_label"],
        "diseases": [r.disease for r in runs],
        "classes": cfg.get("classes", DEFAULT_CLASSES),
        "feature_names": feature_names,
        "low_confidence_threshold": float(cfg["evaluation"]["low_confidence_threshold"]),
        "models": {r.disease: r.pipeline for r in runs},
        "best_params": {r.disease: r.best_params for r in runs},
        "reproducibility": {
            "sklearn_version": sklearn.__version__,
            "numpy_version": np.__version__,
            "pandas_version": pd.__version__,
            "train_sha256": _sha256_file(paths.TRAIN_PATH),
            "split_manifest": _split_manifest(),
        },
    }


#: Fallback ``low_confidence_threshold`` for a bundle built before Sprint M6.1
#: (which did not yet stamp the config value into the artifact). Reproduces the
#: threshold every such artifact was actually evaluated/served against; new
#: bundles always carry their own value via :func:`build_bundle`, so this is
#: only ever reached for a pre-M6.1 artifact.
_LEGACY_LOW_CONFIDENCE_THRESHOLD = 0.55


def predict_risk(
    bundle: dict[str, Any], disease: str, X: pd.DataFrame
) -> list[dict[str, Any]]:
    """Stable prediction interface: feature rows -> RiskLevel / Confidence / Version.

    Returns one dict per input row with the Sprint 1 contract fields. Operates on
    the plain bundle dict, so it works after a bare ``joblib.load`` without
    importing the training internals. The low-confidence threshold is read from
    the bundle (``low_confidence_threshold``, Sprint M6.1) — never hardcoded —
    so this stays consistent with whatever the model was configured with.
    """
    pipeline: Pipeline = bundle["models"][disease]
    feats = X[bundle["feature_names"]].astype(float)
    proba = pipeline.predict_proba(feats)
    classes = pipeline.classes_
    threshold = float(
        bundle.get("low_confidence_threshold", _LEGACY_LOW_CONFIDENCE_THRESHOLD)
    )
    out: list[dict[str, Any]] = []
    for row in proba:
        idx = int(np.argmax(row))
        confidence = float(row[idx])
        out.append({
            "risk_level": str(classes[idx]),
            "confidence": round(confidence, 4),
            "model_version": bundle["model_version"],
            "low_confidence": confidence < threshold,
        })
    return out


def save_artifacts(
    bundle: dict[str, Any],
    runs: list[DiseaseRun],
    cfg: dict[str, Any],
    artifacts_dir: Path | None = None,
) -> dict[str, Path]:
    """Persist model, metrics, feature importances, and plots."""
    artifacts_dir = artifacts_dir or paths.ARTIFACTS_DIR
    paths.ensure_dir(artifacts_dir)
    plots_dir = paths.ensure_dir(artifacts_dir / "plots")

    model_path = artifacts_dir / "candidate_model.joblib"
    dump(bundle, model_path)

    metrics = {
        "model_version": cfg["model_version"],
        "random_state": int(cfg["random_state"]),
        "target_label": cfg["target_label"],
        "scoring": cfg["search"].get("scoring", "f1_macro"),
        "cv": {"splitter": "TimeSeriesSplit",
               "n_splits": int(cfg["search"]["cv"]["n_splits"])},
        "reproducibility": bundle["reproducibility"],
        "per_disease": {
            r.disease: {
                "best_cv_score": r.best_cv_score,
                "best_params": r.best_params,
                "n_trials": r.n_trials,
                "class_distribution": r.class_distribution,
                **r.metrics,
            }
            for r in runs
        },
    }
    metrics_path = artifacts_dir / "metrics.json"
    metrics_path.write_text(
        json.dumps(_round_floats(metrics), indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    # feature_importance.csv (long format, ranked within disease).
    imp_rows: list[dict[str, Any]] = []
    for r in runs:
        ranked = sorted(r.importances.items(), key=lambda kv: kv[1], reverse=True)
        for rank, (feature, value) in enumerate(ranked, start=1):
            imp_rows.append({"disease": r.disease, "rank": rank,
                             "feature": feature, "importance": value})
    imp_df = pd.DataFrame(imp_rows, columns=["disease", "rank", "feature", "importance"])
    imp_path = artifacts_dir / "feature_importance.csv"
    imp_df.to_csv(imp_path, index=False)

    # Plots per disease.
    classes = cfg.get("classes", DEFAULT_CLASSES)
    top_n = int(cfg["evaluation"]["importance_top_n"])
    bins = int(cfg["evaluation"]["calibration_bins"])
    feature_names = bundle["feature_names"]
    for r in runs:
        cm = r.metrics["confusion_matrix"]["matrix"]
        plot_confusion(cm, classes, f"{r.disease} — OOF confusion",
                       plots_dir / f"confusion_matrix_{r.disease}.png")
        imp_vec = np.array([r.importances[f] for f in feature_names])
        plot_importances(feature_names, imp_vec, top_n,
                         f"{r.disease} — top features",
                         plots_dir / f"feature_importance_{r.disease}.png")

    return {"model": model_path, "metrics": metrics_path, "importance": imp_path,
            "plots": plots_dir}


def train_all(
    df: pd.DataFrame, cfg: dict[str, Any]
) -> tuple[dict[str, Any], list[DiseaseRun], list[str]]:
    """Train every disease and return (bundle, runs, feature_names)."""
    feature_names = select_feature_columns(df, cfg["features"])
    runs = [train_disease(df, d, feature_names, cfg) for d in cfg["diseases"]]
    bundle = build_bundle(runs, feature_names, cfg)
    return bundle, runs, feature_names


# --- Calibration plots (need OOF probabilities, recomputed cheaply) ---------


def _write_calibration_plots(
    df: pd.DataFrame, runs: list[DiseaseRun], feature_names: list[str],
    cfg: dict[str, Any], plots_dir: Path,
) -> None:
    """Reliability curves for the 'High' risk class, per disease (assessment)."""
    classes = cfg.get("classes", DEFAULT_CLASSES)
    bins = int(cfg["evaluation"]["calibration_bins"])
    cv = build_cv(cfg["search"])
    ordered = time_sort(df)
    for r in runs:
        target_col = f"{r.disease}_{cfg['target_label']}"
        y_all = ordered[target_col]
        mask = y_all.notna().to_numpy()
        X = feature_frame(ordered, feature_names)[mask].reset_index(drop=True)
        y = y_all[mask].astype(str).reset_index(drop=True)
        est = build_estimator(cfg).set_params(
            **{f"rf__{k}": v for k, v in r.best_params.items()}
        )
        oof = temporal_oof(est, X, y, cv, classes)
        plot_calibration(oof.y_true, oof.proba, classes, "High", bins,
                         f"{r.disease} — calibration (High, OvR)",
                         plots_dir / f"calibration_{r.disease}.png")


# --- Training log -----------------------------------------------------------


def render_training_log(runs: list[DiseaseRun], cfg: dict[str, Any]) -> str:
    L: list[str] = []
    L.append("# Training Log — ForeSeeMe Candidate Random Forest")
    L.append("")
    L.append("**Sprint 2, Prompt 11 — Model Training, Hyperparameter Tuning & "
             "Temporal Cross-Validation**")
    L.append("")
    L.append(f"- Model version: `{cfg['model_version']}`")
    L.append(f"- Seed (forest + search + folds): `{cfg['random_state']}`  → "
             "reproducible: same seed yields the same winner.")
    L.append(f"- Target label: `{cfg['target_label']}` (transition-band sampled "
             "labels, Prompt 9).")
    L.append(f"- One Pipeline per disease: {', '.join(cfg['diseases'])} — bundled "
             "into `candidate_model.joblib`.")
    L.append("- Pipeline: `SimpleImputer(median)` → `StandardScaler` → "
             "`RandomForestClassifier(class_weight='balanced')` (preprocessing is "
             "inside the artifact, self-sufficient at serving).")
    sc = cfg["search"]
    L.append(f"- Search: **{sc.get('method')}** "
             f"({sc.get('n_iter')} candidates) scored by `{sc.get('scoring')}` "
             f"over **TimeSeriesSplit(n_splits={sc['cv']['n_splits']})** — "
             "temporal CV, never K-fold.")
    L.append("- Trained on `train.parquet` only; `test.parquet` untouched "
             "(held-out evaluation is Prompt 12).")
    L.append("")
    L.append("## Class imbalance & `class_weight='balanced'`")
    L.append("")
    L.append("High risk is a minority class for smog and influenza. "
             "`class_weight='balanced'` (inverse-frequency) is used **deliberately** "
             "so the minority risk classes are not washed out; this is a documented "
             "choice, not a silent default. Train-split distributions:")
    L.append("")
    L.append("| Disease | Low | Medium | High |")
    L.append("|---------|-----|--------|------|")
    for r in runs:
        d = r.class_distribution
        L.append(f"| {r.disease} | {d.get('Low', 0)} | {d.get('Medium', 0)} | "
                 f"{d.get('High', 0)} |")
    L.append("")
    L.append("## Search outcome (the winner)")
    L.append("")
    L.append(f"| Disease | Best CV {sc.get('scoring')} | Chosen hyperparameters |")
    L.append("|---------|------------------|------------------------|")
    for r in runs:
        params = ", ".join(f"{k}={v}" for k, v in r.best_params.items())
        L.append(f"| {r.disease} | {r.best_cv_score:.4f} | {params} |")
    L.append("")
    L.append("## Out-of-fold metrics (temporal CV on train)")
    L.append("")
    L.append("Honest generalisation estimate from out-of-fold TimeSeriesSplit "
             "predictions — never the test set.")
    L.append("")
    L.append("| Disease | n (covered) | Accuracy | F1-macro | F1-weighted | "
             "ROC-AUC (OvR) | Brier |")
    L.append("|---------|-------------|----------|----------|-------------|"
             "--------------|-------|")
    for r in runs:
        m = r.metrics
        auc = "n/a" if m["roc_auc_ovr_macro"] is None else f"{m['roc_auc_ovr_macro']:.4f}"
        L.append(f"| {r.disease} | {m['n_eval_rows']}/{m['n_train_rows']} | "
                 f"{m['accuracy']:.4f} | {m['f1_macro']:.4f} | "
                 f"{m['f1_weighted']:.4f} | {auc} | {m['brier_multiclass']:.4f} |")
    L.append("")
    L.append("## Full search trace (all trials, best first)")
    L.append("")
    for r in runs:
        L.append(f"### {r.disease} — {r.n_trials} trials")
        L.append("")
        L.append(f"| Rank | Mean CV {sc.get('scoring')} | Std | Params |")
        L.append("|------|----------------|-----|--------|")
        for t in r.trials:
            params = ", ".join(f"{k}={v}" for k, v in t["params"].items())
            L.append(f"| {t['rank']} | {t['mean_cv_score']:.4f} | "
                     f"{t['std_cv_score']:.4f} | {params} |")
        L.append("")
    L.append("## Artifacts")
    L.append("")
    L.append("- `artifacts/candidate_model.joblib` — bundle of the three fitted "
             "Pipelines + feature list + reproducibility record.")
    L.append("- `artifacts/metrics.json` — per-disease CV winner + OOF metric suite.")
    L.append("- `artifacts/feature_importance.csv` — ranked Gini importances "
             "(permutation importance is Prompt 12).")
    L.append("- `artifacts/plots/` — confusion matrix, feature importance, and "
             "calibration (reliability) plot per disease.")
    L.append("")
    L.append("> Scope: this prompt trains and tunes the candidate only. Held-out "
             "test evaluation, calibration tuning, robustness, permutation "
             "importance, and seasonality validation are Prompt 12. FastAPI, the "
             "Sprint 1 stub, and serving are untouched (Prompt 14).")
    return "\n".join(L) + "\n"


# --- Entry point ------------------------------------------------------------


def main() -> int:
    from app.logging_config import configure_logging

    configure_logging("INFO")
    cfg = load_model_config()
    df = load_train()

    bundle, runs, feature_names = train_all(df, cfg)
    out = save_artifacts(bundle, runs, cfg)
    _write_calibration_plots(df, runs, feature_names, cfg, out["plots"])

    report = render_training_log(runs, cfg)
    paths.ensure_dir(paths.REPORTS_DIR)
    (paths.REPORTS_DIR / "training_log.md").write_text(report, encoding="utf-8")

    for r in runs:
        print(f"  [{r.disease}] best {r.scoring}={r.best_cv_score:.4f} "
              f"acc={r.metrics['accuracy']:.4f} f1_macro={r.metrics['f1_macro']:.4f} "
              f"params={r.best_params}")
    print(f"model    -> {out['model']}")
    print(f"metrics  -> {out['metrics']}")
    print(f"log      -> {paths.REPORTS_DIR / 'training_log.md'}")
    return 0


if __name__ == "__main__":
    import sys

    sys.exit(main())
