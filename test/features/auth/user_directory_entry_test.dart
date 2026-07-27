import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/auth/domain/models/user_directory_entry.dart';

void main() {
  group('UserStatus JSON', () {
    test('round-trips active and defaults everything else to pending', () {
      expect(UserStatusX.fromJson('active'), UserStatus.active);
      expect(UserStatusX.fromJson('pending'), UserStatus.pending);
      expect(UserStatusX.fromJson('blocked'), UserStatus.pending); // not modelled
      expect(UserStatusX.fromJson(null), UserStatus.pending);
    });
  });

  group('UserDirectoryEntry.fromJson', () {
    test('parses a complete document', () {
      final entry = UserDirectoryEntry.fromJson({
        'name': 'Alice',
        'email': 'alice@example.com',
        'createdAt': '2026-07-01T00:00:00.000Z',
        'status': 'active',
      }, uid: 'u1');

      expect(entry.uid, 'u1');
      expect(entry.name, 'Alice');
      expect(entry.email, 'alice@example.com');
      expect(entry.createdAt, DateTime.utc(2026, 7, 1));
      expect(entry.status, UserStatus.active);
    });

    test('a missing name (Google-only account) parses to null, not a throw', () {
      final entry = UserDirectoryEntry.fromJson({
        'email': 'bob@example.com',
        'createdAt': '2026-07-01T00:00:00.000Z',
        'status': 'pending',
      }, uid: 'u2');

      expect(entry.name, isNull);
    });

    test('a missing/malformed createdAt never throws — degrades to epoch', () {
      final entry = UserDirectoryEntry.fromJson({
        'email': 'carol@example.com',
        'status': 'active',
      }, uid: 'u3');

      expect(entry.createdAt, DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
    });
  });
}
