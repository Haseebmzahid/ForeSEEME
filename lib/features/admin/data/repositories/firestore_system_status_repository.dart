import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/job_heartbeat.dart';
import '../../domain/models/model_status.dart';
import '../../domain/models/operational_metrics.dart';
import '../../domain/repositories/system_status_repository.dart';

/// Firestore implementation of [SystemStatusRepository].
///
class FirestoreSystemStatusRepository implements SystemStatusRepository {
  final FirebaseFirestore _firestore;

  FirestoreSystemStatusRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  static const String heartbeatsCollectionPath = 'jobHeartbeats';
  static const _server = GetOptions(source: Source.server);
  static const String riskEstimatesCollectionPath = 'riskEstimates';

  @override
  Future<List<JobHeartbeat>> getJobHeartbeats(List<String> jobIds) async {
    return Future.wait(
      jobIds.map((job) async {
        try {
          final snapshot = await _firestore
              .collection(heartbeatsCollectionPath)
              .doc(job)
              .get(_server)
              .timeout(const Duration(seconds: 10));
          return _heartbeatFromSnapshot(job, snapshot.data());
        } catch (error) {
          final code = error is FirebaseException
              ? error.code
              : error.runtimeType.toString();
          developer.log(
            'Heartbeat read failed ($code)',
            name: 'foreseeme.admin',
          );
          return JobHeartbeat.none(job, readError: error);
        }
      }),
    );
  }

  Future<Map<String, dynamic>?> _metric(String id) async {
    final data =
        (await _firestore.collection('operationalMetrics').doc(id).get(_server))
            .data();
    if (data?['aggregationStatus'] == 'failed') {
      throw StateError('Latest aggregation failed');
    }
    return data;
  }

  @override
  Future<int?> getAlertVolume() async {
    final data = await _metric('alerts');
    return data == null ? null : data['totalAlerts'] as int;
  }

  @override
  Future<AccountMetrics?> getAccountMetrics() async {
    final data = await _metric('accounts');
    if (data == null) return null;
    return AccountMetrics(
      totalUsers: data['totalUsers'] as int,
      activeUsers: data['activeUsers'] as int,
      windowDays: data['measurementWindowDays'] as int,
      generatedAt: (data['generatedAt'] as Timestamp).toDate(),
    );
  }

  @override
  Future<ModelStatus?> getDeployedModel() async {
    final data = await _metric('deployedModel');
    if (data == null) return null;
    return ModelStatus(
      version: data['version'] as String,
      generatedAt: (data['verifiedAt'] as Timestamp).toDate(),
    );
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
        .get(_server);

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
    final normalised = {...data, 'job': job};
    for (final key in const ['startedAt', 'finishedAt', 'lastSuccessfulAt']) {
      final value = normalised[key];
      if (value is Timestamp) {
        normalised[key] = value.toDate().toUtc().toIso8601String();
      }
    }
    return JobHeartbeat.fromJson(normalised);
  }
}
