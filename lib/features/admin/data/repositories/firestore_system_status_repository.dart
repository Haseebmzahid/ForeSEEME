import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/job_heartbeat.dart';
import '../../domain/models/model_status.dart';
import '../../domain/repositories/system_status_repository.dart';

/// Firestore implementation of [SystemStatusRepository].
///
/// Reads three collections, all admin-read-gated by `firestore.rules`
/// (Sprint M8.1): `jobHeartbeats` and `alertDispatchLog` (previously fully
/// service-account-only; the rules were deliberately widened for this
/// dashboard — see firestore.rules and test_rules/firestore_rules.test.mjs),
/// and `riskEstimates` (already authenticated-read, unchanged).
class FirestoreSystemStatusRepository implements SystemStatusRepository {
  final FirebaseFirestore _firestore;

  FirestoreSystemStatusRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  static const String heartbeatsCollectionPath = 'jobHeartbeats';
  static const String alertLogCollectionPath = 'alertDispatchLog';
  static const String riskEstimatesCollectionPath = 'riskEstimates';

  @override
  Future<List<JobHeartbeat>> getJobHeartbeats(List<String> jobIds) async {
    // One get() per job id (bounded, small — mirrors
    // FirestoreRiskRepository.getLatestRiskAllCities' per-key read shape).
    final snapshots = await Future.wait(
      jobIds.map(
        (job) => _firestore.collection(heartbeatsCollectionPath).doc(job).get(),
      ),
    );

    return [
      for (var i = 0; i < jobIds.length; i++)
        _heartbeatFromSnapshot(jobIds[i], snapshots[i].data()),
    ];
  }

  @override
  Future<int> getAlertVolume() async {
    // An exact aggregation count, not a client-side fetch-and-length — the log
    // grows unbounded over the app's lifetime, so this avoids ever transferring
    // its documents just to total them.
    final aggregate = await _firestore
        .collection(alertLogCollectionPath)
        .count()
        .get();
    return aggregate.count ?? 0;
  }

  @override
  Future<ModelStatus?> getLatestModelStatus() async {
    // No `where` clause — the latest estimate across ALL cities, so this needs
    // only the automatic single-field index on `generatedAt` (unlike the
    // per-city reads in FirestoreRiskRepository, which filter by `city` too).
    final snapshot = await _firestore
        .collection(riskEstimatesCollectionPath)
        .orderBy('generatedAt', descending: true)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;
    final data = snapshot.docs.first.data();
    final version = (data['modelVersion'] as String?) ?? '';
    final rawGeneratedAt = data['generatedAt'];
    final generatedAt = rawGeneratedAt is Timestamp
        ? rawGeneratedAt.toDate().toUtc()
        : DateTime.parse(rawGeneratedAt as String).toUtc();
    return ModelStatus(version: version, generatedAt: generatedAt);
  }

  /// Maps a raw heartbeat document body to a [JobHeartbeat], tolerating a
  /// [Timestamp] for the date fields (the backend writes native Firestore
  /// timestamps, not ISO-8601 strings, for `startedAt`/`finishedAt`) and a
  /// missing document (a job that has never run) via [JobHeartbeat.none].
  static JobHeartbeat _heartbeatFromSnapshot(
    String job,
    Map<String, dynamic>? data,
  ) {
    if (data == null) return JobHeartbeat.none(job);
    final normalised = Map<String, dynamic>.from(data);
    for (final key in const ['startedAt', 'finishedAt']) {
      final value = normalised[key];
      if (value is Timestamp) {
        normalised[key] = value.toDate().toUtc().toIso8601String();
      }
    }
    return JobHeartbeat.fromJson(normalised);
  }
}
