import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fyp_foreseeme/features/admin/presentation/admin_providers.dart';
import 'package:fyp_foreseeme/features/admin/presentation/admin_read.dart';
import 'package:fyp_foreseeme/features/admin/presentation/admin_activity_log_screen.dart';
import 'package:fyp_foreseeme/features/admin/presentation/activity_log_providers.dart';

void main() {
  testWidgets('bounded reads leave loading when the operation never resolves', (
    tester,
  ) async {
    final pending = Completer<int>();
    final future = boundedAdminRead(
      'test',
      () => pending.future,
      timeout: const Duration(seconds: 1),
    );
    final expectation = expectLater(future, throwsA(isA<TimeoutException>()));
    await tester.pump(const Duration(seconds: 1));
    await expectation;
  });

  testWidgets('permission failure stays visible and retry reloads the log', (
    tester,
  ) async {
    var reads = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isAdminProvider.overrideWith((ref) async => true),
          recentActivityLogProvider.overrideWith((ref) async {
            if (reads++ == 0) {
              throw FirebaseException(
                plugin: 'cloud_firestore',
                code: 'permission-denied',
              );
            }
            return [];
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(body: AdminActivityLogScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Check your administrator session'),
      findsOneWidget,
    );
    expect(
      find.text('No administrative actions have been recorded yet.'),
      findsNothing,
    );
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(
      find.text('No administrative actions have been recorded yet.'),
      findsOneWidget,
    );
    expect(reads, 2);
  });
}
