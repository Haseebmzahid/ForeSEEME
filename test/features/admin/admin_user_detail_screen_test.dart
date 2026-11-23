import 'package:flutter/material.dart';
import 'package:fyp_foreseeme/features/admin/data/repositories/admin_api_client.dart';
import 'fake_admin_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fyp_foreseeme/features/admin/presentation/admin_providers.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/admin/presentation/admin_user_detail_screen.dart';
import 'package:fyp_foreseeme/features/auth/domain/models/user_directory_entry.dart';

void main() {
  testWidgets('renders minimal details and offers account controls', (
    tester,
  ) async {
    final entry = UserDirectoryEntry(
      uid: 'u1',
      name: 'Alice Khan',
      email: 'alice@example.com',
      createdAt: DateTime.now().toUtc().subtract(const Duration(days: 3)),
      status: UserStatus.active,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [isAdminProvider.overrideWith((ref) async => true)],
        child: MaterialApp(home: AdminUserDetailScreen(entry: entry)),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Alice Khan'), findsOneWidget);
    expect(find.text('alice@example.com'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('u1'), findsOneWidget);
    expect(find.text('Suspend account'), findsOneWidget);
    expect(find.text('Delete account'), findsOneWidget);
    expect(find.textContaining('Medication'), findsNothing);
  });

  testWidgets('a missing name renders an em dash, not a crash', (tester) async {
    final entry = UserDirectoryEntry(
      uid: 'u2',
      name: null,
      email: 'bob@example.com',
      createdAt: DateTime.now().toUtc(),
      status: UserStatus.pending,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [isAdminProvider.overrideWith((ref) async => true)],
        child: MaterialApp(home: AdminUserDetailScreen(entry: entry)),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('deletion sends the retention choice only after confirmation', (
    tester,
  ) async {
    final api = FakeAdminApi()
      ..failure = const AdminApiException('operation_unconfirmed');
    final entry = UserDirectoryEntry(
      uid: 'u3',
      email: 'example@example.org',
      createdAt: DateTime.utc(2026),
      status: UserStatus.blocked,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isAdminProvider.overrideWith((ref) async => true),
          adminApiClientProvider.overrideWithValue(api),
        ],
        child: MaterialApp(home: AdminUserDetailScreen(entry: entry)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reactivate account'), findsOneWidget);
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    expect(api.calls, isEmpty);
    expect(
      find.textContaining(
        'Firestore records and subcollections will be retained',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    final (path, body) = api.calls.single;
    expect(path, ['users', 'u3']);
    expect(body, {
      'action': 'delete',
      'confirmUid': 'u3',
      'retention': 'retain_firestore',
    });
    expect(
      find.textContaining('outcome could not be confirmed'),
      findsOneWidget,
    );
  });
}
