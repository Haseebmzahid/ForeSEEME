/// The scheduled backend jobs the System Monitoring Dashboard watches
/// (Sprint M8.1). Kept in sync with the job names `app/jobs/observability.py`
/// writes heartbeats under (`jobHeartbeats/{job}`) — see docs/observability.md.
const List<String> kMonitoredJobs = [
  'compute_risk',
  'dispatch_alerts',
  'weekly_report',
];
