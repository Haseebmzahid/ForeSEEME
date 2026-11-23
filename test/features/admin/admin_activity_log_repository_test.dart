import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/admin/data/repositories/firestore_admin_activity_log_repository.dart';
import 'package:fyp_foreseeme/features/admin/domain/models/admin_activity_log_entry.dart';

AdminActivityLogEntry _entry({
  String action = 'override_set',
  String target = 'Lahore',
  DateTime? createdAt,
}) => AdminActivityLogEntry(
  action: action,
  target: target,
  summary: 'Set $target risk to High (Smog)',
  authorUid: 'op-1',
  authorEmail: 'op@example.com',
  createdAt: createdAt ?? DateTime.now().toUtc(),
);

Future<void> _seed(
  FakeFirebaseFirestore firestore,
  AdminActivityLogEntry entry,
) async {
  await firestore.collection('adminActivityLog').add(entry.toJson());
}

void main() {
  group('FirestoreAdminActivityLogRepository', () {
    test('reads an entry written by the backend', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreAdminActivityLogRepository(firestore: firestore);

      await _seed(firestore, _entry());
      final entries = await repo.recent();

      expect(entries, hasLength(1));
      expect(entries.single.id, isNotNull);
      expect(entries.single.action, 'override_set');
      expect(entries.single.target, 'Lahore');
      expect(entries.single.authorEmail, 'op@example.com');
    });

    test('recent returns newest first', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreAdminActivityLogRepository(firestore: firestore);

      await _seed(
        firestore,
        _entry(target: 'Karachi', createdAt: DateTime.utc(2026, 7, 1)),
      );
      await _seed(
        firestore,
        _entry(target: 'Lahore', createdAt: DateTime.utc(2026, 7, 10)),
      );

      final entries = await repo.recent();

      expect(entries.map((e) => e.target), ['Lahore', 'Karachi']);
    });

    test('recent respects the limit', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreAdminActivityLogRepository(firestore: firestore);

      for (var i = 0; i < 5; i++) {
        await _seed(
          firestore,
          _entry(target: 'City$i', createdAt: DateTime.utc(2026, 7, i + 1)),
        );
      }

      final entries = await repo.recent(limit: 2);

      expect(entries, hasLength(2));
      expect(entries.first.target, 'City4');
    });

    test('returns an empty list when nothing has been logged yet', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreAdminActivityLogRepository(firestore: firestore);

      expect(await repo.recent(), isEmpty);
    });

    test('normalises a stored Timestamp back to UTC DateTime', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('adminActivityLog').add({
        'action': 'override_clear',
        'target': 'Peshawar',
        'summary': 'Cleared override for Peshawar',
        'authorUid': 'op-1',
        'authorEmail': 'op@example.com',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 7, 15)),
      });
      final repo = FirestoreAdminActivityLogRepository(firestore: firestore);

      final entries = await repo.recent();

      expect(entries.single.createdAt, DateTime.utc(2026, 7, 15));
    });
  });
}
