import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/insights/data/repositories/static_recommendation_repository.dart';
import 'package:fyp_foreseeme/features/insights/domain/services/environmental_insights.dart';
import 'package:fyp_foreseeme/features/insights/domain/services/recommendation_prioritizer.dart';
import 'package:fyp_foreseeme/features/insights/presentation/environmental_insights_card.dart';
import 'package:fyp_foreseeme/features/insights/presentation/insights_providers.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_attributions.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';

const _repo = StaticRecommendationRepository();

RiskAttributions _attr() => const RiskAttributions(
  method: 'tree_path_contributions',
  modelVersion: 'rf-1.0.0',
  disease: 'smog',
  predictedClass: 'High',
  baseValue: 0.33,
  topContributors: [
    FeatureContribution(
      feature: 'us_aqi',
      contribution: 0.4,
      magnitude: 0.4,
      direction: ContributionDirection.increases,
      value: 180,
    ),
    FeatureContribution(
      feature: 'temperature',
      contribution: -0.1,
      magnitude: 0.1,
      direction: ContributionDirection.decreases,
      value: 12,
    ),
  ],
  confidenceRationale: ConfidenceRationale(
    confidence: 0.82,
    predictedClass: 'High',
    runnerUpClass: 'Medium',
    runnerUpConfidence: 0.12,
    margin: 0.7,
    agreement: 0.9,
    strength: ConfidenceStrength.strong,
    lowConfidence: false,
  ),
);

RiskEstimateModel _estimate() => RiskEstimateModel(
  city: 'Lahore',
  riskLevel: RiskLevel.high,
  disease: 'Smog',
  confidence: 0.82,
  temperature: 12,
  humidity: 40,
  aqi: 180,
  generatedAt: DateTime.utc(2026, 6, 28),
  modelVersion: 'rf-1.0.0',
  attributions: _attr(),
);

EnvironmentalInsightsView _view() {
  final estimate = _estimate();
  return EnvironmentalInsightsView(
    estimate: estimate,
    drivers: deriveEnvironmentalDrivers(estimate.attributions),
    guidance: prioritizeRecommendations(
      riskLevel: estimate.riskLevel,
      disease: estimate.disease,
      conditions: const ['Asthma'],
      repository: _repo,
    ),
  );
}

Future<void> _pump(WidgetTester tester, EnvironmentalInsightsView view) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        environmentalInsightsProvider.overrideWith((ref) async => view),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: EnvironmentalInsightsCard()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('reflects the attributions and shows most-relevant guidance', (
    tester,
  ) async {
    await _pump(tester, _view());

    expect(find.text('Environmental drivers'), findsOneWidget);
    // Driver from real attributions (top environmental factor), labelled.
    expect(find.text('Air quality (AQI)'), findsOneWidget);
    expect(find.text('Temperature'), findsOneWidget);
    // Direction conveyed by an icon (not colour alone).
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
    // Prioritized cited guidance, top one badged + sourced.
    expect(find.text('Most relevant'), findsOneWidget);
    expect(find.textContaining('Source: WHO — Air pollution'), findsOneWidget);
  });

  testWidgets('renders nothing when there is no content (no estimate)', (
    tester,
  ) async {
    await _pump(
      tester,
      const EnvironmentalInsightsView(
        estimate: null,
        drivers: [],
        guidance: [],
      ),
    );
    expect(find.text('Environmental drivers'), findsNothing);
  });
}
