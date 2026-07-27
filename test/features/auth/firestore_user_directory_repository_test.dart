import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/auth/data/repositories/firestore_user_directory_repository.dart';
import 'package:fyp_foreseeme/features/auth/domain/models/user_directory_entry.dart';

void main() {
  group('FirestoreUserDirectoryRepository', () {
    test('register then list surfaces the new entry as pending', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreUserDirectoryRepository(firestore: firestore);

      await repo.register(uid: 'u1', email: 'alice@example.com', name: 'Alice');
      final entries = await repo.list();

      expect(entries, hasLength(1));
      expect(entries.single.uid, 'u1');
      expect(entries.single.name, 'Alice');
      expect(entries.single.email, 'alice@example.com');
      expect(entries.single.status, UserStatus.pending);
    });

    test('register with no name omits the field rather than storing empty', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreUserDirectoryRepository(firestore: firestore);

      await repo.register(uid: 'u1', email: 'alice@example.com');
      final entries = await repo.list();

      expect(entries.single.name, isNull);
    });

    test('markProfileActive flips status without disturbing name/email', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreUserDirectoryRepository(firestore: firestore);

      await repo.register(uid: 'u1', email: 'alice@example.com', name: 'Alice');
      await repo.markProfileActive('u1');
      final entries = await repo.list();

      expect(entries.single.status, UserStatus.active);
      expect(entries.single.name, 'Alice');
      expect(entries.single.email, 'alice@example.com');
    });

    test('markProfileActive on an unregistered uid still produces a usable entry', () async {
      // Defends the fallback path documented on UserDirectoryEntry.fromJson —
      // a Google-sign-in account that never called register().
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreUserDirectoryRepository(firestore: firestore);

      await repo.markProfileActive('u-google-only');
      final entries = await repo.list();

      expect(entries, hasLength(1));
      expect(entries.single.status, UserStatus.active);
      expect(entries.single.name, isNull);
    });

    test('list returns newest-registered first', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreUserDirectoryRepository(firestore: firestore);

      await firestore.collection('userDirectory').doc('older').set({
        'email': 'older@example.com',
        'createdAt': '2026-07-01T00:00:00.000Z',
        'status': 'active',
      });
      await firestore.collection('userDirectory').doc('newer').set({
        'email': 'newer@example.com',
        'createdAt': '2026-07-10T00:00:00.000Z',
        'status': 'pending',
      });

      final entries = await repo.list();

      expect(entries.map((e) => e.uid), ['newer', 'older']);
    });

    test('returns an empty list when nobody has registered yet', () async {
      final repo = FirestoreUserDirectoryRepository(firestore: FakeFirebaseFirestore());
      expect(await repo.list(), isEmpty);
    });
  });
}
