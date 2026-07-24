# Notification Preferences — schema

Captured in Sprint 3 (Prompt 8); **read and enforced by the backend's FCM
dispatch engine** (`backend/app/jobs/alerting/targeting.py`) since Sprint 4.
Stored on the user's own document alongside `fcmToken`.

## Location

`users/{uid}.notificationPreferences` — a map field. The user owns this document
(Firestore rule: `request.auth.uid == userId`), so only they can read/write it.

## Shape

```jsonc
{
  "notificationPreferences": {
    "highRiskAlerts":   true,    // bool — alert on High risk
    "mediumRiskAlerts": true,    // bool — alert on Medium risk
    "lowRiskUpdates":   false,   // bool — alert on Low risk
    "conditions": {              // map<conditionKey, bool>
      "respiratory":    true,
      "cardiovascular": false
    },
    "schemaVersion": 1           // int — bump on breaking changes
  }
}
```

### Fields

| Field | Type | Default | Meaning |
|---|---|---|---|
| `highRiskAlerts` | bool | `true` | Send when the user's city risk is **High**. |
| `mediumRiskAlerts` | bool | `true` | Send when risk is **Medium**. |
| `lowRiskUpdates` | bool | `false` | Send on **Low** risk (quiet by default). |
| `conditions.<key>` | bool | see below | Per-condition opt-in. Keys: `respiratory` (default `true`), `cardiovascular` (default `false`). |
| `schemaVersion` | int | `1` | Schema version for forward migration. |

Condition keys are defined in
`lib/features/alerts/domain/models/notification_preferences.dart`
(`kNotificationConditionLabels`). A missing or partial document reloads to these
defaults (`NotificationPreferences.fromJson` is defensive).

## How the dispatch engine consumes it

For a generated `riskEstimates` document for the user's city, dispatch only if:

1. the severity toggle for that risk level is **on**
   (`riskLevel == High → highRiskAlerts`, etc.); **and**
2. the disease maps to an **enabled** condition category in `conditions`.

Then send to the user's `fcmToken` (subject to the dispatch engine's 24h
throttle + audit log). See `docs/alert_dispatch_design.md` for the full
targeting predicate (this also requires a risk-band transition upward, not
just a static severity match).
