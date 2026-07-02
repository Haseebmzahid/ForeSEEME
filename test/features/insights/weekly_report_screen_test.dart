import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/core/widgets/app_skeleton.dart';
import 'package:fyp_foreseeme/core/widgets/medical_disclaimer.dart';
import 'package:fyp_foreseeme/features/insights/domain/models/adherence_insights.dart';
import 'package:fyp_foreseeme/features/insights/domain/models/health_recommendation.dart';
import 'package:fyp_foreseeme/features/insights/domain/models/weekly_report.dart';
import 'package:fyp_foreseeme/features/insights/domain/services/weekly_report_use_case.dart';
import 'package:fyp_foreseeme/features/insights/presentation/insights_providers.dart';
import 'package:fyp_foreseeme/features/insights/presentation/weekly_report_screen.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/trend_direction.dart';

const _recommendation = HealthRecommendation(
  id: 'rec-resp-air',
  category: 'respiratory',
  driver: 'Air quality',
  text: 'Limit prolonged outdoor exertion during peak smog.',
  source: 'WHO — Air pollution',
  sourceUrl: 'https://www.who.int/health-topics/air-pollution',
  deepLink: '/resources',
  escalation: 'If breathing worsens, seek care; emergency → Rescue 1122.',
);

WeeklyReport _fullReport() => composeWeeklyReport(
  weekOf: DateTime.utc(2026, 6, 29),
  risk: RiskEstimateModel(
    city: 'Lahore',
    riskLevel: RiskLevel.medium,
    disease: 'Dengue',
    confidence: 0.72,
    temperature: 32,
    humidity: 70,
    aqi: 120,
    generatedAt: DateTime.utc(2026, 6, 29),
    modelVersion: 'rf-1.0.0',
  ),
  trend: TrendDirection.rising,
  adherence: const AdherenceInsights(
    currentStreakDays: 3,
    longestStreakDays: 5,
    takenCount: 10,
    missedCount: 1,
    strongestBucket: TimeOfDayBucket.morning,
    focusBucket: TimeOfDayBucket.evening,
  ),
  recommendation: _recommendation,
);

WeeklyReport _emptyReport() => composeWeeklyReport(
  weekOf: DateTime.utc(2026, 6, 29),
  risk: null,
  trend: TrendDirection.insufficient,
  adherence: AdherenceInsights.empty(),
  recommendation: null,
);

Future<void> _pump(
  WidgetTester tester,
  FutureOr<WeeklyReport> Function(Ref ref) build,
) async {
  // Tall viewport so the lazily-built ListView renders every card (the cited
  // recommendation card is below the fold on a default 800×600 surface).
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [weeklyReportProvider.overrideWith(build)],
      child: const MaterialApp(home: WeeklyReportScreen()),
    ),
  );
}

void main() {
  testWidgets('data state renders every section + the cited source', (
    tester,
  ) async {
    await _pump(
      tester,
      (ref) async => _fullReport(),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your weekly health report'), findsOneWidget);
    // Risk + adherence + cited recommendation all present.
    expect(find.textContaining('Lahore'), findsWidgets);
    expect(find.textContaining('3-day streak'), findsOneWidget);
    expect(find.text(_recommendation.text), findsOneWidget);
    expect(find.textContaining('Source: WHO — Air pollution'), findsOneWidget);
    // Non-diagnostic framing is always present.
    expect(find.byType(MedicalDisclaimer), findsOneWidget);
  });

  testWidgets('empty state still renders sections + disclaimer (no crash)', (
    tester,
  ) async {
    await _pump(
      tester,
      (ref) async => _emptyReport(),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your weekly health report'), findsOneWidget);
    expect(find.textContaining("don’t have"), findsOneWidget); // risk empty copy
    expect(find.textContaining('Log a few doses'), findsOneWidget); // adherence
    expect(find.byType(MedicalDisclaimer), findsOneWidget);
  });

  testWidgets('loading state shows the skeleton + disclaimer', (tester) async {
    final never = Completer<WeeklyReport>(); // stays pending → loading
    await _pump(
      tester,
      (ref) => never.future,
    );
    await tester.pump();

    expect(find.byType(AppSkeleton), findsOneWidget);
    expect(find.byType(MedicalDisclaimer), findsOneWidget);
  });
}
