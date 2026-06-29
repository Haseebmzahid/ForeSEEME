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
    # real project:
    GOOGLE_APPLICATION_CREDENTIALS=/secure/sa.json python -m app.jobs.compute_risk
"""

from __future__ import annotations

import json
import logging
import os
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any, Protocol

import pandas as pd

from app.feature_builder import engineer_serving_features
from app.predict import (
    LOW_CONFIDENCE_THRESHOLD,
    classify_dominant,
    display_disease,
    load_bundle,
    resolve_artifact_path,
)
from app.schemas import RiskEstimateResponse
from ml.pipelines import clean, merge, paths
from ml.pipelines import acquire_weather as aw
from ml.pipelines.acquisition_base import Window

logger = logging.getLogger("foreseeme.jobs.compute_risk")

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


# --- Outcome ----------------------------------------------------------------


@dataclass
class CityOutcome:
    city: str
    status: str            # written | skipped_no_data | skipped_insufficient | error
    doc_id: str | None = None
    risk_level: str | None = None
    disease: str | None = None


# --- Config -----------------------------------------------------------------


def load_cities() -> list[dict[str, Any]]:
    """The five target cities (cities.yaml) — reused from the cleaning module."""
    return clean.load_cities()


# --- Core: one city's estimate ----------------------------------------------


def _latest_finite(frame: pd.DataFrame, column: str) -> float | None:
    """Last non-null value of ``column`` in the (time-sorted) window, or None."""
    if column not in frame.columns:
        return None
    series = frame[column].dropna()
    return float(series.iloc[-1]) if not series.empty else None


def estimate_for_city(
    bundle: dict[str, Any],
    city_name: str,
    base: pd.DataFrame,
    generated_at: datetime,
) -> RiskEstimateResponse | None:
    """Engineer features over the trailing window, classify the dominant risk.

    Returns ``None`` when the latest week lacks the core conditions needed for a
    contract-valid document.
    """
    if base is None or base.empty:
        return None

    feature_names = bundle["feature_names"]
    engineered = engineer_serving_features(base, feature_names).sort_values(KEY)
    latest_features = engineered.iloc[[-1]][feature_names].astype(float)
    disease, risk_level, confidence = classify_dominant(bundle, latest_features)
    confidence = round(confidence, 4)

    base_sorted = base.sort_values(KEY)
    temperature = _latest_finite(base_sorted, "temperature")
    humidity = _latest_finite(base_sorted, "humidity")
    aqi = _latest_finite(base_sorted, "us_aqi")
    if temperature is None or humidity is None:
        return None  # current conditions missing -> skip this city

    return RiskEstimateResponse(
        city=city_name,
        risk_level=risk_level,
        disease=display_disease(disease),
        confidence=confidence,
        temperature=round(temperature, 2),
        humidity=round(humidity, 2),
        aqi=round(aqi, 2) if aqi is not None else 0.0,  # contract requires aqi >= 0
        generated_at=generated_at,
        model_version=bundle["model_version"],
        low_confidence=confidence < LOW_CONFIDENCE_THRESHOLD,
    )


def document_id(city_name: str, generated_at: datetime) -> str:
    """``{city}_{YYYY-MM-DD}`` — the idempotent (city, date) key (RISK_SCHEMA.md)."""
    return f"{city_name}_{generated_at.strftime('%Y-%m-%d')}"


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
        except Exception as exc:  # one city's fetch failure must not kill the run
            logger.error("city_fetch_failed", extra={"city": name, "error": str(exc)})
            outcomes.append(CityOutcome(name, "error"))
            continue

        if base is None or base.empty:
            logger.warning("city_skipped_no_data", extra={"city": name})
            outcomes.append(CityOutcome(name, "skipped_no_data"))
            continue

        estimate = estimate_for_city(bundle, name, base, generated_at)
        if estimate is None:
            logger.warning("city_skipped_insufficient", extra={"city": name})
            outcomes.append(CityOutcome(name, "skipped_insufficient"))
            continue

        body = estimate.model_dump(by_alias=True, mode="json")
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


# --- Firestore repository (service-account writes only) ---------------------


class FirestoreRiskRepository:
    """Upserts ``riskEstimates`` via the Admin SDK (idempotent ``set(merge=True)``)."""

    def __init__(self, collection: Any) -> None:
        self._collection = collection

    def upsert(self, doc_id: str, body: dict[str, Any]) -> None:
        self._collection.document(doc_id).set(body, merge=True)


def init_firestore_repository() -> FirestoreRiskRepository:
    """Initialise the Admin SDK from the environment (Sprint 1 seed-script pattern).

    Prefers a real service account (``GOOGLE_APPLICATION_CREDENTIALS``); falls back
    to the emulator (``FIRESTORE_EMULATOR_HOST``). Never hardcodes credentials or a
    project id. ``firebase_admin`` is imported lazily so the API service does not
    depend on it.
    """
    import firebase_admin
    from firebase_admin import credentials, firestore

    if not firebase_admin._apps:
        cred_path = os.getenv("GOOGLE_APPLICATION_CREDENTIALS")
        emulator = os.getenv("FIRESTORE_EMULATOR_HOST")
        if cred_path:
            logger.info("firestore_auth", extra={"mode": "service_account"})
            firebase_admin.initialize_app(credentials.Certificate(cred_path))
        elif emulator:
            project_id = (os.getenv("FIREBASE_PROJECT_ID")
                          or os.getenv("GCLOUD_PROJECT") or "demo-foreseeme")
            logger.info("firestore_auth", extra={"mode": "emulator",
                                                 "host": emulator, "project": project_id})
            firebase_admin.initialize_app(options={"projectId": project_id})
        else:
            raise SystemExit(
                "Set GOOGLE_APPLICATION_CREDENTIALS (real project) or "
                "FIRESTORE_EMULATOR_HOST (emulator) before running the job."
            )
    return FirestoreRiskRepository(firestore.client().collection(COLLECTION))


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
        data_dir: Any | None = None,
        get: Any | None = None,
    ) -> None:
        from ml.pipelines.acquisition_base import AcquisitionBase

        self._client = AcquisitionBase(data_dir=data_dir, get=get)
        self._lookback_weeks = lookback_weeks
        self._sources = clean.load_sources()
        self._cleaning = clean.load_cleaning_config()
        self._aliases = clean._canonical_aliases(clean.load_cities())

    def _recent_window(self) -> Window:
        end = datetime.now(timezone.utc).date()
        start = end - timedelta(weeks=self._lookback_weeks)
        return Window(start=start.isoformat(), end=end.isoformat())

    def _fetch_clean_daily(
        self, source_key: str, subdir: str, city: dict[str, Any], window: Window,
        add_aqi_flag: bool,
    ) -> pd.DataFrame:
        source = self._sources[source_key]
        specs = aw.variable_specs(source)
        effective, clipped = aw.clip_to_coverage(window, source.get("coverage", {}))
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
        daily, _stats = clean.clean_city(
            raw, source_key, city["name"], effective, cleans, max_gap,
            self._aliases, add_aqi_flag=add_aqi_flag,
        )
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


def main() -> int:
    from app.logging_config import configure_logging

    configure_logging(os.getenv("LOG_LEVEL", "INFO"))
    provider = OpenMeteoWeeklyBaseProvider(
        lookback_weeks=int(os.getenv("RISK_LOOKBACK_WEEKS", "12"))
    )
    repository = init_firestore_repository()
    outcomes = run(provider, repository)

    written = sum(1 for o in outcomes if o.status == "written")
    for o in outcomes:
        if o.status == "written":
            print(f"  {o.city:11} {o.status:22} {o.doc_id} -> {o.risk_level} ({o.disease})")
        else:
            print(f"  {o.city:11} {o.status}")
    print(f"done: {written}/{len(outcomes)} cities written to {COLLECTION}")
    return 0


if __name__ == "__main__":
    import sys

    sys.exit(main())
