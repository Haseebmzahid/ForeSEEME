import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/admin/domain/models/admin_activity_log_entry.dart';
import 'package:fyp_foreseeme/features/admin/presentation/activity_log_providers.dart';
import 'package:fyp_foreseeme/features/admin/presentation/admin_activity_log_screen.dart';
import 'package:fyp_foreseeme/features/admin/presentation/admin_providers.dart';

const _host = MaterialApp(home: Scaffold(body: AdminActivityLogScreen()));

void main() {
  testWidgets('a non-admin sees the shared not-authorized view, not the log', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [isAdminProvider.overrideWith((ref) async => false)],
        child: _host,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Not authorized'), findsOneWidget);
  });

  testWidgets(
    'an admin sees an honest empty state before any action is logged',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isAdminProvider.overrideWith((ref) async => true),
            recentActivityLogProvider.overrideWith((ref) async => const []),
          ],
          child: _host,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('No administrative actions have been recorded yet.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'an admin sees logged entries, newest first, with author + summary',
    (tester) async {
      final entries = [
        AdminActivityLogEntry(
          id: '2',
          action: 'override_clear',
          target: 'Lahore',
          summary: 'Cleared override for Lahore',
          authorUid: 'op-1',
          authorEmail: 'op@example.com',
          createdAt: DateTime.now().toUtc(),
        ),
        AdminActivityLogEntry(
          id: '1',
          action: 'override_set',
          target: 'Lahore',
          summary: 'Set Lahore risk to High (Smog)',
          authorUid: 'op-1',
          authorEmail: 'op@example.com',
          createdAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isAdminProvider.overrideWith((ref) async => true),
            recentActivityLogProvider.overrideWith((ref) async => entries),
          ],
          child: _host,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cleared override for Lahore'), findsOneWidget);
      expect(find.text('Set Lahore risk to High (Smog)'), findsOneWidget);
      expect(find.textContaining('op@example.com'), findsNWidgets(2));

      // Newest first: the clear (index 0) precedes the set (index 1) on screen.
      final clearY = tester
          .getTopLeft(find.text('Cleared override for Lahore'))
          .dy;
      final setY = tester
          .getTopLeft(find.text('Set Lahore risk to High (Smog)'))
          .dy;
      expect(clearY, lessThan(setY));
    },
  );
}
