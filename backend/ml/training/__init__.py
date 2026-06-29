"""Training-time code for the ForeSeeMe Random Forest (Sprint 2, Phase C).

This package owns model training, tuning, and evaluation. It reads the frozen
``train.parquet`` (Prompt 10) and writes artifacts under ``ml/artifacts/``.
Serving-time model loading stays in ``backend/app/`` (Sprint 1) — the two are
kept separate by design (see docs/SPRINT_2.md, "Target ML structure").
"""
