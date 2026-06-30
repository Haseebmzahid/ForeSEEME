"""Cited recommendation lookup tests (Sprint 4, Prompt 2).

Deterministic, total, and never empty/unsourced — the engine selects, never
generates (Rule 11).
"""

from __future__ import annotations

from app.jobs.alerting import recommendation_lookup as rl


def test_known_pairs_resolve_to_expected_entries() -> None:
    assert rl.lookup("respiratory", "Air quality").id == "rec-resp-air"
    assert rl.lookup("respiratory", "Respiratory").id == "rec-resp-seasonal"
    assert rl.lookup("cardiovascular", "Air quality").id == "rec-cardio-air"
    assert rl.lookup("cardiovascular", "Heat").id == "rec-cardio-heat"


def test_unknown_pair_falls_back_to_cited_default() -> None:
    rec = rl.lookup("respiratory", "Heat")  # no exact row
    assert rec.id == "rec-default"
    assert rec.source and rec.source_url.startswith("https://")


def test_every_entry_is_cited_and_routes_help() -> None:
    entries = list(rl._TABLE.values()) + [rl.DEFAULT]
    for rec in entries:
        assert rec.text.strip()
        assert rec.source.strip()
        assert rec.source_url.startswith("https://")
        assert rec.deep_link.startswith("/")
        assert "1122" in rec.escalation  # routes to emergency help
