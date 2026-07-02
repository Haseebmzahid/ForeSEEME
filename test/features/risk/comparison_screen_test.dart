import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/core/widgets/empty_state.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/domain/services/risk_comparison_service.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';
import 'package:fyp_foreseeme/features/risk/presentation/screens/comparison_screen.dart';

RiskEstimateModel _city(String c, RiskLevel level, String disease) =>
    RiskEstimateModel(
      city: c,
      riskLevel: level,
      disease: disease,
      confidence: 0.7,
      temperature: 30,
      humidity: 60,
      aqi: 100,
      generatedAt: DateTime.utc(2026, 6, 28),
      modelVersion: 'rf-1.0.0',
    );

final _cities = [
  _city('Lahore', RiskLevel.high, 'Dengue'),
  _city('Karachi', RiskLevel.medium, 'Heat-Related Illness'),
  _city('Islamabad', RiskLevel.low, 'Respiratory Illness'),
];

final _fixedDate = DateTime.utc(2026, 6, 28);
final _diseases = [
  DiseaseRiskSummary(
    disease: 'Dengue',
    latestLevel: RiskLevel.high,
    latestLowConfidence: false,
    latestAt: _fixedDate,
    weeksObserved: 2,
  ),
  DiseaseRiskSummary(
    disease: 'Smog',
    latestLevel: RiskLevel.low,
    latestLowConfidence: false,
    latestAt: _fixedDate,
    weeksObserved: 1,
  ),
];

Future<void> _pump(
  WidgetTester tester, {
  List<RiskEstimateModel>? cities,
  List<DiseaseRiskSummary>? diseases,
}) async {
  tester.view.physicalSize = const Size(1080, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userCityProvider.overrideWith((ref) async => 'Lahore'),
        allCitiesRiskProvider.overrideWith((ref) async => cities ?? _cities),
        cityDiseaseSummaryProvider.overrideWith(
          (ref, city) async => diseases ?? _diseases,
        ),
      ],
      child: const MaterialApp(home: ComparisonScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('cities view ranks cities with a labelled risk (not colour-only)', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Lahore'), findsOneWidget);
    expect(find.text('Karachi'), findsOneWidget);
    expect(find.text('Islamabad'), findsOneWidget);
    // Risk conveyed by text label (+ icon), never colour alone.
    expect(find.text('High'), findsOneWidget);
    expect(find.text('Medium'), findsOneWidget);
    expect(find.text('Low'), findsOneWidget);
    // Dominant disease shown as the subtitle.
    expect(find.text('Dengue'), findsOneWidget);
  });

  testWidgets('toggling to Diseases shows the per-disease breakdown', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.text('Diseases'));
    await tester.pumpAndSettle();

    expect(find.text('Dengue'), findsOneWidget);
    expect(find.text('Smog'), findsOneWidget);
    expect(find.text('2 weeks'), findsOneWidget);
    expect(find.text('1 week'), findsOneWidget);
  });

  testWidgets('empty cities → informative empty state', (tester) async {
    await _pump(tester, cities: const []);
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.textContaining('No city estimates'), findsOneWidget);
  });

  testWidgets('empty disease history → informative empty state', (tester) async {
    await _pump(tester, diseases: const []);
    await tester.tap(find.text('Diseases'));
    await tester.pumpAndSettle();
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.textContaining('No recent history'), findsOneWidget);
  });
}
