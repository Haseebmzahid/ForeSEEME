// Pure-Dart model for a scheduled job's operator heartbeat (Sprint M8.1).
//
// Framework-free: imports NO `package:flutter` and NO `cloud_firestore`, mirroring
// [RiskEstimateModel]/[RiskOverride]. Read-only — the app never writes this
// document; it is produced by `backend/app/jobs/observability.py` on every
// scheduled run of `compute_risk` / `dispatch_alerts` / `weekly_report` and
// overwritten each time (see docs/observability.md). Firestore normalises
// `Timestamp` fields to ISO-8601 strings before [fromJson] is called, matching
// the [FirestoreRiskRepository.modelFromSnapshotData] convention.

/// Run health for a scheduled job, in increasing severity — mirrors the
/// backend's `STATUS_OK` / `STATUS_DEGRADED` / `STATUS_FAILED` constants.
enum JobRunStatus {
  ok,
  degraded,
  failed,
  /// No heartbeat has ever been written, or the stored value is unrecognised —
  /// distinct from [failed] so the dashboard can say "never run" rather than
  /// implying a run happened and failed.
  unknown;

  String get label => switch (this) {
    JobRunStatus.ok => 'Healthy',
    JobRunStatus.degraded => 'Degraded',
    JobRunStatus.failed => 'Failed',
    JobRunStatus.unknown => 'No data yet',
  };
}

extension JobRunStatusX on JobRunStatus {
  static JobRunStatus fromJson(String? value) => switch (value) {
    'ok' => JobRunStatus.ok,
    'degraded' => JobRunStatus.degraded,
    'failed' => JobRunStatus.failed,
    _ => JobRunStatus.unknown,
  };
}

/// One job's latest heartbeat (`jobHeartbeats/{job}`), admin-read-only.
class JobHeartbeat {
  /// The job name — the Firestore document id, e.g. `"compute_risk"`.
  final String job;

  /// Graded health of the most recent run.
  final JobRunStatus status;

  /// When that run started/finished (UTC).
  final DateTime startedAt;
  final DateTime finishedAt;

  /// How long the run took.
  final int durationMs;

  /// Total outcomes the run produced (sum of [counts]).
  final int total;

  /// Per-status tally of the run's outcomes (e.g. `{"written": 5}`).
  final Map<String, int> counts;

  /// `"TypeName: message"` on a crash; `null` otherwise. Never a secret
  /// (GOLDEN_RULES §7) — the backend only ever writes a type/message string.
  final String? error;

  const JobHeartbeat({
    required this.job,
    required this.status,
    required this.startedAt,
    required this.finishedAt,
    required this.durationMs,
    required this.total,
    required this.counts,
    this.error,
  });

  /// A placeholder for a job with no heartbeat document yet (e.g. it has never
  /// run). Callers distinguish this from real data via [status] ==
  /// [JobRunStatus.unknown]; [startedAt]/[finishedAt] are not meaningful.
  factory JobHeartbeat.none(String job) => JobHeartbeat(
    job: job,
    status: JobRunStatus.unknown,
    startedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    finishedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    durationMs: 0,
    total: 0,
    counts: const {},
  );

  factory JobHeartbeat.fromJson(Map<String, dynamic> json) {
    return JobHeartbeat(
      job: (json['job'] as String?) ?? '',
      status: JobRunStatusX.fromJson(json['status'] as String?),
      startedAt: DateTime.parse(json['startedAt'] as String).toUtc(),
      finishedAt: DateTime.parse(json['finishedAt'] as String).toUtc(),
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt() ?? 0,
      counts: (json['counts'] as Map<String, dynamic>?)?.map(
            (key, value) => MapEntry(key, (value as num).toInt()),
          ) ??
          const {},
      error: json['error'] as String?,
    );
  }

  @override
  String toString() =>
      'JobHeartbeat(job: $job, status: ${status.name}, finishedAt: '
      '${finishedAt.toUtc().toIso8601String()})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JobHeartbeat &&
          other.job == job &&
          other.status == status &&
          other.startedAt == startedAt &&
          other.finishedAt == finishedAt &&
          other.durationMs == durationMs &&
          other.total == total &&
          other.error == error;

  @override
  int get hashCode =>
      Object.hash(job, status, startedAt, finishedAt, durationMs, total, error);
}
