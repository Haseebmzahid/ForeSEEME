import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/admin/data/repositories/firestore_system_status_repository.dart';
import 'package:fyp_foreseeme/features/admin/domain/models/job_heartbeat.dart';

void main() {
  group('FirestoreSystemStatusRepository.getJobHeartbeats', () {
    test(
      'returns a real heartbeat and a placeholder for a job that never ran',
      () async {
        final firestore = FakeFirebaseFirestore();
        await firestore.collection('jobHeartbeats').doc('compute_risk').set({
          'job': 'compute_risk',
          'status': 'ok',
          'ok': true,
          'startedAt': Timestamp.fromDate(DateTime.utc(2026, 7, 20, 0, 0)),
          'finishedAt': Timestamp.fromDate(DateTime.utc(2026, 7, 20, 0, 1)),
          'durationMs': 60000,
          'total': 5,
          'counts': {'written': 5},
          'error': null,
        });
        final repo = FirestoreSystemStatusRepository(firestore: firestore);

        final heartbeats = await repo.getJobHeartbeats([
          'compute_risk',
          'dispatch_alerts',
        ]);

        expect(heartbeats, hasLength(2));
        expect(heartbeats[0].job, 'compute_risk');
        expect(heartbeats[0].status, JobRunStatus.ok);
        expect(heartbeats[0].total, 5);
        expect(
          heartbeats[0].healthAt(DateTime.utc(2026, 7, 23)),
          JobRunStatus.degraded,
        );
        expect(
          heartbeats[0].healthAt(DateTime.utc(2026, 7, 20, 0, 2)),
          JobRunStatus.ok,
        );
        expect(heartbeats[0].counts, {'written': 5});
        expect(heartbeats[0].finishedAt, DateTime.utc(2026, 7, 20, 0, 1));
        // Never-run job: a placeholder, not an omission — the dashboard must be
        // able to show every monitored job, including "never run yet".
        expect(heartbeats[1].job, 'dispatch_alerts');
        expect(heartbeats[1].status, JobRunStatus.unknown);
      },
    );

    test('classifies a failed run without showing raw error data', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('jobHeartbeats').doc('compute_risk').set({
        'job': 'compute_risk',
        'status': 'failed',
        'ok': false,
        'startedAt': Timestamp.fromDate(DateTime.utc(2026, 7, 20)),
        'finishedAt': Timestamp.fromDate(DateTime.utc(2026, 7, 20)),
        'durationMs': 210,
        'total': 0,
        'counts': {'error': 5},
        'error': 'RuntimeError: fetch failed',
      });
      final repo = FirestoreSystemStatusRepository(firestore: firestore);

      final heartbeats = await repo.getJobHeartbeats(['compute_risk']);

      expect(heartbeats.single.status, JobRunStatus.failed);
      expect(heartbeats.single.error, 'Job execution failed');
    });
  });

  group('FirestoreSystemStatusRepository.getAlertVolume', () {
    test('reads the published aggregate dispatch count', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('operationalMetrics').doc('alerts').set({
        'totalAlerts': 3,
      });
      final repo = FirestoreSystemStatusRepository(firestore: firestore);

      expect(await repo.getAlertVolume(), 3);
    });

    test('returns unavailable when aggregation has never run', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreSystemStatusRepository(firestore: firestore);

      expect(await repo.getAlertVolume(), isNull);
    });
  });

  group('FirestoreSystemStatusRepository.getLatestModelStatus', () {
    test('returns the most recent estimate across all cities', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('riskEstimates').doc('Lahore_2026-07-01').set({
        'city': 'Lahore',
        'modelVersion': 'rf-1.0.0',
        'generatedAt': Timestamp.fromDate(DateTime.utc(2026, 7, 1)),
      });
      await firestore
          .collection('riskEstimates')
          .doc('Karachi_2026-07-10')
          .set({
            'city': 'Karachi',
            'modelVersion': 'rf-1.1.0',
            'generatedAt': Timestamp.fromDate(DateTime.utc(2026, 7, 10)),
          });
      final repo = FirestoreSystemStatusRepository(firestore: firestore);

      final status = await repo.getLatestModelStatus();

      expect(status, isNotNull);
      expect(status!.version, 'rf-1.1.0');
      expect(status.generatedAt, DateTime.utc(2026, 7, 10));
    });

    test('returns null when no estimate has ever been written', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreSystemStatusRepository(firestore: firestore);

      expect(await repo.getLatestModelStatus(), isNull);
    });
  });
}
