# Risk Data Schema (`riskEstimates`)

**Status**: 🔒 Frozen contract (Sprint 1) — shape only, no logic.

This document is the single source of truth for the **risk-data contract**. The
same shape is implemented by three artifacts, which MUST stay in sync:

| Artifact | Location |
|----------|----------|
| Pydantic response model (`RiskEstimateResponse`) | `backend/app/schemas.py` |
| Pydantic request model (`PredictRequest`) | `backend/app/schemas.py` |
| Dart model (`RiskEstimateModel`) | `lib/features/risk/domain/models/risk_estimate_model.dart` |
| Firestore document | `riskEstimates/{docId}` |

> **Architecture note (ADR-001).** The Flutter app reads risk data **only** from
> the Firestore `riskEstimates` collection. It MUST NEVER call the FastAPI
> `/predict` endpoint directly — `/predict` is internal to the backend batch job.
>
> **Model placement note.** The Dart model lives in `risk/domain/models/` (not
> `risk/data/models/`) to mirror the existing `medication` and `auth` features,
> where all immutable models live under `domain/models/`. This satisfies
> GOLDEN_RULE #8 (mirror existing structure) and CLAUDE.md's priority order
> (existing architecture outranks prompt-suggested paths). The model is
> framework-free: it imports neither `package:flutter` nor `cloud_firestore`.

---

## Firestore document: `riskEstimates/{docId}`

### Document ID convention

```
{city}_{YYYY-MM-DD}
```

- `city` — the city name (e.g. `Lahore`).
- `YYYY-MM-DD` — the **UTC** calendar date of `generatedAt`.

Example: an estimate for Lahore generated on 2026-06-28 (UTC) →
`riskEstimates/Lahore_2026-06-28`.

This composite ID makes each `(city, day)` estimate idempotent: re-running the
batch job for the same city and day overwrites the same document instead of
creating duplicates. In Dart this ID is exposed by `RiskEstimateModel.docId`.

### Document fields

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `city` | string | Yes | City the estimate was computed for |
| `riskLevel` | string enum | Yes | One of `"Low"` \| `"Medium"` \| `"High"` |
| `disease` | string | Yes | Disease the estimate refers to (e.g. `"Dengue"`) |
| `confidence` | float | Yes | Model confidence, in `[0.0, 1.0]` |
| `temperature` | float | Yes | Temperature feature (°C); must be `<= 80` |
| `humidity` | float | Yes | Relative humidity feature (%) |
| `aqi` | float | Yes | Air-quality-index feature; must be `>= 0` |
| `generatedAt` | string (ISO-8601, UTC) | Yes | When the estimate was generated, e.g. `"2026-06-28T00:00:00.000Z"` |
| `modelVersion` | string | Yes | Version of the model that produced the estimate |
| `lowConfidence` | bool | No | `true` when `confidence` is below the reliability threshold. Defaults to `false` |

#### Example document

```json
{
  "city": "Lahore",
  "riskLevel": "High",
  "disease": "Dengue",
  "confidence": 0.87,
  "temperature": 34.5,
  "humidity": 62.0,
  "aqi": 180.0,
  "generatedAt": "2026-06-28T00:00:00.000Z",
  "modelVersion": "rf-v1.2",
  "lowConfidence": false
}
```

### Write rule

**Service-account writes only.** The `riskEstimates` collection is written
exclusively by the scheduled backend batch job (Cloud Scheduler → Cloud Run, per
ADR-002) using the Firebase Admin SDK / a service account. The Flutter client has
**read-only** access; client writes MUST be denied by Firestore security rules.

---

## Internal request: `POST /predict`

> Internal to the backend only (ADR-001). Never called by the Flutter client.

### Request fields

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `city` | string | Yes | City to predict for |
| `temperature` | float | Yes | Temperature feature (°C); must be `<= 80` |
| `humidity` | float | Yes | Relative humidity feature (%) |
| `rainfall` | float | Yes | Rainfall feature (mm) |
| `aqi` | float | Yes | Air-quality-index feature; must be `>= 0` |
| `weekOfYear` | int | Yes | ISO week number, in `[1, 53]` |

### Validation → HTTP 422

The Pydantic v2 models reject:

- `aqi < 0`
- `temperature > 80`
- `confidence` outside `[0.0, 1.0]` (response only)
- `weekOfYear` outside `[1, 53]` (request only)

When these models are bound to the future FastAPI route, a Pydantic
`ValidationError` is surfaced automatically as an HTTP **422 Unprocessable
Entity** response.
