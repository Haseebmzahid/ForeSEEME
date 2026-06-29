"""Model persistence & Model Card (Sprint 2, Prompt 13).

Promotes the validated Prompt 11 candidate to a versioned **production** artifact
``model_<semver>.joblib`` and authors the authoritative deliverables an examiner
can audit end-to-end:

* ``artifacts/model_<version>.joblib`` — the promoted bundle (the three fitted
  per-disease Pipelines) enriched with a complete reproducibility record.
* ``artifacts/metrics.json`` — the sidecar, whose held-out numbers are sourced
  directly from the Prompt 12 ``evaluation.json`` so they cannot drift from the
  evaluation report.
* ``reports/MODEL_CARD.md`` — rendered programmatically from that same data, so
  the card and the artifact never disagree.

The Sprint 1 serving contract is untouched: the artifact is a plain dict loadable
with a bare ``joblib.load`` and predicted through the existing
``train.predict_risk`` interface (RiskLevel / Confidence / ModelVersion). This
prompt persists and documents only — it does not modify FastAPI, the stub, or any
serving code (that is Prompt 14).

Run (from ``backend/``)::

    python -m ml.training.persist
"""

from __future__ import annotations

import json
import platform
import re
from pathlib import Path
from typing import Any

import joblib
import numpy as np
import pandas as pd
import scipy
import sklearn
import yaml
from joblib import dump, load

from ml.pipelines import paths
from ml.training import train as T

#: Strict semver (major.minor.patch with optional pre-release/build), so the
#: promoted version is auditable and machine-checkable.
SEMVER_RE = re.compile(
    r"^(?P<major>0|[1-9]\d*)\.(?P<minor>0|[1-9]\d*)\.(?P<patch>0|[1-9]\d*)"
    r"(?:-(?P<prerelease>[0-9A-Za-z-.]+))?(?:\+(?P<build>[0-9A-Za-z-.]+))?$"
)


def is_semver(version: str) -> bool:
    return bool(SEMVER_RE.match(version))


# --- Inputs -----------------------------------------------------------------


def _load_json(path: Path) -> dict[str, Any]:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def load_candidate(path: Path | None = None) -> dict[str, Any]:
    return load(path or (paths.ARTIFACTS_DIR / "candidate_model.joblib"))


def load_evaluation(path: Path | None = None) -> dict[str, Any]:
    return _load_json(path or (paths.ARTIFACTS_DIR / "evaluation.json"))


# --- Reproducibility record -------------------------------------------------


def library_versions() -> dict[str, str]:
    return {
        "python": platform.python_version(),
        "scikit-learn": sklearn.__version__,
        "numpy": np.__version__,
        "pandas": pd.__version__,
        "scipy": scipy.__version__,
        "joblib": joblib.__version__,
    }


def reproducibility_record(
    cfg: dict[str, Any], candidate: dict[str, Any], candidate_path: Path
) -> dict[str, Any]:
    """Everything needed to reproduce this artifact bit-for-bit."""
    manifest = (
        _load_json(paths.SPLIT_MANIFEST_PATH)
        if Path(paths.SPLIT_MANIFEST_PATH).exists() else {}
    )
    return {
        "seed": int(cfg["random_state"]),
        "target_label": cfg["target_label"],
        "config_sha256": T._sha256_file(paths.MODEL_PATH),
        "candidate_sha256": T._sha256_file(candidate_path),
        "train_sha256": manifest.get("train_sha256"),
        "test_sha256": manifest.get("test_sha256"),
        "split_manifest": manifest,
        "feature_count": len(candidate["feature_names"]),
        "library_versions": library_versions(),
    }


# --- Promotion --------------------------------------------------------------


def build_production_bundle(
    cfg: dict[str, Any], candidate: dict[str, Any], evaluation: dict[str, Any],
    repro: dict[str, Any],
) -> dict[str, Any]:
    """Enrich the candidate bundle into the versioned production artifact."""
    release = cfg["release"]
    eval_summary = {
        d: {
            "accuracy": v["metrics"]["accuracy"],
            "f1_macro": v["metrics"]["f1_macro"],
            "roc_auc_ovr_macro": v["metrics"]["roc_auc_ovr_macro"],
            "brier_multiclass": v["metrics"]["brier_multiclass"],
            "seasonality_lift": v["label_seasonality"]["lift"],
        }
        for d, v in evaluation["per_disease"].items()
    }
    bundle = dict(candidate)  # keeps the fitted Pipelines + feature_names + best_params
    bundle["schema_version"] = 2
    bundle["version"] = release["version"]
    bundle["model_version"] = release["model_version"]   # stamped on predictions
    bundle["promoted_from"] = candidate["model_version"]
    bundle["reproducibility"] = repro
    bundle["evaluation_summary"] = eval_summary
    return bundle


def build_metrics(
    cfg: dict[str, Any], candidate: dict[str, Any], evaluation: dict[str, Any],
    repro: dict[str, Any],
) -> dict[str, Any]:
    """Authoritative sidecar — held-out numbers copied from evaluation.json."""
    release = cfg["release"]
    per_disease: dict[str, Any] = {}
    for d, v in evaluation["per_disease"].items():
        m = v["metrics"]
        per_disease[d] = {
            "best_params": candidate["best_params"][d],
            "test": {
                "n": m["n"],
                "accuracy": m["accuracy"],
                "precision_macro": m["precision_macro"],
                "recall_macro": m["recall_macro"],
                "f1_macro": m["f1_macro"],
                "precision_weighted": m["precision_weighted"],
                "recall_weighted": m["recall_weighted"],
                "f1_weighted": m["f1_weighted"],
                "roc_auc_ovr_macro": m["roc_auc_ovr_macro"],
                "brier_multiclass": m["brier_multiclass"],
                "per_class": m["per_class"],
                "confusion_matrix": m["confusion_matrix"],
            },
            "calibration": v["calibration"],
            "recalibration": v["recalibration"],
            "label_seasonality": {
                "window_label": v["label_seasonality"]["window_label"],
                "high_in_window_rate": v["label_seasonality"]["high_in_window_rate"],
                "base_rate": v["label_seasonality"]["base_rate"],
                "lift": v["label_seasonality"]["lift"],
            },
        }
    return {
        "version": release["version"],
        "model_version": release["model_version"],
        "evaluated_on": evaluation["evaluated_on"],
        "test_target_label": evaluation["test_target_label"],
        "diseases": candidate["diseases"],
        "classes": cfg.get("classes", T.DEFAULT_CLASSES),
        "reproducibility": repro,
        "per_disease": per_disease,
    }


# --- Model Card -------------------------------------------------------------


def _window() -> tuple[str, str]:
    pipe = yaml.safe_load(Path(paths.PIPELINE_PATH).read_text(encoding="utf-8"))
    w = pipe.get("window", {})
    return str(w.get("start", "?")), str(w.get("end", "?"))


def render_model_card(metrics: dict[str, Any], cfg: dict[str, Any]) -> str:
    repro = metrics["reproducibility"]
    start, end = _window()
    sm = repro.get("split_manifest", {}).get("split", {})
    L: list[str] = []
    L.append(f"# Model Card — ForeSeeMe Environmental Disease-Risk Model `{metrics['version']}`")
    L.append("")
    L.append(f"**Artifact:** `artifacts/model_{metrics['version']}.joblib` · "
             f"**Prediction `modelVersion`:** `{metrics['model_version']}` · "
             f"**Status:** 🔒 released candidate (Sprint 2, Prompt 13)")
    L.append("")
    L.append("> **ForeSeeMe estimates ENVIRONMENTAL DISEASE-RISK SUITABILITY — not "
             "incidence, not outbreaks.** It scores how favourable a city-week's "
             "environment is for each disease family, from a transparent, "
             "literature-grounded index. It is **not** an outbreak predictor and "
             "**not** a clinical or diagnostic tool.")
    L.append("")

    L.append("## Intended use")
    L.append("")
    L.append("- Produce a Low / Medium / High **environmental risk level** per "
             "(city, week) for dengue, smog/respiratory, and influenza, with a "
             "confidence, to drive the ForeSeeMe awareness dashboard and alerts.")
    L.append("- Consumed only by the backend batch job, which writes "
             "`riskEstimates` to Firestore (ADR-001); the app reads Firestore, "
             "never the model directly.")
    L.append("")

    L.append("## Out of scope (explicit)")
    L.append("")
    L.append("- ❌ **Not outbreak prediction / forecasting.** It does not predict "
             "case counts, epidemic timing, or transmission.")
    L.append("- ❌ **Not clinical or diagnostic.** It says nothing about any "
             "individual's health and must not inform diagnosis or treatment.")
    L.append("- ❌ **Not a surveillance substitute.** It complements, never "
             "replaces, official public-health surveillance.")
    L.append("- ❌ Outside the five modelled cities or the trained environmental "
             "ranges, outputs are unsupported.")
    L.append("")

    L.append("## Model details")
    L.append("")
    L.append(f"- **Architecture:** one self-contained scikit-learn `Pipeline` per "
             f"disease ({', '.join(metrics['diseases'])}) — "
             "`SimpleImputer(median)` → `StandardScaler` → "
             "`RandomForestClassifier(class_weight='balanced')` — bundled in a "
             "single artifact behind one predict interface.")
    L.append(f"- **Inputs:** {repro['feature_count']} leakage-free engineered "
             "features (raw weather/AQI, 1–4 wk lags, 3–4 wk rolling means, "
             "seasonal anomalies, cyclical week, city one-hots). See "
             "`reports/feature_dictionary.md`.")
    L.append(f"- **Output:** `riskLevel` ∈ {{Low, Medium, High}}, `confidence` ∈ "
             "[0,1], `modelVersion` — matching the frozen Sprint 1 contract "
             "(`docs/RISK_SCHEMA.md`).")
    L.append(f"- **Selected hyperparameters (tuned via TimeSeriesSplit, Prompt 11):**")
    for d in metrics["diseases"]:
        params = ", ".join(f"{k}={v}" for k, v in metrics["per_disease"][d]["best_params"].items())
        L.append(f"  - {d}: {params}")
    L.append("")

    L.append("## Training data & provenance")
    L.append("")
    L.append(f"- **Sources:** Open-Meteo ERA5 (temperature, humidity, "
             "precipitation) and CAMS air quality (PM2.5, PM10, US-AQI), for "
             "Islamabad, Rawalpindi, Lahore, Karachi, Peshawar.")
    L.append(f"- **Window:** {start} → {end} (weekly; bounded by real AQI "
             "coverage — see `reports/data_availability.md`). No fabricated or "
             "back-filled records.")
    L.append(f"- **Temporal split (no shuffling):** train **{sm.get('train_rows','?')}** "
             f"rows / test **{sm.get('test_rows','?')}** rows; test is the most "
             "recent block (`reports/validation_report.md`, GREEN gate).")
    L.append(f"- **Data hashes:** train `{repro.get('train_sha256','?')}` · "
             f"test `{repro.get('test_sha256','?')}`.")
    L.append("")

    L.append("## Label methodology & limitations")
    L.append("")
    L.append("- Labels are a transparent, weighted **environmental-suitability "
             "index** per disease, mapped to Low/Med/High with a soft transition "
             "band; every threshold/weight is cited to literature in "
             "**`reports/label_methodology.md`** (Prompt 9).")
    L.append("- **Suitability, not incidence.** No human immunity, mobility, "
             "vaccination, vector control, or reporting effects are modelled.")
    L.append("- The index weights and cutoffs are documented **design choices** an "
             "examiner can challenge; the data window is short (2022-08 onward).")
    L.append("")

    L.append("## Metrics & calibration (held-out test set)")
    L.append("")
    L.append("> **Accuracy is expected-by-construction and is NOT the scientific "
             "claim:** labels are derived from the same features the model reads, "
             "so a faithful surrogate necessarily scores high. The evidence is "
             "calibration, robustness, importance alignment, and seasonality "
             "(`reports/evaluation_report.md`, Prompt 12).")
    L.append("")
    L.append("| Disease | Accuracy | F1 (macro/wt) | ROC-AUC | Brier | ECE | Seasonality lift |")
    L.append("|---------|----------|---------------|---------|-------|-----|------------------|")
    for d in metrics["diseases"]:
        pd_ = metrics["per_disease"][d]
        t = pd_["test"]
        auc = "n/a" if t["roc_auc_ovr_macro"] is None else f"{t['roc_auc_ovr_macro']:.3f}"
        ece = pd_["calibration"]["ece_top_class"]
        lift = pd_["label_seasonality"]["lift"]
        L.append(f"| {d} | {t['accuracy']:.3f} | "
                 f"{t['f1_macro']:.3f}/{t['f1_weighted']:.3f} | {auc} | "
                 f"{t['brier_multiclass']:.3f} | {ece:.3f} | {lift:.2f} |")
    L.append("")
    L.append("- **Calibration:** reliability + Brier + ECE assessed per disease; "
             "where ECE was poor it was improved with a temporal sigmoid "
             "calibrator (details in `evaluation.json` / evaluation report).")
    L.append("- **Robustness:** graceful degradation under Gaussian input noise "
             "(stays above chance) — not collapse.")
    L.append("- **Seasonality validation (decisive):** High-risk weeks concentrate "
             "in documented windows (smog Oct–Jan, influenza Dec–Feb strongly; "
             "dengue post-monsoon more broadly, consistent with thermal "
             "suitability).")
    L.append("")

    L.append("## Ethical & operational caveats")
    L.append("")
    L.append("- Communicate outputs as **environmental awareness**, never as a "
             "personal medical warning; avoid fatalism or false reassurance.")
    L.append("- Low confidence / out-of-range inputs should degrade gracefully "
             "(the serving layer flags `lowConfidence`).")
    L.append("- Risk is only as fresh as the batch schedule (ADR-002); stale or "
             "missing upstream data must be surfaced, not hidden.")
    L.append("- Not for resource allocation or clinical triage decisions.")
    L.append("")

    L.append("## Reproducibility record")
    L.append("")
    L.append(f"- **Seed:** `{repro['seed']}` (everywhere) · **Target label:** "
             f"`{repro['target_label']}` · **Promoted:** "
             f"`{cfg['model_version']}` (candidate) → `{metrics['model_version']}` "
             "(released).")
    L.append(f"- **Config hash** (`model.yaml`): `{repro['config_sha256']}`")
    L.append(f"- **Candidate hash:** `{repro['candidate_sha256']}`")
    L.append(f"- **Library versions:** " + ", ".join(
        f"{k} {v}" for k, v in repro["library_versions"].items()))
    L.append("- **Reproducibility:** the candidate (training + tuning) is "
             "byte-for-byte reproducible — same seed → identical candidate "
             "(`reports/training_log.md`). This artifact is promoted from that "
             "candidate (`candidate_sha256` above) and loads to an identical model "
             "with identical predictions; `metrics.json` is regenerated "
             "deterministically from the held-out evaluation.")
    L.append("")
    L.append("## Linked documents")
    L.append("")
    L.append("- `reports/label_methodology.md` — labels, determinants, citations "
             "(Prompt 9)")
    L.append("- `reports/feature_dictionary.md` — features & leakage guarantees "
             "(Prompt 8)")
    L.append("- `reports/validation_report.md` — dataset freeze & GREEN gate "
             "(Prompt 10)")
    L.append("- `reports/training_log.md` — search trace & winner (Prompt 11)")
    L.append("- `reports/evaluation_report.md` — held-out evaluation & seasonality "
             "(Prompt 12)")
    L.append("- `docs/RISK_SCHEMA.md` — frozen Sprint 1 serving contract")
    L.append("")
    return "\n".join(L) + "\n"


# --- Orchestration ----------------------------------------------------------


def promote(cfg: dict[str, Any] | None = None) -> dict[str, Path]:
    cfg = cfg or T.load_model_config()
    version = cfg["release"]["version"]
    if not is_semver(version):
        raise ValueError(f"release.version {version!r} is not valid semver")

    candidate_path = paths.ARTIFACTS_DIR / "candidate_model.joblib"
    candidate = load_candidate(candidate_path)
    evaluation = load_evaluation()

    # Guard against metric drift: the evaluation must be of THIS candidate.
    if evaluation.get("model_version") != candidate.get("model_version"):
        raise ValueError(
            "evaluation.json model_version "
            f"{evaluation.get('model_version')!r} != candidate "
            f"{candidate.get('model_version')!r}; re-run Prompt 12 before promoting."
        )

    repro = reproducibility_record(cfg, candidate, candidate_path)
    bundle = build_production_bundle(cfg, candidate, evaluation, repro)
    metrics = build_metrics(cfg, candidate, evaluation, repro)

    paths.ensure_dir(paths.ARTIFACTS_DIR)
    model_path = paths.ARTIFACTS_DIR / f"model_{version}.joblib"
    dump(bundle, model_path)

    metrics_path = paths.ARTIFACTS_DIR / "metrics.json"
    metrics_path.write_text(
        json.dumps(T._round_floats(metrics), indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    card_path = paths.REPORTS_DIR / "MODEL_CARD.md"
    paths.ensure_dir(paths.REPORTS_DIR)
    card_path.write_text(render_model_card(metrics, cfg), encoding="utf-8")

    return {"model": model_path, "metrics": metrics_path, "card": card_path}


def main() -> int:
    from app.logging_config import configure_logging

    configure_logging("INFO")
    cfg = T.load_model_config()
    out = promote(cfg)
    print(f"model    -> {out['model']}")
    print(f"metrics  -> {out['metrics']}")
    print(f"card     -> {out['card']}")
    print(f"version  -> {cfg['release']['version']} (semver ok)")
    return 0


if __name__ == "__main__":
    import sys

    sys.exit(main())
