# ForeSeeMe Preprocessing Pipeline (M5.1 – M5.5, final)

Lightweight map of Module 5's responsibilities — ingestion
(`acquisition_base.py`/`acquisition_common.py`/`acquire_*.py`), preprocessing
(`clean.py`/`merge.py`), observability (`quality_report.py`), and lineage
(`lineage.py`) — and where they hand off to Module 6. This documents existing
behavior; nothing described here changed what any stage computes. See
`docs/adr/` for architectural decisions and `reports/*.md`/`reports/*.json`
for generated, run-specific output.

## Stage map (final Module 5 architecture)

```
External Sources (Open-Meteo HTTP APIs)
   v
Acquisition               AcquisitionBase.fetch_with_cache               (acquisition_base.py, M5.1)
                          acquire_weather.py / acquire_aqi.py            (M5.1)
   v
Structural Validation     check_variables / validate_payload_structure   (acquisition_common.py, M5.1)
   |                     _require_raw_file                              (clean.py, M5.3)
   |                     load_source_daily precondition                 (merge.py, M5.3)
   v
Quality Reporting         QualityReport / StageQuality                  (quality_report.py, M5.2)
   v
Cleaning                  enforce_range, interpolate_short_gaps         (clean.py)
   v
Normalization             normalize_city, _canonical_aliases,
                          aggregate_daily                                (clean.py)
   v
Merge Preparation         with_iso_week, aggregate_weekly_weather,
                          aggregate_weekly_aqi                          (merge.py)
   v
Merge                     merge_sources                                (merge.py)
   v
Dataset Lineage           LineageRecord / lineage.json                  (lineage.py, M5.4/M5.5)
   v
Pipeline Summary          record_pipeline_stage / render_pipeline_summary (quality_report.py, M5.4/M5.5)
   v
  data/interim/weekly_base.parquet   <-- Module 5 / Module 6 boundary -->
   v
Feature Engineering       features.py, labels.py, validate.py, ml/training/, app/*   (Module 6)
```

Quality Reporting, Dataset Lineage, and Pipeline Summary **observe** the
pipeline — they aggregate figures the surrounding stages already compute and
are never imported by, or a dependency of, Module 6. If all three
disappeared, ingestion and preprocessing would behave identically; only
visibility into them would be lost.

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
| Dataset Lineage | Provenance for every parquet Module 5 writes: sources, inputs, row/column counts, checksum, schema version, consumer | `build_record`, `record_lineage` | `lineage.py` |
| Pipeline Summary | One cross-stage, human-readable run summary; boolean completion checks for non-timed concerns | `record_pipeline_stage`, `QualityReport.render_pipeline_summary` | `quality_report.py` |
| Export | Frozen output consumed by Module 6 | `data/interim/weekly_base.parquet` (columns = `merge.COLUMNS`) | `merge.py` |

Quality **Reporting** (M5.2) and **Dataset Lineage**/**Pipeline Summary**
(M5.4/M5.5) sit alongside the pipeline, not inside it — they aggregate
figures each stage already computes and are never a dependency of any
stage's actual behavior. See "Quality reporting, lineage, and the pipeline
summary" below for how the three relate.

## Execution order

Each stage is its own CLI entry point (no orchestrator exists, and this
sprint does not add one):

```
python -m ml.pipelines.acquire_disease_reference
python -m ml.pipelines.acquire_weather
python -m ml.pipelines.acquire_aqi
python -m ml.pipelines.clean
python -m ml.pipelines.merge
python -m ml.pipelines.features   # Module 6 — first step past the boundary
```

Each of the five commands above contributes one entry to the shared
`reports/pipeline_run.json` (see below); `merge.py`, run last, prints the
full cross-stage summary.

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

## Quality reporting, lineage, and the pipeline summary

Three related but distinct observability concerns, each with one job:

- **Quality reporting** (`quality_report.py`, M5.2) — per-source
  (`open_meteo_weather`, `open_meteo_air_quality`, `weekly_base`) figures:
  rows processed, missing/out-of-range/interpolated cell counts, warnings.
  Persisted at `reports/quality_<source>.json`, idempotently merged across
  separate stage runs (re-running a stage replaces its own entry).
- **Dataset lineage** (`lineage.py`, M5.4/M5.5) — one record per *output
  artifact* (each per-city interim parquet, plus `weekly_base.parquet`):
  what produced it, from what inputs, its checksum, row/column counts, and
  who consumes it next. Persisted at `data/interim/lineage.json`, mirroring
  `manifest.json`'s shape (a dict of entries keyed by output path).
- **Pipeline summary** (`quality_report.record_pipeline_stage` +
  `render_pipeline_summary`, M5.4/M5.5) — one cross-stage view spanning all
  five CLI commands (disease reference, weather/AQI acquisition, cleaning,
  merge), persisted at `reports/pipeline_run.json`. Reuses the same
  `QualityReport`/`StageQuality` machinery as per-source quality reports —
  it is not a second implementation, just a different `source` value
  (`pipeline_run`) that every stage's `main()` also contributes to.

None of the three recomputes anything: durations are timed once per stage
around calls that already happen; row/column counts come from the DataFrame
already in memory; checksums reuse `acquisition_base.sha256_file` (the same
hashing `manifest.json` uses for raw files). The only markers are plain
ASCII (`OK`/`FAIL`) — deliberately not Unicode checkmarks, since Windows'
default `cp1252` console encoding cannot print `✓`/`✗` and would crash a
pipeline run.

### Sample pipeline summary (real output, `python -m ml.pipelines.merge`)

```
============================================
Pipeline Summary
============================================
Disease Reference        OK   0.01s
Weather Acquisition      OK   28.73s
AQI Acquisition          OK   21.09s
Cleaning                 OK   2.92s
Merge                    OK   0.48s
Quality Report           OK
Dataset Lineage          OK
Output Generated         OK
============================================
Total Runtime: 53.22s
Output Dataset: data/interim/weekly_base.parquet
Metadata File: data/interim/lineage.json
Quality Report: reports/quality_weekly_base.json
============================================
```

Because no orchestrator ties the five commands together, `pipeline_run.json`
reflects the most recent run of *each* stage, which may span multiple
invocations over time — the same limitation the per-source quality reports
already have (M5.2), not a new one.

## Handoff to Module 6

Module 6 (`features.py`, `labels.py`, `validate.py`, `ml/training/`, `app/*`)
reads exactly one file from Module 5: `data/interim/weekly_base.parquet`,
shaped by `merge.COLUMNS`. Module 6 has no knowledge of how that table was
produced — which source adapter, which cleaning policy, which merge
strategy — and must not gain any; that boundary is the whole point of this
stage map.

## Known risk: shared raw-file cache key (found via M5.4/M5.5 lineage work)

`AcquisitionBase.fetch_with_cache`'s per-source layout keys the raw cache by
`(source, city)` only — `raw/<subdir>/<city>.json` — not by the requested
window (the window is recorded in `manifest.json`, not the filename; see
`paths.raw_relpath`). Module 6's `app/jobs/compute_risk.py` reuses
`acquire_weather.variable_specs`/`clip_to_coverage`/`build_params` to fetch a
short **trailing window** of recent data for serving, through the same
`AcquisitionBase.fetch_with_cache` call — and therefore the same cache key —
that the bulk `acquire_weather.py`/`acquire_aqi.py` pipelines use for the
full historical window.

Running the batch risk job silently overwrites the bulk historical raw cache
with its narrow trailing window. This is not hypothetical: it is exactly
what happened in this repository three weeks before M5.4/M5.5 (raw cache
narrowed to a ~13-week trailing window on 2026-07-01; the bulk historical
range was only restored by re-running `acquire_weather`/`acquire_aqi`
against the live API during this sprint's verification). Re-deriving
`weekly_base.parquet` from the narrowed cache in the meantime broke a
Module 6 test comparing serving-time to training-time features.

Fixing this would mean giving the two call sites distinct cache keys (e.g. a
window-aware raw path, or a separate subdir for trailing-window fetches) —
a change to `acquisition_base.py`'s caching contract and to `compute_risk.py`,
both out of scope for a Module-5-only sprint. Documented here so a future
Module 5 or Module 6 sprint can address it deliberately.
