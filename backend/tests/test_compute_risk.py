"""Tests for the batch inference & Firestore write job (Sprint 2, Prompt 15).

Uses fakes for both seams (mock weather/AQI via a fake weekly-base provider, mock
Firestore via an in-memory repository) to assert:
- one upsert per city, each a contract-valid document with the ``{city}_{date}`` id;
- re-running the same day is idempotent (no duplicates);
- a city with missing data is skipped + logged while the others still write;
- a provider error for one city does not abort the run;
- features are engineered over the trailing window (not a single week).
"""

from __future__ import annotations

import re
from datetime import datetime, timezone

import numpy as np
import pandas as pd
import pytest

from app.feature_builder import engineer_serving_features
from app.jobs import compute_risk as job
from app.predict import load_bundle, resolve_artifact_path
from app.schemas import RiskEstimateResponse

BUNDLE = load_bundle(resolve_artifact_path())
GENERATED_AT = datetime(2026, 6, 29, tzinfo=timezone.utc)
CITIES = [{"name": "Lahore"}, {"name": "Karachi"}, {"name": "Islamabad"}]
DOC_ID_RE = re.compile(r"^[A-Za-z]+_\d{4}-\d{2}-\d{2}$")


# --- Fakes ------------------------------------------------------------------


def _fake_base(city: str, n_weeks: int = 10, start_week: int = 10) -> pd.DataFrame:
    """A trailing window of plausible weekly base rows for one city."""
    rows = []
    for i in range(n_weeks):
        rows.append({
            "city": city,
            "iso_year": 2026,
            "week_of_year": start_week + i,
            "days_in_week": 7,
            "temperature": 20.0 + i,             # rising trend -> lags differ by week
            "humidity": 55.0 + (i % 5),
            "precipitation": 3.0 + (i % 4),
            "pm2_5": 30.0 + i,
            "pm10": 50.0 + i,
            "us_aqi": 90.0 + 2 * i,
            "aqi_available": True,
        })
    return pd.DataFrame(rows)


class FakeProvider:
    def __init__(self, bases: dict, errors: frozenset = frozenset()):
        self._bases = bases
        self._errors = errors

    def recent_weekly_base(self, city: dict):
        name = city["name"]
        if name in self._errors:
            raise RuntimeError("simulated upstream fetch failure")
        return self._bases.get(name)


class FakeRepository:
    def __init__(self):
        self.docs: dict[str, dict] = {}
        self.upsert_calls = 0

    def upsert(self, doc_id: str, body: dict) -> None:
        self.upsert_calls += 1
        self.docs[doc_id] = body          # keyed by id -> inherently idempotent


def _all_present() -> FakeProvider:
    return FakeProvider({c["name"]: _fake_base(c["name"]) for c in CITIES})


# --- One upsert per city, contract-valid, correct id ------------------------


def test_writes_one_contract_valid_doc_per_city() -> None:
    repo = FakeRepository()
    outcomes = job.run(_all_present(), repo, bundle=BUNDLE, cities=CITIES,
                       generated_at=GENERATED_AT)

    assert repo.upsert_calls == len(CITIES)
    assert len(repo.docs) == len(CITIES)
    assert all(o.status == "written" for o in outcomes)

    for city in CITIES:
        doc_id = f"{city['name']}_2026-06-29"
        assert doc_id in repo.docs
        assert DOC_ID_RE.match(doc_id)
        body = repo.docs[doc_id]
        # Re-validate against the frozen contract (alias keys accepted).
        estimate = RiskEstimateResponse(**body)
        assert estimate.city == city["name"]
        assert body["riskLevel"] in ("Low", "Medium", "High")
        assert body["disease"] in ("Dengue", "Smog", "Influenza")
        assert 0.0 <= body["confidence"] <= 1.0
        assert body["aqi"] >= 0.0
        assert body["modelVersion"] == BUNDLE["model_version"]
        assert body["lowConfidence"] == (body["confidence"] < 0.55)


# --- Idempotency ------------------------------------------------------------


def test_rerun_same_day_is_idempotent() -> None:
    repo = FakeRepository()
    job.run(_all_present(), repo, bundle=BUNDLE, cities=CITIES, generated_at=GENERATED_AT)
    first = dict(repo.docs)
    job.run(_all_present(), repo, bundle=BUNDLE, cities=CITIES, generated_at=GENERATED_AT)

    assert len(repo.docs) == len(CITIES)          # no duplicates created
    assert set(repo.docs) == set(first)           # same ids overwritten
    assert repo.upsert_calls == 2 * len(CITIES)


def test_different_dates_make_distinct_documents() -> None:
    repo = FakeRepository()
    job.run(_all_present(), repo, bundle=BUNDLE, cities=CITIES, generated_at=GENERATED_AT)
    next_day = datetime(2026, 6, 30, tzinfo=timezone.utc)
    job.run(_all_present(), repo, bundle=BUNDLE, cities=CITIES, generated_at=next_day)

    assert len(repo.docs) == 2 * len(CITIES)      # one per (city, date)
    assert "Lahore_2026-06-29" in repo.docs and "Lahore_2026-06-30" in repo.docs


# --- Graceful per-city handling ---------------------------------------------


def test_city_missing_data_is_skipped_others_written() -> None:
    bases = {c["name"]: _fake_base(c["name"]) for c in CITIES}
    bases["Karachi"] = None                       # no recent data for Karachi
    repo = FakeRepository()
    outcomes = job.run(FakeProvider(bases), repo, bundle=BUNDLE, cities=CITIES,
                       generated_at=GENERATED_AT)

    statuses = {o.city: o.status for o in outcomes}
    assert statuses["Karachi"] == "skipped_no_data"
    assert statuses["Lahore"] == "written" and statuses["Islamabad"] == "written"
    assert "Karachi_2026-06-29" not in repo.docs
    assert len(repo.docs) == len(CITIES) - 1


def test_provider_error_does_not_abort_run() -> None:
    bases = {c["name"]: _fake_base(c["name"]) for c in CITIES}
    repo = FakeRepository()
    outcomes = job.run(FakeProvider(bases, errors=frozenset({"Lahore"})), repo,
                       bundle=BUNDLE, cities=CITIES, generated_at=GENERATED_AT)

    statuses = {o.city: o.status for o in outcomes}
    assert statuses["Lahore"] == "error"
    assert statuses["Karachi"] == "written" and statuses["Islamabad"] == "written"
    assert len(repo.docs) == len(CITIES) - 1


def test_empty_base_is_skipped() -> None:
    bases = {c["name"]: _fake_base(c["name"]) for c in CITIES}
    bases["Islamabad"] = pd.DataFrame()
    repo = FakeRepository()
    outcomes = job.run(FakeProvider(bases), repo, bundle=BUNDLE, cities=CITIES,
                       generated_at=GENERATED_AT)
    statuses = {o.city: o.status for o in outcomes}
    assert statuses["Islamabad"] == "skipped_no_data"


# --- Features use the trailing window, not a single week --------------------


def test_features_use_trailing_window_history() -> None:
    """The latest week's lag features must reflect prior weeks (history used)."""
    base = _fake_base("Lahore", n_weeks=8, start_week=10)
    feats = BUNDLE["feature_names"]
    engineered = engineer_serving_features(base, feats).sort_values(job.KEY)
    last = engineered.iloc[-1]
    prev = base.sort_values(job.KEY).iloc[-2]
    # lag1(temperature) at the latest week == previous week's temperature.
    assert "temperature_lag1" in feats
    assert last["temperature_lag1"] == pytest.approx(prev["temperature"])
    assert not np.isnan(last["temperature_lag1"])


def test_document_id_format() -> None:
    assert job.document_id("Lahore", GENERATED_AT) == "Lahore_2026-06-29"
    assert DOC_ID_RE.match(job.document_id("Karachi", GENERATED_AT))


# --- Backfill: real, distinct, per-week historical estimates ----------------


def test_backfill_writes_one_contract_valid_doc_per_week() -> None:
    """`backfill(weeks=6)` produces 6 distinct dated docs per city, each a
    contract-valid estimate — reusing the same model path as the scheduled job."""
    repo = FakeRepository()
    outcomes = job.backfill(
        _all_present(), repo, weeks=6, bundle=BUNDLE, cities=CITIES,
    )

    assert all(o.status == "written" for o in outcomes)
    assert repo.upsert_calls == 6 * len(CITIES)
    assert len(repo.docs) == 6 * len(CITIES)  # 6 distinct (city, week) ids each

    for city in CITIES:
        ids = sorted(k for k in repo.docs if k.startswith(f"{city['name']}_"))
        assert len(ids) == 6
        dates = [k.split("_", 1)[1] for k in ids]
        assert len(set(dates)) == 6  # six distinct calendar weeks
        for doc_id in ids:
            assert DOC_ID_RE.match(doc_id)
            body = repo.docs[doc_id]
            RiskEstimateResponse(**body)  # re-validate against the frozen contract
            assert body["riskLevel"] in ("Low", "Medium", "High")
            assert body["modelVersion"] == BUNDLE["model_version"]


def test_backfill_points_are_real_per_week_not_redated_copies() -> None:
    """Each backfilled week is evaluated at its own cutoff, so the conditions
    (and thus the estimate) differ week to week — proving no re-dated duplication."""
    repo = FakeRepository()
    # _fake_base has a rising temperature/AQI trend, so per-week cutoffs differ.
    job.backfill(_all_present(), repo, weeks=6, bundle=BUNDLE, cities=[{"name": "Lahore"}])

    lahore = [repo.docs[k] for k in sorted(repo.docs) if k.startswith("Lahore_")]
    assert len(lahore) == 6
    temps = [d["temperature"] for d in lahore]
    aqis = [d["aqi"] for d in lahore]
    # Distinct trailing conditions per week (a re-dated single estimate would be
    # identical across all six).
    assert len(set(temps)) == 6
    assert len(set(aqis)) == 6
    assert temps == sorted(temps)  # rising fixture -> monotonically increasing


def test_backfill_is_idempotent_per_week() -> None:
    repo = FakeRepository()
    job.backfill(_all_present(), repo, weeks=6, bundle=BUNDLE, cities=CITIES)
    first = dict(repo.docs)
    job.backfill(_all_present(), repo, weeks=6, bundle=BUNDLE, cities=CITIES)

    assert set(repo.docs) == set(first)          # same ids overwritten
    assert len(repo.docs) == 6 * len(CITIES)     # no duplicates


def test_backfill_caps_at_available_weeks() -> None:
    """Requesting more weeks than exist yields one doc per available week (never
    fabricated points)."""
    repo = FakeRepository()
    provider = FakeProvider({"Lahore": _fake_base("Lahore", n_weeks=4, start_week=20)})
    outcomes = job.backfill(provider, repo, weeks=6, bundle=BUNDLE,
                            cities=[{"name": "Lahore"}])

    written = [o for o in outcomes if o.status == "written"]
    assert len(repo.docs) == len(written) <= 4   # at most the 4 real weeks


def test_backfill_reuses_estimate_for_city() -> None:
    """The latest backfilled week equals what estimate_for_city produces for the
    full window at that week's date — i.e. the shared pipeline, not a fork."""
    base = _fake_base("Lahore", n_weeks=8, start_week=12)
    repo = FakeRepository()
    job.backfill(FakeProvider({"Lahore": base}), repo, weeks=1, bundle=BUNDLE,
                 cities=[{"name": "Lahore"}])

    ((doc_id, body),) = repo.docs.items()
    # The single (latest) week id is the Monday of that ISO week.
    iso_year, week = 2026, 12 + 8 - 1
    expected_gen = job._iso_week_start(iso_year, week)
    assert doc_id == job.document_id("Lahore", expected_gen)
    reference = job.estimate_for_city(BUNDLE, "Lahore", base, expected_gen)
    assert body["riskLevel"] == reference.risk_level
    assert body["confidence"] == pytest.approx(reference.confidence)


# --- Real provider construction (no network) --------------------------------


def test_real_provider_constructs_and_builds_window() -> None:
    """The production provider wires up from config without network on construct."""
    provider = job.OpenMeteoWeeklyBaseProvider(
        lookback_weeks=8, get=lambda url, params: None,
    )
    window = provider._recent_window()
    assert window.start < window.end                  # trailing window, not one day
    assert provider._sources and provider._cleaning   # config loaded
