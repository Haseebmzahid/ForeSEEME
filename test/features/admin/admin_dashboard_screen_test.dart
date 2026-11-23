import 'package:flutter/material.dart';
import 'package:fyp_foreseeme/features/admin/domain/models/operational_metrics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/admin/domain/models/job_heartbeat.dart';
import 'package:fyp_foreseeme/features/admin/domain/models/model_status.dart';
import 'package:fyp_foreseeme/features/admin/presentation/admin_dashboard_screen.dart';
import 'package:fyp_foreseeme/features/admin/presentation/admin_providers.dart';
import 'package:fyp_foreseeme/features/admin/presentation/system_status_providers.dart';

const _host = MaterialApp(home: Scaffold(body: AdminDashboardScreen()));

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
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isAdminProvider.overrideWith((ref) async => true),
          deployedModelProvider.overrideWith((ref) async => null),
          accountMetricsProvider.overrideWith(
            (ref) async => AccountMetrics(
              totalUsers: 7,
              activeUsers: 3,
              windowDays: 30,
              generatedAt: DateTime.utc(2026),
            ),
          ),
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

    expect(find.text('Latest estimate · rf-1.0.0'), findsOneWidget);
    expect(find.text('compute_risk'), findsOneWidget);
    expect(find.text('Healthy'), findsOneWidget);
    expect(find.text('weekly_report'), findsOneWidget);
    expect(find.text('Never executed'), findsOneWidget);
    expect(find.text('Unknown'), findsNWidgets(2));
    expect(find.text('42'), findsOneWidget);
    // Honesty rule: never a fabricated active-user number.
    expect(find.textContaining('Active users in 30 days · 3'), findsOneWidget);
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

  testWidgets(
    'an untested deployed version leaves healthy runs degraded overall',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime.now();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isAdminProvider.overrideWith((ref) async => true),
            deployedModelProvider.overrideWith(
              (ref) async =>
                  ModelStatus(version: 'new-model', generatedAt: now),
            ),
            latestModelStatusProvider.overrideWith(
              (ref) async =>
                  ModelStatus(version: 'old-model', generatedAt: now),
            ),
            accountMetricsProvider.overrideWith((ref) async => null),
            alertVolumeProvider.overrideWith((ref) async => 8),
            jobHeartbeatsProvider.overrideWith(
              (ref) async => [
                for (final job in [
                  'compute_risk',
                  'dispatch_alerts',
                  'weekly_report',
                ])
                  JobHeartbeat(
                    job: job,
                    status: JobRunStatus.ok,
                    startedAt: now,
                    finishedAt: now,
                    durationMs: 42,
                    total: 1,
                    counts: const {},
                    lastSuccessfulModelVersion: job == 'compute_risk'
                        ? 'old-model'
                        : null,
                  ),
              ],
            ),
          ],
          child: _host,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Degraded'), findsOneWidget);
      expect(find.textContaining('Deployed model · new-model'), findsOneWidget);
      expect(
        find.textContaining('latest successful batch · old-model'),
        findsOneWidget,
      );
      expect(find.text('8'), findsOneWidget);
    },
  );
}
