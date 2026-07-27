import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/features/admin/presentation/admin_providers.dart';
import 'package:fyp_foreseeme/features/admin/presentation/admin_users_providers.dart';
import 'package:fyp_foreseeme/features/admin/presentation/admin_users_screen.dart';
import 'package:fyp_foreseeme/features/auth/domain/models/user_directory_entry.dart';

final _alice = UserDirectoryEntry(
  uid: 'u1',
  name: 'Alice Khan',
  email: 'alice@example.com',
  createdAt: DateTime.utc(2026, 7, 1),
  status: UserStatus.active,
);
final _bob = UserDirectoryEntry(
  uid: 'u2',
  name: null,
  email: 'bob@example.com',
  createdAt: DateTime.utc(2026, 7, 10),
  status: UserStatus.pending,
);

GoRouter _buildRouter() {
  return GoRouter(
    initialLocation: '/admin/users',
    routes: [
      GoRoute(
        path: '/admin/users',
        builder: (context, state) => const Scaffold(body: AdminUsersScreen()),
        routes: [
          GoRoute(
            path: 'detail',
            builder: (context, state) =>
                const Scaffold(body: Text('Detail Screen')),
          ),
        ],
      ),
    ],
  );
}

// `flutter_riverpod` 3.3.1 does not export the `Override` type — see
// test/features/resources/resource_center_test.dart.
Future<void> _pump(WidgetTester tester, List<dynamic> overrides) async {
  // A tall viewport so the whole (lazily-built) list renders for assertions —
  // mirrors resource_center_test.dart's pumpCenter.
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [...overrides],
      child: MaterialApp.router(routerConfig: _buildRouter()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a non-admin sees the shared not-authorized view, not the list', (
    tester,
  ) async {
    await _pump(tester, [isAdminProvider.overrideWith((ref) async => false)]);

    expect(find.text('Not authorized'), findsOneWidget);
  });

  testWidgets('an admin sees an honest empty state before anyone registers', (
    tester,
  ) async {
    await _pump(tester, [
      isAdminProvider.overrideWith((ref) async => true),
      userDirectoryListProvider.overrideWith((ref) async => const []),
    ]);

    expect(find.text('No registered users yet'), findsOneWidget);
  });

  testWidgets('an admin sees both users with name/email and status', (
    tester,
  ) async {
    await _pump(tester, [
      isAdminProvider.overrideWith((ref) async => true),
      userDirectoryListProvider.overrideWith((ref) async => [_alice, _bob]),
    ]);

    expect(find.text('Alice Khan'), findsOneWidget);
    expect(find.text('alice@example.com'), findsOneWidget);
    // 'Active'/'Pending' each appear twice: once as a filter chip label, once
    // as the matching user's status pill.
    expect(find.text('Active'), findsNWidgets(2));
    // Bob has no name — falls back to showing the email as the title too.
    expect(find.text('bob@example.com'), findsWidgets);
    expect(find.text('Pending'), findsNWidgets(2));

    // Honest scope: no suspend/block/delete controls in-app.
    expect(find.textContaining('operator actions'), findsOneWidget);
  });

  testWidgets('search filters by name or email', (tester) async {
    await _pump(tester, [
      isAdminProvider.overrideWith((ref) async => true),
      userDirectoryListProvider.overrideWith((ref) async => [_alice, _bob]),
    ]);

    await tester.enterText(find.byType(TextField), 'alice');
    await tester.pumpAndSettle();

    expect(find.text('Alice Khan'), findsOneWidget);
    expect(find.text('bob@example.com'), findsNothing);
  });

  testWidgets('a search with no matches shows the filtered-empty state, distinct from true-empty', (
    tester,
  ) async {
    await _pump(tester, [
      isAdminProvider.overrideWith((ref) async => true),
      userDirectoryListProvider.overrideWith((ref) async => [_alice, _bob]),
    ]);

    await tester.enterText(find.byType(TextField), 'nobody-matches-this');
    await tester.pumpAndSettle();

    expect(find.text('No matching users'), findsOneWidget);
    expect(find.text('No registered users yet'), findsNothing);
  });

  testWidgets('status filter shows only users in that status', (tester) async {
    await _pump(tester, [
      isAdminProvider.overrideWith((ref) async => true),
      userDirectoryListProvider.overrideWith((ref) async => [_alice, _bob]),
    ]);

    // Two "Pending" texts exist (the filter chip + Bob's status pill) — the
    // chip has a dedicated key so the tap is unambiguous.
    await tester.tap(find.byKey(const Key('status-filter-pending')));
    await tester.pumpAndSettle();

    expect(find.text('bob@example.com'), findsWidgets);
    expect(find.text('Alice Khan'), findsNothing);
  });

  testWidgets('tapping a user navigates to the detail route with it as extra', (
    tester,
  ) async {
    await _pump(tester, [
      isAdminProvider.overrideWith((ref) async => true),
      userDirectoryListProvider.overrideWith((ref) async => [_alice, _bob]),
    ]);

    await tester.tap(find.text('Alice Khan'));
    await tester.pumpAndSettle();

    expect(find.text('Detail Screen'), findsOneWidget);
  });
}
