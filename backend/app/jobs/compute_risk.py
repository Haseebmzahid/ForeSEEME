"""Batch inference & Firestore write job (Sprint 2, Prompt 15).

The scheduled job that closes the pipeline **model → Firestore → app**. For each
city it fetches a *trailing window* of recent weather/AQI (lagged/rolling features
need history, not just today), builds the **same engineered features** used in
training/serving (the Prompt 8 transforms, via ``app.feature_builder``), runs the
promoted model, and upserts one contract-valid ``riskEstimates`` document per city
using the Firebase Admin SDK (service account — ADR-001/002).

Design for testability & safety:

* Two seams — :class:`WeeklyBaseProvider` (recent data) and
  :class:`RiskRepository` (Firestore) — are injected, so the whole job runs
  offline against fakes (mock weather/AQI + mock Firestore).
* **Idempotent** per ``(city, date)``: the document id is ``{city}_{YYYY-MM-DD}``
  and writes use ``set(merge=True)``, so re-running a day overwrites rather than
  duplicates (same pattern as the Sprint 1 seed script).
* One city's missing data or error never aborts the run — it is logged and
  skipped; the others still write.
* Never imports Flutter or the VALIDATION_ONLY disease-reference module.

Run (standalone, container-friendly)::

    # emulator (no credentials):
    FIRESTORE_EMULATOR_HOST=localhost:8080 python -m app.jobs.compute_risk
    # real project (local ADC or attached Cloud Run service account):
    FIREBASE_PROJECT_ID=foreseeme-83587 python -m app.jobs.compute_risk
"""

from __future__ import annotations

import json
import logging
import math
import os
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta, timezone
from typing import Any, Protocol

import pandas as pd

from app.explain import AttributionSet, compute_attributions
from app.disease_estimates import independent_estimates
from app.feature_builder import engineer_serving_features
from app.jobs import observability
from app.predict import (
    classify_dominant,
    display_disease,
    load_bundle,
    resolve_artifact_path,
    resolve_low_confidence_threshold,
)
from app.schemas import RiskEstimateResponse
from ml.pipelines import clean, merge
from ml.pipelines import acquire_weather as aw
from ml.pipelines.acquisition_base import Window

logger = logging.getLogger("foreseeme.jobs.compute_risk")

JOB_NAME = "compute_risk"
COLLECTION = "riskEstimates"
KEY = ["city", "iso_year", "week_of_year"]
WEATHER_SOURCE = "open_meteo_weather"
AQI_SOURCE = "open_meteo_air_quality"


# --- Seams ------------------------------------------------------------------


class WeeklyBaseProvider(Protocol):
    """Supplies a city's recent **weekly base** table (the Prompt 7 schema).

    Returns enough trailing weeks for lag/rolling features, or ``None`` when the
    city has no usable recent data (the job skips and logs it).
    """

    def recent_weekly_base(self, city: dict[str, Any]) -> pd.DataFrame | None: ...


class RiskRepository(Protocol):
    """Idempotent upsert sink for ``riskEstimates`` documents."""

    def upsert(self, doc_id: str, body: dict[str, Any]) -> None: ...


class InsufficientObservations(ValueError):
    """A source is absent or older than the configured trailing-data policy."""


# --- Outcome ----------------------------------------------------------------


@dataclass
class CityOutcome:
    city: str
    status: str            # written | skipped_no_data | skipped_insufficient | error
    doc_id: str | None = None
    risk_level: str | None = None
    disease: str | None = None


@dataclass
class CityEstimate:
    """A city's contract estimate plus its genuine, additive attributions."""

    response: RiskEstimateResponse
    attributions: AttributionSet
    disease_estimates: list[dict[str, Any]] = field(default_factory=list)


# --- Config -----------------------------------------------------------------


def load_cities() -> list[dict[str, Any]]:
    """The five target cities (cities.yaml) — reused from the cleaning module."""
    return clean.load_cities()


# --- Core: one city's estimate ----------------------------------------------


def estimate_for_city_full(
    bundle: dict[str, Any],
    city_name: str,
    base: pd.DataFrame,
    generated_at: datetime,
) -> CityEstimate | None:
    """Engineer features over the trailing window, classify the dominant risk, and
    compute its **genuine, additive attributions** (Sprint 5, Prompt 5).

    The attributions explain the SAME dominant disease the estimate reports, so the
    explained ``predictedClass`` / ``confidence`` match the document's ``riskLevel``
    / ``confidence``. Returns ``None`` when the latest week lacks the core
    conditions needed for a contract-valid document.
    """
    if base is None or base.empty:
        return None

    base_sorted = base.sort_values(KEY)
    latest = base_sorted.iloc[-1]
    conditions = [latest.get(column) for column in ("temperature", "humidity", "us_aqi")]
    if any(value is None or pd.isna(value) or not math.isfinite(float(value)) for value in conditions):
        return None  # Never substitute an older week's conditions or missing AQI.
    temperature, humidity, aqi = map(float, conditions)

    feature_names = bundle["feature_names"]
    engineered = engineer_serving_features(base, feature_names).sort_values(KEY)
    latest_features = engineered.iloc[[-1]][feature_names].astype(float)
    disease, risk_level, confidence = classify_dominant(bundle, latest_features)
    confidence = round(confidence, 4)

    response = RiskEstimateResponse(
        city=city_name,
        risk_level=risk_level,
        disease=display_disease(disease),
        confidence=confidence,
        temperature=round(temperature, 2),
        humidity=round(humidity, 2),
        aqi=round(aqi, 2),
        generated_at=generated_at,
        model_version=bundle["model_version"],
        low_confidence=confidence < resolve_low_confidence_threshold(bundle),
    )
    attributions = compute_attributions(bundle, disease, latest_features)
    return CityEstimate(
        response=response, attributions=attributions,
        disease_estimates=independent_estimates(bundle, latest_features, generated_at),
    )


def estimate_for_city(
    bundle: dict[str, Any],
    city_name: str,
    base: pd.DataFrame,
    generated_at: datetime,
) -> RiskEstimateResponse | None:
    """Contract estimate for one city (thin wrapper over :func:`estimate_for_city_full`).

    Sprint M6.4 clarification: :func:`run`/:func:`backfill` (the actual
    scheduled job) call :func:`estimate_for_city_full` directly and do not use
    this wrapper — it is kept as the minimal, attribution-free public accessor
    for any caller (a script, a notebook, a future integration) that only wants
    the frozen :class:`~app.schemas.RiskEstimateResponse` shape without also
    handling :class:`CityEstimate`/:class:`~app.explain.AttributionSet`. This is
    a one-line field extraction (``full.response``), not a second
    classification implementation, so it cannot diverge from
    :func:`estimate_for_city_full` the way a duplicated computation could —
    ``test_estimate_for_city_wrapper_matches_full`` in
    ``backend/tests/test_compute_risk.py`` pins that equivalence.
    """
    full = estimate_for_city_full(bundle, city_name, base, generated_at)
    return full.response if full is not None else None


def document_id(city_name: str, generated_at: datetime) -> str:
    """``{city}_{YYYY-MM-DD}`` — the idempotent (city, date) key (RISK_SCHEMA.md)."""
    return f"{city_name}_{generated_at.strftime('%Y-%m-%d')}"


def _document_body(estimate: CityEstimate) -> dict[str, Any]:
    """Serialise a full estimate to its Firestore document.

    The frozen risk contract is emitted unchanged; the genuine attributions are
    attached **additively** under ``attributions`` (a purely additive field — old
    readers/documents that ignore it are unaffected). See docs/RISK_SCHEMA.md.
    """
    body = estimate.response.model_dump(by_alias=True, mode="json")
    body["attributions"] = estimate.attributions.model_dump(by_alias=True, mode="json")
    body["diseaseEstimates"] = estimate.disease_estimates
    return body


def _iso_week_start(iso_year: int, week_of_year: int) -> datetime:
    """The UTC datetime for the Monday of an ISO ``(year, week)`` — the canonical
    calendar date used to id/date a backfilled weekly estimate."""
    d = date.fromisocalendar(int(iso_year), int(week_of_year), 1)
    return datetime(d.year, d.month, d.day, tzinfo=timezone.utc)


# --- Orchestration ----------------------------------------------------------


def run(
    provider: WeeklyBaseProvider,
    repository: RiskRepository,
    *,
    bundle: dict[str, Any] | None = None,
    cities: list[dict[str, Any]] | None = None,
    generated_at: datetime | None = None,
) -> list[CityOutcome]:
    """Compute and upsert one risk document per city; never abort on one city."""
    bundle = bundle or load_bundle(resolve_artifact_path())
    cities = cities or load_cities()
    generated_at = generated_at or datetime.now(timezone.utc)

    outcomes: list[CityOutcome] = []
    for city in cities:
        name = city["name"]
        try:
            base = provider.recent_weekly_base(city)
        except InsufficientObservations:
            outcomes.append(CityOutcome(name, "skipped_insufficient"))
            continue  # Provider already logged source/variable freshness details.
        except Exception as exc:  # one city's fetch failure must not kill the run
            logger.error("city_fetch_failed", extra={"city": name, "error": str(exc)})
            outcomes.append(CityOutcome(name, "error"))
            continue

        if base is None or base.empty:
            logger.warning("city_skipped_no_data", extra={"city": name})
            outcomes.append(CityOutcome(name, "skipped_no_data"))
            continue

        estimate = estimate_for_city_full(bundle, name, base, generated_at)
        if estimate is None:
            logger.warning("city_skipped_insufficient", extra={"city": name})
            outcomes.append(CityOutcome(name, "skipped_insufficient"))
            continue

        body = _document_body(estimate)
        doc_id = document_id(name, generated_at)
        repository.upsert(doc_id, body)
        logger.info(
            "risk_upserted",
            extra={"city": name, "doc_id": doc_id,
                   "riskLevel": body["riskLevel"], "disease": body["disease"]},
        )
        outcomes.append(CityOutcome(name, "written", doc_id,
                                    body["riskLevel"], body["disease"]))
    return outcomes


def backfill(
    provider: WeeklyBaseProvider,
    repository: RiskRepository,
    *,
    weeks: int = 6,
    bundle: dict[str, Any] | None = None,
    cities: list[dict[str, Any]] | None = None,
) -> list[CityOutcome]:
    """Backfill the last ``weeks`` **weekly** ``riskEstimates`` per city.

    Reuses the SAME feature-engineering + model path as :func:`run` / the
    scheduled job (:func:`estimate_for_city`), only evaluated at each historical
    week's *cutoff*: for a target week ``W`` the base is truncated to weeks
    ``<= W`` so ``estimate_for_city`` classifies week ``W`` using its own trailing
    lags/rollings. Every point is therefore a **genuine, leakage-free** estimate
    for that week — never a re-dated copy of "today", and no fabricated values.

    Idempotent per ``(city, week)`` via the ``{city}_{YYYY-MM-DD}`` doc id (the
    Monday of the ISO week). One city's/week's missing data is skipped + logged;
    the rest still write.
    """
    bundle = bundle or load_bundle(resolve_artifact_path())
    cities = cities or load_cities()

    outcomes: list[CityOutcome] = []
    for city in cities:
        name = city["name"]
        try:
            base = provider.recent_weekly_base(city)
        except Exception as exc:  # one city's fetch failure must not kill the run
            logger.error("city_fetch_failed", extra={"city": name, "error": str(exc)})
            outcomes.append(CityOutcome(name, "error"))
            continue

        if base is None or base.empty:
            logger.warning("city_skipped_no_data", extra={"city": name})
            outcomes.append(CityOutcome(name, "skipped_no_data"))
            continue

        ordered = base.sort_values(KEY).reset_index(drop=True)
        week_keys = list(
            ordered[["iso_year", "week_of_year"]]
            .drop_duplicates()
            .itertuples(index=False, name=None)
        )
        targets = week_keys[-weeks:]  # the most recent `weeks` real data weeks

        for iso_year, woy in targets:
            cutoff = ordered[
                (ordered["iso_year"] < iso_year)
                | ((ordered["iso_year"] == iso_year) & (ordered["week_of_year"] <= woy))
            ]
            generated_at = _iso_week_start(iso_year, woy)
            estimate = estimate_for_city_full(bundle, name, cutoff, generated_at)
            if estimate is None:
                logger.info(
                    "week_skipped_insufficient",
                    extra={"city": name, "iso_year": int(iso_year), "week": int(woy)},
                )
                outcomes.append(CityOutcome(name, "skipped_insufficient"))
                continue

            body = _document_body(estimate)
            doc_id = document_id(name, generated_at)
            repository.upsert(doc_id, body)
            logger.info(
                "risk_backfilled",
                extra={"city": name, "doc_id": doc_id,
                       "riskLevel": body["riskLevel"], "disease": body["disease"]},
            )
            outcomes.append(CityOutcome(name, "written", doc_id,
                                        body["riskLevel"], body["disease"]))
    return outcomes


# --- Observability: heartbeat + failure signal (Sprint 5, Prompt 15→P12) ----


def classify_run(outcomes: list[CityOutcome], *, cities_count: int) -> str:
    """Grade a scheduled run's health for the heartbeat/alert signal.

    * ``failed``   — nothing was written though cities exist: the pipeline produced
      no fresh estimates, so the app would show stale risk (audit H1). This is the
      "zero output unexpectedly" case an operator must act on.
    * ``degraded`` — some cities were written but others errored/were skipped: the
      run partially succeeded and is worth a look, but not a hard failure.
    * ``ok``       — one estimate written per city, no errors.
    """
    written = sum(1 for o in outcomes if o.status == "written")
    if written == 0 and cities_count > 0:
        return observability.STATUS_FAILED
    if written < cities_count or any(o.status == "error" for o in outcomes):
        return observability.STATUS_DEGRADED
    return observability.STATUS_OK


def run_and_report(
    provider: WeeklyBaseProvider,
    repository: RiskRepository,
    *,
    heartbeat: observability.HeartbeatSink,
    bundle: dict[str, Any] | None = None,
    cities: list[dict[str, Any]] | None = None,
    generated_at: datetime | None = None,
) -> tuple[observability.RunReport, list[CityOutcome]]:
    """Run the scheduled job and emit its heartbeat + run-summary signal.

    Thin observability wrapper over :func:`run` (unchanged): grades the run, writes
    the ``jobHeartbeats/compute_risk`` document, and logs ``job_run`` at INFO (ok) or
    ERROR (degraded/failed). A crash before outcomes are produced emits a ``failed``
    heartbeat and re-raises so the process exits non-zero (Scheduler/Run marks the
    run failed). Backfill is intentionally NOT wrapped — it is a manual, operator-run
    operation, not the monitored weekly cadence.
    """
    cities = cities or load_cities()
    started_at = datetime.now(timezone.utc)
    generated_at = generated_at or started_at
    try:
        bundle = bundle or load_bundle(resolve_artifact_path())
        outcomes = run(
            provider, repository, bundle=bundle, cities=cities,
            generated_at=generated_at,
        )
    except Exception:  # unexpected: emit a failed signal, then propagate
        report = observability.failed_report(
            JOB_NAME, started_at, datetime.now(timezone.utc),
            "job_execution_failed",
        )
        observability.emit(report, sink=heartbeat, logger=logger)
        raise

    status = classify_run(outcomes, cities_count=len(cities))
    report = observability.RunReport(
        JOB_NAME, status, started_at, datetime.now(timezone.utc),
        counts=observability.count_by_status(outcomes),
        model_version=bundle["model_version"] if status == observability.STATUS_OK else None,
    )
    observability.emit(report, sink=heartbeat, logger=logger)
    logger.info("run_evidence", extra={
        "event": "run_evidence", "startedAt": report.started_at.isoformat(),
        "finishedAt": report.finished_at.isoformat(), "generatedAt": generated_at.isoformat(),
        "status": report.status, "counts": report.counts,
        "heartbeatWritten": not (report.error or "").startswith("heartbeat_write_failed:"),
        "cities": [{"city": o.city, "status": o.status, "doc_id": o.doc_id} for o in outcomes],
    })
    return report, outcomes


# --- Firestore repository (service-account writes only) ---------------------


class FirestoreRiskRepository:
    """Upserts ``riskEstimates`` via the Admin SDK (idempotent ``set(merge=True)``)."""

    def __init__(self, collection: Any) -> None:
        self._collection = collection

    def upsert(self, doc_id: str, body: dict[str, Any]) -> None:
        self._collection.document(doc_id).set(body, merge=True)


def init_firestore_repository() -> FirestoreRiskRepository:
    """Use ADC for real Firestore, anonymous credentials for the emulator.

    ADC supports local gcloud login, optional credential files, and Cloud Run's
    attached identity. An explicitly configured project must match a reused app.
    """
    from app.jobs.firestore_runtime import get_firestore_client

    return FirestoreRiskRepository(get_firestore_client().collection(COLLECTION))


# --- Real provider: recent Open-Meteo weather + AQI -> weekly base ----------


class OpenMeteoWeeklyBaseProvider:
    """Fetches a trailing window of recent weather/AQI and builds a weekly base.

    Reuses the acquisition framework (Prompt 2) plus the cleaning (Prompt 6) and
    merging (Prompt 7) transforms, so the base this produces is built by the SAME
    code as the training data — no divergence. The HTTP getter and cache dir are
    injectable for offline testing.
    """

    def __init__(
        self,
        *,
        lookback_weeks: int = 12,
        data_delay_days: int = 5,
        weather_max_trailing_gap_days: int | None = None,
        aqi_max_trailing_gap_days: int | None = None,
        data_dir: Any | None = None,
        get: Any | None = None,
    ) -> None:
        from ml.pipelines.acquisition_base import AcquisitionBase

        if lookback_weeks < 1 or data_delay_days < 0:
            raise ValueError("Lookback must be positive and data delay must be non-negative")
        self._client = AcquisitionBase(data_dir=data_dir, get=get)
        self._lookback_weeks = lookback_weeks
        # ERA5 archive data can lag by five days. Use one common historical
        # window for weather and AQI rather than including today's partial data.
        self._data_delay_days = data_delay_days
        self._freshness = {
            WEATHER_SOURCE: int(os.getenv("RISK_WEATHER_MAX_TRAILING_GAP_DAYS", "0"))
            if weather_max_trailing_gap_days is None else weather_max_trailing_gap_days,
            AQI_SOURCE: int(os.getenv("RISK_AQI_MAX_TRAILING_GAP_DAYS", "0"))
            if aqi_max_trailing_gap_days is None else aqi_max_trailing_gap_days,
        }
        if any(gap < 0 for gap in self._freshness.values()):
            raise ValueError("Freshness trailing gaps must be non-negative")
        self._sources = clean.load_sources()
        self._cleaning = clean.load_cleaning_config()
        self._aliases = clean._canonical_aliases(clean.load_cities())

    def _recent_window(self) -> Window:
        end = datetime.now(timezone.utc).date() - timedelta(days=self._data_delay_days)
        start = end - timedelta(weeks=self._lookback_weeks)
        return Window(start=start.isoformat(), end=end.isoformat())

    def _fetch_clean_daily(
        self, source_key: str, subdir: str, city: dict[str, Any], window: Window,
        add_aqi_flag: bool,
    ) -> pd.DataFrame:
        source = self._sources[source_key]
        specs = aw.variable_specs(source)
        # latest_confirmed is a training-time observation, not a live API limit.
        coverage = source.get("coverage", {})
        effective, clipped = aw.clip_to_coverage(
            window, {"earliest_confirmed": coverage.get("earliest_confirmed")},
        )
        if clipped:
            logger.info("window_clipped", extra={"city": city["name"],
                                                 "source": source_key})
        params = aw.build_params(city, specs, effective)
        result = self._client.fetch_with_cache(
            source=source_key, city=city["name"], window=effective,
            url=source["base_url"], params=params, subdir=subdir,
        )
        raw = json.loads(result.path.read_text(encoding="utf-8"))
        cleans = clean.variable_cleans(source, self._cleaning)
        max_gap = int(self._cleaning["max_interpolation_gap_days"])
        daily, stats = clean.clean_city(
            raw, source_key, city["name"], effective, cleans, max_gap,
            self._aliases, add_aqi_flag=add_aqi_flag,
        )
        # coverage_end describes real, range-valid observations BEFORE any
        # interpolation; cached payloads are revalidated on every use.
        cutoff = date.fromisoformat(window.end) - timedelta(days=self._freshness[source_key])
        for variable in stats.variables:
            if variable.coverage_end is None or date.fromisoformat(variable.coverage_end) < cutoff:
                logger.warning("city_skipped_observations", extra={
                    "city": city["name"], "source": source_key,
                    "variable": variable.variable, "last_observation": variable.coverage_end,
                    "required_since": cutoff.isoformat(), "requested_end": window.end,
                    "max_trailing_gap_days": self._freshness[source_key],
                    "reason": "unavailable" if variable.coverage_end is None else "stale",
                })
                raise InsufficientObservations("Required source observations unavailable or stale")
        return daily

    def recent_weekly_base(self, city: dict[str, Any]) -> pd.DataFrame | None:
        window = self._recent_window()
        weather_daily = self._fetch_clean_daily(
            WEATHER_SOURCE, "weather", city, window, add_aqi_flag=False)
        aqi_daily = self._fetch_clean_daily(
            AQI_SOURCE, "aqi", city, window, add_aqi_flag=True)
        base = merge.merge_sources(
            merge.aggregate_weekly_weather(weather_daily),
            merge.aggregate_weekly_aqi(aqi_daily),
        )
        return base if not base.empty else None


# --- Entry point ------------------------------------------------------------


def _parse_backfill(argv: list[str]) -> int | None:
    """Returns the requested backfill week-count when ``--backfill [N]`` is passed
    (default 6), else ``None`` for the normal single-run mode."""
    if "--backfill" not in argv:
        return None
    idx = argv.index("--backfill")
    if idx + 1 < len(argv) and argv[idx + 1].isdigit():
        return int(argv[idx + 1])
    return 6


def main(argv: list[str] | None = None) -> int:
    import sys

    from app.logging_config import configure_logging

    argv = sys.argv[1:] if argv is None else argv
    configure_logging(os.getenv("LOG_LEVEL", "INFO"))

    weeks = _parse_backfill(argv)
    is_backfill = weeks is not None

    # Backfill needs enough trailing weeks for BOTH the target window and the
    # lag/rolling features of the earliest target week.
    lookback = int(os.getenv("RISK_LOOKBACK_WEEKS", "12"))
    if is_backfill:
        lookback = max(lookback, weeks + 8)

    provider = OpenMeteoWeeklyBaseProvider(
        lookback_weeks=lookback, data_delay_days=int(os.getenv("RISK_DATA_DELAY_DAYS", "5")),
    )
    repository = init_firestore_repository()

    # Backfill is a manual operator operation (prints its own summary, no
    # heartbeat). The scheduled run is monitored: it emits a heartbeat + a
    # failure signal so a silent/empty run is detectable (audit H1).
    report: observability.RunReport | None = None
    if is_backfill:
        outcomes = backfill(provider, repository, weeks=weeks)
    else:
        heartbeat = observability.init_firestore_heartbeat_sink()
        report, outcomes = run_and_report(provider, repository, heartbeat=heartbeat)

    written = sum(1 for o in outcomes if o.status == "written")
    label = f"backfill({weeks}w)" if is_backfill else "run"
    for o in outcomes:
        if o.status == "written":
            print(f"  {o.city:11} {o.status:22} {o.doc_id} -> {o.risk_level} ({o.disease})")
        else:
            print(f"  {o.city:11} {o.status}")
    status_note = f" [{report.status}]" if report is not None else ""
    print(f"done [{label}]: {written} documents written to {COLLECTION}{status_note}")
    # A failed scheduled run exits non-zero so Cloud Scheduler/Run flags it too.
    return 1 if report is not None and report.status == observability.STATUS_FAILED else 0


if __name__ == "__main__":
    import sys

    sys.exit(main())
