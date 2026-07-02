import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/risk/domain/models/risk_attributions.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/domain/services/explanation_templater.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/explanation_panel.dart';

RiskEstimateModel estimate({
  required RiskLevel level,
  required ConfidenceStrength strength,
  bool lowConfidence = false,
}) {
  final cls = level.toJson();
  return RiskEstimateModel(
    city: 'Lahore',
    riskLevel: level,
    disease: 'Dengue',
    confidence: 0.72,
    temperature: 32.6,
    humidity: 76.0,
    aqi: 113.0,
    generatedAt: DateTime.utc(2026, 7, 2),
    modelVersion: 'rf-1.0.0',
    lowConfidence: lowConfidence,
    attributions: RiskAttributions(
      method: 'tree_path_contributions',
      modelVersion: 'rf-1.0.0',
      disease: 'dengue',
      predictedClass: cls,
      baseValue: 0.33,
      topContributors: const [
        FeatureContribution(
          feature: 'temperature',
          contribution: 0.44,
          magnitude: 0.44,
          direction: ContributionDirection.increases,
          value: 32.6,
        ),
        FeatureContribution(
          feature: 'humidity_lag1',
          contribution: -0.07,
          magnitude: 0.07,
          direction: ContributionDirection.decreases,
          value: 76.0,
        ),
      ],
      confidenceRationale: ConfidenceRationale(
        confidence: 0.72,
        predictedClass: cls,
        runnerUpClass: 'High',
        runnerUpConfidence: 0.2,
        margin: 0.5,
        agreement: 0.9,
        strength: strength,
        lowConfidence: lowConfidence,
      ),
    ),
  );
}

Future<void> pumpPanel(WidgetTester tester, ExplanationView? view) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [currentCityExplanationProvider.overrideWithValue(view)],
      child: const MaterialApp(home: Scaffold(body: ExplanationPanel())),
    ),
  );
  await tester.pump();
}

ExplanationView viewFor(RiskLevel level, ConfidenceStrength strength) =>
    ExplanationTemplater.build(estimate(level: level, strength: strength))!;

void main() {
  testWidgets('renders the title, lead and templated driver rows', (
    tester,
  ) async {
    await pumpPanel(tester, viewFor(RiskLevel.medium, ConfidenceStrength.moderate));

    expect(find.text('Why this estimate?'), findsOneWidget);
    expect(find.textContaining('Dengue'), findsWidgets);
    // Driver labels rendered in the backend's order.
    expect(find.text('Temperature'), findsOneWidget);
    expect(find.text('Humidity (previous week)'), findsOneWidget);
    // Measured values shown (with units).
    expect(find.text('32.6°C'), findsOneWidget);
    expect(find.text('76%'), findsOneWidget);
    // Direction conveyed by an ICON (not colour alone).
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
  });

  testWidgets('renders across risk levels', (tester) async {
    for (final level in RiskLevel.values) {
      await pumpPanel(tester, viewFor(level, ConfidenceStrength.moderate));
      expect(find.text('Why this estimate?'), findsOneWidget);
      expect(find.text('Temperature'), findsOneWidget);
    }
  });

  testWidgets('confidence chip + sentence reflect strength (label + icon)', (
    tester,
  ) async {
    await pumpPanel(tester, viewFor(RiskLevel.high, ConfidenceStrength.strong));
    expect(find.text('Strong confidence'), findsOneWidget);
    expect(find.textContaining('Confidence is strong'), findsOneWidget);
    expect(find.byIcon(Icons.verified_rounded), findsOneWidget);

    await pumpPanel(tester, viewFor(RiskLevel.medium, ConfidenceStrength.moderate));
    expect(find.text('Moderate confidence'), findsOneWidget);
    expect(find.textContaining('Confidence is moderate'), findsOneWidget);

    await pumpPanel(
      tester,
      ExplanationTemplater.build(
        estimate(
          level: RiskLevel.low,
          strength: ConfidenceStrength.weak,
          lowConfidence: true,
        ),
      )!,
    );
    expect(find.text('Limited confidence'), findsOneWidget);
    expect(find.textContaining('extra caution'), findsOneWidget);
  });

  testWidgets('driver row exposes the full sentence to screen readers', (
    tester,
  ) async {
    await pumpPanel(tester, viewFor(RiskLevel.medium, ConfidenceStrength.moderate));
    expect(
      find.bySemanticsLabel(
        'Temperature, measured 32.6°C, pushed this estimate higher.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows an honest unavailable state when there are no attributions', (
    tester,
  ) async {
    await pumpPanel(tester, null);
    expect(find.textContaining("isn't available"), findsOneWidget);
    // No fabricated drivers.
    expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);
  });
}
