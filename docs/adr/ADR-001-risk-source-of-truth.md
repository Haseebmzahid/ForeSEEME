# ADR-001: Firestore is the single source of truth for risk data

## Status: Accepted

## Context

Two data paths for risk existed in the design: (a) the app calling FastAPI

`/predict` live, and (b) the app reading a `riskEstimates` collection in

Firestore written by the backend. Maintaining both creates ambiguity and rework.

## Decision

A scheduled backend job computes risk per city and writes `riskEstimates` to

Firestore. The Flutter app reads ONLY from Firestore. `/predict` is internal to

the backend (used by the batch job), never called by the client.

## Consequences

+ Preserves the "client never calls external APIs directly" invariant.

+ App is decoupled from ML-service uptime; works offline from cache.

+ The FCM dispatch job (Sprint 5) reads the same collection — no new path.

- Risk is as fresh as the schedule (acceptable: weekly/daily cadence by design).
