import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/admin/domain/models/job_heartbeat.dart';
import 'package:fyp_foreseeme/features/admin/domain/models/model_status.dart';
import 'package:fyp_foreseeme/features/admin/presentation/admin_dashboard_screen.dart';
import 'package:fyp_foreseeme/features/admin/presentation/admin_providers.dart';
import 'package:fyp_foreseeme/features/admin/presentation/system_status_providers.dart';

const _host = MaterialApp(
  home: Scaffold(body: AdminDashboardScreen()),
);

void main() {
  testWidgets('a non-admin sees the shared not-authorized view, not metrics', (
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
    expect(find.text('Total alerts dispatched'), findsNothing);
  });

  testWidgets('an admin sees model status, job health, and alert volume', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isAdminProvider.overrideWith((ref) async => true),
          latestModelStatusProvider.overrideWith(
            (ref) async => ModelStatus(
              version: 'rf-1.0.0',
              generatedAt: DateTime.now().toUtc(),
            ),
          ),
          jobHeartbeatsProvider.overrideWith(
            (ref) async => [
              JobHeartbeat(
                job: 'compute_risk',
                status: JobRunStatus.ok,
                startedAt: DateTime.now().toUtc(),
                finishedAt: DateTime.now().toUtc(),
                durationMs: 100,
                total: 5,
                counts: const {'written': 5},
              ),
              JobHeartbeat.none('weekly_report'),
            ],
          ),
          alertVolumeProvider.overrideWith((ref) async => 42),
        ],
        child: _host,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('rf-1.0.0'), findsOneWidget);
    expect(find.text('compute_risk'), findsOneWidget);
    expect(find.text('Healthy'), findsOneWidget);
    expect(find.text('weekly_report'), findsOneWidget);
    expect(find.text('Never run yet'), findsOneWidget);
    expect(find.text('No data yet'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    // Honesty rule: never a fabricated active-user number.
    expect(find.text('Not tracked yet'), findsOneWidget);
  });

  testWidgets('shows an honest empty state before any risk estimate exists', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isAdminProvider.overrideWith((ref) async => true),
          latestModelStatusProvider.overrideWith((ref) async => null),
          jobHeartbeatsProvider.overrideWith(
            (ref) async => [JobHeartbeat.none('compute_risk')],
          ),
          alertVolumeProvider.overrideWith((ref) async => 0),
        ],
        child: _host,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('No risk estimates have been written yet.'),
      findsOneWidget,
    );
  });
}
