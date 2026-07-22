# ForeSeeMe Preprocessing Pipeline (M5.3)

Lightweight map of the preprocessing responsibilities inside Module 5 —
`acquisition_common.py`, `clean.py`, `merge.py` — and where they hand off to
Module 6. This documents existing behavior; nothing described here changed
what any stage computes. See `docs/adr/` for architectural decisions and
`reports/*.md` for generated, run-specific output.

## Stage map

```
Raw Input               data/raw/<source>/<city>.json          (acquire_weather.py / acquire_aqi.py, M5.1)
   |
Validation               check_variables / validate_payload_structure   (acquisition_common.py, M5.1)
   |                     _require_raw_file                              (clean.py)
   |                     load_source_daily precondition                 (merge.py)
   v
Cleaning                 enforce_range, interpolate_short_gaps          (clean.py)
   v
Normalization            normalize_city, _canonical_aliases,
                          aggregate_daily                               (clean.py)
   v
Merge Preparation         with_iso_week, aggregate_weekly_weather,
                          aggregate_weekly_aqi                          (merge.py)
   v
Merge                     merge_sources                                (merge.py)
   v
  data/interim/weekly_base.parquet   <-- Module 5 / Module 6 boundary -->
   v
Feature Engineering       features.py, labels.py, validate.py, ml/training/, app/*   (Module 6)
```

Cleaning and Normalization are interleaved per variable inside
`clean.clean_city()` (normalize the city once; per variable: aggregate →
enforce range → interpolate) rather than run as two full passes over the
data — this is the existing, tested behavior and is unchanged by this
documentation pass.

## Stage responsibilities

| Stage | Responsibility | Functions | Module |
|---|---|---|---|
| Raw Input | Immutable per-city API responses, cached + hash-manifested | `AcquisitionBase.fetch_with_cache` | `acquisition_base.py` |
| Validation | Schema/structural checks on raw responses; precondition checks before a later stage reads another stage's output | `check_variables`, `validate_payload_structure`, `normalize_city` (unknown-city raise), `_require_raw_file`, `load_source_daily` | `acquisition_common.py`, `clean.py`, `merge.py` |
| Cleaning | Physical-range enforcement, missing-value/gap policy | `enforce_range`, `interpolate_short_gaps` | `clean.py` |
| Normalization | City-name canonicalization, hourly→daily granularity consistency | `normalize_city`, `_canonical_aliases`, `aggregate_daily` | `clean.py` |
| Merge Preparation | Daily → ISO-week key derivation and weekly aggregation per source | `with_iso_week`, `aggregate_weekly_weather`, `aggregate_weekly_aqi` | `merge.py` |
| Merge | Outer-join sources into one weekly, unlabelled, unengineered table | `merge_sources` | `merge.py` |
| Export | Frozen output consumed by Module 6 | `data/interim/weekly_base.parquet` (columns = `merge.COLUMNS`) | `merge.py` |

Quality **observability** (M5.2, `quality_report.py`) sits alongside these
stages, not inside them — it aggregates figures each stage already computes
and is never a dependency of any stage's actual behavior.

## Execution order

Each stage is its own CLI entry point (no orchestrator exists, and this
sprint does not add one):

```
python -m ml.pipelines.acquire_weather
python -m ml.pipelines.acquire_aqi
python -m ml.pipelines.clean
python -m ml.pipelines.merge
python -m ml.pipelines.features   # Module 6 — first step past the boundary
```

## Expected inputs / outputs per stage

| Stage | Reads | Writes |
|---|---|---|
| Raw Input | Open-Meteo HTTP APIs | `data/raw/weather/<city>.json`, `data/raw/aqi/<city>.json` + `.meta.json` sidecars |
| Validation + Cleaning + Normalization | `data/raw/<source>/<city>.json` | `data/interim/<source>/<city>.parquet` |
| Merge Preparation + Merge | `data/interim/weather/*.parquet`, `data/interim/aqi/*.parquet` | `data/interim/weekly_base.parquet` |
| Export (handoff) | `data/interim/weekly_base.parquet`, columns = `merge.COLUMNS` | consumed by `features.py` (Module 6) |

## Relationship to M5.1 ingestion

M5.1 already centralized acquisition-side validation
(`acquisition_common.check_variables`/`validate_payload_structure`) and
deduplicated the weather/AQI adapters. This sprint does not re-implement or
duplicate any of that — `clean.py` and `merge.py` never re-check what M5.1
already validated; their own Validation responsibility (`_require_raw_file`,
`load_source_daily`) covers a different concern: whether the *previous
stage's output* exists before this stage reads it.

## Handoff to Module 6

Module 6 (`features.py`, `labels.py`, `validate.py`, `ml/training/`, `app/*`)
reads exactly one file from Module 5: `data/interim/weekly_base.parquet`,
shaped by `merge.COLUMNS`. Module 6 has no knowledge of how that table was
produced — which source adapter, which cleaning policy, which merge
strategy — and must not gain any; that boundary is the whole point of this
stage map.
