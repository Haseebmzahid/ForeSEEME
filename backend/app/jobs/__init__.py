"""Scheduled backend jobs (Sprint 2, Prompt 15).

Container-friendly, standalone entrypoints run on a schedule (Cloud Scheduler →
Cloud Run, ADR-002). The risk-compute job is the *sole writer* of the Firestore
``riskEstimates`` collection (ADR-001); the Flutter app only reads it.
"""
