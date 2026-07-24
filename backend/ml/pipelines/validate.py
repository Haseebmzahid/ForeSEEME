"""Dataset validation & temporal train/test freeze (Sprint 2, Prompt 10).

⛔ HARD GATE. Modeling must not begin unless every check here is green.

This validates the labelled feature set against a schema + statistical contract,
performs a **temporal** train/test split (no shuffling — lagged features make
random splits leak), and freezes the processed datasets with a reproducible
manifest hash. It catches leakage, broken splits, and degenerate distributions
before any training time is spent. It trains nothing and tunes nothing.

Checks (all must PASS):
  1. schema           — column types, physical ranges, allowed labels, key uniqueness
  2. feature_leakage  — stored lags/rollings == reconstructed past values (no future)
  3. class_distribution — every class present in BOTH splits, non-degenerate
  4. missing_values   — only documented columns are nullable; keys/raw are complete
  5. temporal_split   — train weeks strictly precede test weeks
  6. contamination    — no (city, year, week) shared between train and test
  7. label_consistency— probs sum to 1; hard label matches thresholds; labels valid
  8. feature_statistics — train/test summary stats; flag zero-variance features

Outputs: ``data/processed/train.parquet``, ``data/processed/test.parquet``,
``data/processed/split_manifest.json`` (committed), ``reports/validation_report.md``.

Run (from ``backend/``)::

    python -m ml.pipelines.validate     # exits non-zero if the gate fails
"""

from __future__ import annotations

import hashlib
import json
import logging
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd
import pandera.pandas as pa
import yaml

from ml.pipelines import paths
from ml.pipelines.labels import hard_label

logger = logging.getLogger("foreseeme.ml.validate")

KEY = ["city", "iso_year", "week_of_year"]
DISEASES = ["dengue", "smog", "influenza"]
CLASSES = ["Low", "Medium", "High"]
LABEL_KINDS = ["label", "label_sampled"]


# --- Config ----------------------------------------------------------------


def _load_yaml(path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def load_pipeline(path=paths.PIPELINE_PATH) -> dict[str, Any]:
    return _load_yaml(path)


def load_city_vocab(path=paths.CITIES_PATH) -> list[str]:
    return [c["name"] for c in _load_yaml(path)["cities"]]


# --- Result model ----------------------------------------------------------


@dataclass
class Check:
    name: str
    passed: bool
    detail: str
    rows: list[str] = field(default_factory=list)


# --- Schema contract -------------------------------------------------------


_LAG_RE = re.compile(r"_lag\d+$")
_ROLL_RE = re.compile(r"_roll\d+$")


def _col_groups(df: pd.DataFrame) -> dict[str, list[str]]:
    # Precise patterns so flags like `insufficient_lag_history` are NOT matched.
    return {
        "lag": [c for c in df.columns if _LAG_RE.search(c)],
        "roll": [c for c in df.columns if _ROLL_RE.search(c)],
        "anom": [c for c in df.columns if c.endswith("_anom")],
        "onehot": [c for c in df.columns if c.startswith("city_")],
    }


def build_schema(df: pd.DataFrame, city_vocab: list[str]) -> pa.DataFrameSchema:
    """Build the schema/statistical contract for the labelled table."""
    ranges = load_pipeline()["cleaning"]["physical_ranges"]
    groups = _col_groups(df)
    columns: dict[str, pa.Column] = {}

    # Keys.
    columns["city"] = pa.Column(str, pa.Check.isin(city_vocab), nullable=False)
    columns["iso_year"] = pa.Column(int, pa.Check.in_range(2000, 2100), nullable=False)
    columns["week_of_year"] = pa.Column(int, pa.Check.in_range(1, 53), nullable=False)

    # Raw weather/AQI — complete and physically bounded.
    for var in ("temperature", "humidity", "precipitation", "pm2_5", "pm10", "us_aqi"):
        lo, hi = ranges[var]
        columns[var] = pa.Column(float, pa.Check.in_range(lo, hi), nullable=False)
    columns["aqi_available"] = pa.Column(bool, nullable=False)

    # Engineered features — nullable (documented history-driven NaNs).
    for col in groups["lag"] + groups["roll"] + groups["anom"]:
        columns[col] = pa.Column(float, nullable=True)
    columns["week_sin"] = pa.Column(float, pa.Check.in_range(-1.0, 1.0), nullable=False)
    columns["week_cos"] = pa.Column(float, pa.Check.in_range(-1.0, 1.0), nullable=False)
    for col in groups["onehot"]:
        columns[col] = pa.Column(int, pa.Check.isin([0, 1]), nullable=False)

    # Per-disease labels.
    for disease in DISEASES:
        columns[f"{disease}_score"] = pa.Column(
            float, pa.Check.in_range(0.0, 1.0), nullable=True
        )
        for cls in ("low", "medium", "high"):
            columns[f"{disease}_prob_{cls}"] = pa.Column(
                float, pa.Check.in_range(0.0, 1.0), nullable=True
            )
        for kind in LABEL_KINDS:
            columns[f"{disease}_{kind}"] = pa.Column(
                str, pa.Check.isin(CLASSES), nullable=True
            )

    return pa.DataFrameSchema(
        columns,
        unique=KEY,            # key uniqueness
        strict=False,          # extra QA columns (days_in_week, month, flags) allowed
        coerce=False,
    )


def check_schema(df: pd.DataFrame, schema: pa.DataFrameSchema) -> Check:
    try:
        schema.validate(df, lazy=True)
        return Check("schema", True, "all column types, ranges, labels and key "
                                     "uniqueness satisfied")
    except pa.errors.SchemaErrors as exc:
        cases = exc.failure_cases
        summary = (
            cases.groupby("column")["check"].count().to_dict()
            if not cases.empty else {}
        )
        rows = [f"{r['column']}: {r['check']} (value={r['failure_case']})"
                for _, r in cases.head(20).iterrows()]
        return Check("schema", False, f"{len(cases)} schema failures: {summary}", rows)


# --- Feature-leakage check (reconstruction) --------------------------------


def _count_mismatch(stored: pd.Series, expected: pd.Series) -> int:
    a = stored.to_numpy(dtype=float)
    b = expected.to_numpy(dtype=float)
    both_nan = np.isnan(a) & np.isnan(b)
    ok = both_nan | np.isclose(a, b, equal_nan=False)
    return int((~ok).sum())


def check_feature_leakage(df: pd.DataFrame, feat_cfg: dict[str, Any]) -> Check:
    """Stored lags/rollings must equal values reconstructed from PAST weeks only.

    If a lag column ever used a future value, the reconstruction (shift +k =
    past) would differ. Zero mismatches ⇒ causal, no lookahead.
    """
    d = df.sort_values(KEY).reset_index(drop=True)
    grouped = d.groupby("city", sort=False)
    issues: list[str] = []

    for var in feat_cfg["lags"]["variables"]:
        for k in feat_cfg["lags"]["weeks"]:
            col = f"{var}_lag{k}"
            mism = _count_mismatch(d[col], grouped[var].shift(k))
            if mism:
                issues.append(f"{col}: {mism} mismatches")

    shift = int(feat_cfg["rolling"].get("shift", 1))
    for var in feat_cfg["rolling"]["variables"]:
        for w in feat_cfg["rolling"]["windows"]:
            col = f"{var}_roll{w}"
            expected = grouped[var].transform(
                lambda s, w=w: s.shift(shift).rolling(w, min_periods=w).mean()
            )
            mism = _count_mismatch(d[col], expected)
            if mism:
                issues.append(f"{col}: {mism} mismatches")

    passed = not issues
    detail = (
        "all lag/rolling features equal their reconstructed past values "
        "(causal, no future leakage)"
        if passed
        else "; ".join(issues)
    )
    return Check("feature_leakage", passed, detail, issues)


# --- Temporal split --------------------------------------------------------


def _time_key(df: pd.DataFrame) -> pd.Series:
    return df["iso_year"] * 100 + df["week_of_year"]


def temporal_split(
    df: pd.DataFrame, test_weeks: int
) -> tuple[pd.DataFrame, pd.DataFrame, dict[str, int]]:
    """Split into (train, test): the most-recent ``test_weeks`` ISO weeks → test."""
    timeline = (
        df[["iso_year", "week_of_year"]]
        .drop_duplicates()
        .sort_values(["iso_year", "week_of_year"])
        .reset_index(drop=True)
    )
    split_row = timeline.iloc[len(timeline) - test_weeks]
    split_t = int(split_row["iso_year"]) * 100 + int(split_row["week_of_year"])
    tk = _time_key(df)
    train = df[tk < split_t].sort_values(KEY).reset_index(drop=True)
    test = df[tk >= split_t].sort_values(KEY).reset_index(drop=True)
    return train, test, {
        "split_iso_year": int(split_row["iso_year"]),
        "split_week_of_year": int(split_row["week_of_year"]),
    }


# --- Checks over the split -------------------------------------------------


def check_class_distribution(train: pd.DataFrame, test: pd.DataFrame) -> Check:
    issues: list[str] = []
    detail_rows: list[str] = []
    for disease in DISEASES:
        for kind in LABEL_KINDS:
            col = f"{disease}_{kind}"
            tr = train[col].value_counts()
            te = test[col].value_counts()
            detail_rows.append(
                f"{col}: train={ {c: int(tr.get(c, 0)) for c in CLASSES} } "
                f"test={ {c: int(te.get(c, 0)) for c in CLASSES} }"
            )
            for cls in CLASSES:
                if int(tr.get(cls, 0)) == 0:
                    issues.append(f"{col}: class {cls} absent from TRAIN")
                if int(te.get(cls, 0)) == 0:
                    issues.append(f"{col}: class {cls} absent from TEST")
    passed = not issues
    detail = "every class present in both splits" if passed else "; ".join(issues)
    return Check("class_distribution", passed, detail, detail_rows)


def check_missing_values(train: pd.DataFrame, test: pd.DataFrame) -> Check:
    """Keys + raw must be complete; only documented engineered/label columns may
    be null (lags/rollings after exclusion should be complete; anomalies may be
    null for the first seasonal cycle)."""
    required = ["city", "iso_year", "week_of_year", "temperature", "humidity",
               "precipitation", "pm2_5", "pm10", "us_aqi", "aqi_available"]
    issues: list[str] = []
    rows: list[str] = []
    for name, part in (("train", train), ("test", test)):
        for col in required:
            n = int(part[col].isna().sum())
            if n:
                issues.append(f"{name}.{col}: {n} unexpected nulls")
        # Surface the documented nullable columns' counts (not a failure).
        anom_nulls = {c: int(part[c].isna().sum()) for c in part.columns if c.endswith("_anom")}
        rows.append(f"{name}: anomaly nulls (first-cycle climatology) = {anom_nulls}")
    passed = not issues
    detail = ("keys and raw values complete; remaining nulls are documented "
              "(anomaly first-cycle, labels)") if passed else "; ".join(issues)
    return Check("missing_values", passed, detail, rows)


def check_temporal_split(train: pd.DataFrame, test: pd.DataFrame) -> Check:
    max_train = int(_time_key(train).max())
    min_test = int(_time_key(test).min())
    passed = max_train < min_test
    detail = (
        f"train <= {max_train // 100}-W{max_train % 100:02d} < "
        f"test >= {min_test // 100}-W{min_test % 100:02d}"
    )
    if not passed:
        detail = f"TEMPORAL OVERLAP: max train time {max_train} >= min test time {min_test}"
    return Check("temporal_split", passed, detail)


def check_contamination(train: pd.DataFrame, test: pd.DataFrame) -> Check:
    train_keys = set(map(tuple, train[KEY].to_numpy()))
    test_keys = set(map(tuple, test[KEY].to_numpy()))
    shared = train_keys & test_keys
    passed = not shared
    detail = "no (city, year, week) shared between train and test" if passed else (
        f"{len(shared)} contaminating keys shared between train and test"
    )
    return Check("contamination", passed, detail)


def check_label_consistency(df: pd.DataFrame, label_cfg: dict[str, Any]) -> Check:
    """Probabilities sum to 1 (where defined) and hard labels match thresholds."""
    issues: list[str] = []
    for disease in DISEASES:
        probs = df[[f"{disease}_prob_low", f"{disease}_prob_medium", f"{disease}_prob_high"]]
        defined = probs.notna().all(axis=1)
        s = probs[defined].sum(axis=1).to_numpy()
        if not np.allclose(s, 1.0):
            issues.append(f"{disease}: {int((~np.isclose(s, 1.0)).sum())} prob rows not summing to 1")

        dcfg = label_cfg["diseases"][disease]
        recomputed = hard_label(
            df[f"{disease}_score"].to_numpy(),
            float(dcfg["thresholds"]["low_medium"]),
            float(dcfg["thresholds"]["medium_high"]),
        )
        stored = df[f"{disease}_label"].to_numpy()
        mism = sum(
            1 for a, b in zip(stored, recomputed)
            if not ((a is None and b is None) or a == b)
        )
        if mism:
            issues.append(f"{disease}_label: {mism} rows disagree with thresholds")
    passed = not issues
    detail = ("probabilities sum to 1 and hard labels match their thresholds"
              if passed else "; ".join(issues))
    return Check("label_consistency", passed, detail, issues)


def feature_statistics(train: pd.DataFrame, test: pd.DataFrame) -> Check:
    """Summary stats for key features; flag any zero-variance feature in train."""
    feats = [c for c in train.columns
             if (_LAG_RE.search(c) or _ROLL_RE.search(c) or c.endswith("_anom")
                 or c in ("temperature", "humidity", "precipitation", "pm2_5",
                          "pm10", "us_aqi", "week_sin", "week_cos"))]
    zero_var = [c for c in feats if float(train[c].std(skipna=True) or 0.0) == 0.0]
    rows: list[str] = []
    for c in ("temperature", "humidity", "precipitation", "pm2_5", "us_aqi"):
        rows.append(
            f"{c}: train μ={train[c].mean():.2f} σ={train[c].std():.2f} "
            f"[{train[c].min():.1f},{train[c].max():.1f}] | "
            f"test μ={test[c].mean():.2f} σ={test[c].std():.2f} "
            f"[{test[c].min():.1f},{test[c].max():.1f}]"
        )
    passed = not zero_var
    detail = ("no zero-variance features in train" if passed
              else f"zero-variance features: {zero_var}")
    return Check("feature_statistics", passed, detail, rows)


# --- Freeze + manifest -----------------------------------------------------


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def freeze(
    train: pd.DataFrame,
    test: pd.DataFrame,
    split_info: dict[str, int],
    excluded: int,
    checks: list[Check],
    data_dir: Path,
) -> dict[str, Any]:
    """Write train/test parquet and the committed split manifest; return manifest."""
    processed = paths.ensure_dir(data_dir / "processed")
    train_path = processed / "train.parquet"
    test_path = processed / "test.parquet"
    train.to_parquet(train_path, index=False)
    test.to_parquet(test_path, index=False)

    manifest = {
        "split": {
            "test_weeks": int(len(test[["iso_year", "week_of_year"]].drop_duplicates())),
            "split_point": {
                "iso_year": split_info["split_iso_year"],
                "week_of_year": split_info["split_week_of_year"],
            },
            "train_rows": int(len(train)),
            "test_rows": int(len(test)),
            "excluded_insufficient_history_rows": int(excluded),
        },
        "train_sha256": _sha256_file(train_path),
        "test_sha256": _sha256_file(test_path),
        "checks": {c.name: ("PASS" if c.passed else "FAIL") for c in checks},
        "all_passed": all(c.passed for c in checks),
    }
    (processed / "split_manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return manifest


# --- Orchestration ---------------------------------------------------------


def run_validation(
    data_dir: Path | None = None, config: dict[str, Any] | None = None
) -> tuple[list[Check], dict[str, Any]]:
    data_dir = data_dir or paths.DATA_DIR
    config = config or load_pipeline()
    city_vocab = load_city_vocab()

    df = pd.read_parquet(data_dir / "interim" / "weekly_labelled.parquet")

    checks: list[Check] = []
    schema = build_schema(df, city_vocab)
    checks.append(check_schema(df, schema))
    checks.append(check_feature_leakage(df, config["features"]))
    checks.append(check_label_consistency(df, config["labels"]))

    # Exclude insufficient-history rows from the frozen datasets (documented).
    split_cfg = config["split"]
    excluded = 0
    kept = df
    if split_cfg.get("exclude_insufficient_lag_history", True):
        mask = df["insufficient_lag_history"].astype(bool)
        excluded = int(mask.sum())
        kept = df[~mask].reset_index(drop=True)

    train, test, split_info = temporal_split(kept, int(split_cfg["test_weeks"]))
    checks.append(check_temporal_split(train, test))
    checks.append(check_contamination(train, test))
    checks.append(check_class_distribution(train, test))
    checks.append(check_missing_values(train, test))
    checks.append(feature_statistics(train, test))

    manifest = freeze(train, test, split_info, excluded, checks, data_dir)
    return checks, manifest


# --- Report ----------------------------------------------------------------


def render_report(checks: list[Check], manifest: dict[str, Any]) -> str:
    all_passed = all(c.passed for c in checks)
    L: list[str] = []
    L.append("# Validation Report — ForeSeeMe Dataset Freeze ⛔")
    L.append("")
    L.append("**Sprint 2, Prompt 10 — Dataset Validation & Temporal Train/Test Freeze**")
    L.append("")
    L.append(f"## GATE: {'🟢 GREEN — modeling may proceed' if all_passed else '🔴 RED — DO NOT PROCEED'}")
    L.append("")
    sp = manifest["split"]
    L.append(f"- Temporal split point: test begins {sp['split_point']['iso_year']}-"
             f"W{sp['split_point']['week_of_year']:02d} "
             f"({sp['test_weeks']} test weeks).")
    L.append(f"- Train rows: {sp['train_rows']}  |  Test rows: {sp['test_rows']}  |  "
             f"Excluded (insufficient history): {sp['excluded_insufficient_history_rows']}")
    L.append(f"- train.parquet sha256: `{manifest['train_sha256']}`")
    L.append(f"- test.parquet  sha256: `{manifest['test_sha256']}`")
    L.append("")
    L.append("## Checks")
    L.append("")
    L.append("| Check | Status | Detail |")
    L.append("|-------|--------|--------|")
    for c in checks:
        L.append(f"| {c.name} | {'✅ PASS' if c.passed else '❌ FAIL'} | {c.detail} |")
    L.append("")
    for c in checks:
        if c.rows:
            L.append(f"### {c.name}")
            L.append("")
            for r in c.rows:
                L.append(f"- {r}")
            L.append("")
    return "\n".join(L)


def main() -> int:
    from app.logging_config import configure_logging

    configure_logging("INFO")
    checks, manifest = run_validation()
    report = render_report(checks, manifest)
    paths.ensure_dir(paths.REPORTS_DIR)
    (paths.REPORTS_DIR / "validation_report.md").write_text(report, encoding="utf-8")

    all_passed = all(c.passed for c in checks)
    for c in checks:
        print(f"  [{'PASS' if c.passed else 'FAIL'}] {c.name}: {c.detail}")
    print(f"GATE: {'GREEN' if all_passed else 'RED'}  "
          f"(train={manifest['split']['train_rows']} test={manifest['split']['test_rows']})")
    print(f"report -> {paths.REPORTS_DIR / 'validation_report.md'}")
    return 0 if all_passed else 1


if __name__ == "__main__":
    import sys

    sys.exit(main())
