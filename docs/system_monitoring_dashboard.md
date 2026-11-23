# System monitoring dashboard

The dashboard reads independent metrics through Riverpod. Admin reads have a 12-second deadline, use server data, distinguish permission and connectivity failures, and expose retry. Pull down to refresh all metrics. A missing document produces an explicit unavailable state.

| Display | Firestore source | Interpretation |
|---|---|---|
| Registered and active users | `operationalMetrics/accounts` | Unique Firebase Auth UIDs, including disabled accounts in the registered count. Active means the account is enabled and signed in or refreshed its ID token during the configured window, 30 days by default. These are authentication events, so background token refresh may qualify. |
| Alerts dispatched | `operationalMetrics/alerts` | Count of retained dispatch entries with `status == "sent"`. Skips, failures and outstanding claims are omitted. This measures FCM acceptance. Enabling TTL on the ledger would change the count to a retention-window total. |
| Deployed model | `operationalMetrics/deployedModel` | Version from the verified digest-pinned compute deployment. Publish the record at deployment and rollback. |
| Latest successful batch model | `jobHeartbeats/compute_risk.lastSuccessfulModelVersion` | Batch artifact version recorded only for a healthy full run. |
| Latest estimate | `riskEstimates` ordered by `generatedAt` | Most recent written estimate and its version, including estimates from partial batches or a backfill. |
| Jobs | `jobHeartbeats/{compute_risk,dispatch_alerts,weekly_report}` | Latest outcome, start and finish, duration, counts, last success and a fixed failure label. |

Compute and dispatch heartbeats become stale after 36 hours. Weekly report becomes stale after eight days. Overall status is failed if a job failed, degraded for degraded or stale jobs or a deployed/successful model mismatch, and unknown when job or model evidence is missing. It only shows healthy with current healthy job evidence and matching model evidence. This is operational telemetry for the monitored pipeline.

The account document stores `totalUsers`, `activeUsers`, `measurementWindowDays`, `generatedAt`, `source`, `aggregationStatus` and `lastAttemptAt`. Alerts use `totalAlerts` and the equivalent provenance fields. Aggregation failures preserve the prior snapshot and mark its status failed. The app displays the failure for that metric. The aggregation writes no identity or health information. The dispatch ledger is private to backend identities.

See [deployment and verification](MODULE_8_FINALIZATION.md) for the scheduled job entry points.
