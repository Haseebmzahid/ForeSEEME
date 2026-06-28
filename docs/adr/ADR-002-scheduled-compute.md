# ADR-002: Scheduled compute via Cloud Scheduler + Cloud Run

## Status: Accepted

## Context

Two core features (batch risk generation, FCM alert dispatch) require scheduled

execution. The architecture had no scheduled-compute component.

## Decision

Run scheduled jobs as Cloud Scheduler → Cloud Run, reusing the existing

Dockerised FastAPI service via a protected batch endpoint. 

## Alternatives considered

- Firebase Scheduled Functions (Node/TS): rejected — introduces a second backend

  language and duplicates model/serialization logic.

## Consequences

+ One backend language (Python), one deployable artifact (the container).

+ Cloud Run free tier is sufficient for FYP scale.

- Requires the batch endpoint to be auth-protected (service-to-service).
