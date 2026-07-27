import '../models/job_heartbeat.dart';
import '../models/model_status.dart';

/// Read-only operator telemetry for the System Monitoring Dashboard
/// (Sprint M8.1, SDS FR8.1).
///
/// Mirrors [RiskRepository]/[RiskOverrideRepository]: a pure data interface, no
/// business logic. Every read here is gated server-side by the `admin` custom
/// claim (`firestore.rules`) — a non-admin caller is denied by the rules, not by
/// this interface, matching the existing admin-override pattern.
abstract class SystemStatusRepository {
  /// The latest heartbeat for each of [jobIds], in the same order. A job with no
  /// heartbeat document yet (never run) is represented by [JobHeartbeat.none]
  /// rather than being omitted, so the dashboard can show every monitored job.
  Future<List<JobHeartbeat>> getJobHeartbeats(List<String> jobIds);

  /// Total number of dispatch attempts ever logged to `alertDispatchLog`
  /// (SDS FR8.1 "alerts count") — an exact count, not an estimate.
  Future<int> getAlertVolume();

  /// The model version + timestamp of the most recently written risk estimate
  /// across all cities, or `null` if no estimate has ever been written.
  Future<ModelStatus?> getLatestModelStatus();
}
