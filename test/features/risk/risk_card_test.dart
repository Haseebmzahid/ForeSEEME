import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shimmer/shimmer.dart';

import 'package:fyp_foreseeme/core/theme/app_design_v2.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_card.dart';

RiskEstimateModel estimate({
  RiskLevel level = RiskLevel.high,
  String disease = 'Respiratory Illness',
  double confidence = 0.89,
  bool lowConfidence = false,
}) => RiskEstimateModel(
  city: 'Lahore',
  riskLevel: level,
  disease: disease,
  confidence: confidence,
  temperature: 34.0,
  humidity: 55.0,
  aqi: 210.0,
  generatedAt: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
  modelVersion: 'rf-v1.2',
  lowConfidence: lowConfidence,
);

/// The card under a Scaffold; the enclosing [ProviderScope] supplies overrides.
const _host = MaterialApp(
  home: Scaffold(
    backgroundColor: AppColorsV2.shell,
    body: Center(child: RiskCard()),
  ),
);

Future<void> pumpScope(
  WidgetTester tester,
  ProviderScope scope, {
  bool settle = true,
}) async {
  await tester.pumpWidget(scope);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Color? headlineColor(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

void main() {
  group('RiskCard data states', () {
    testWidgets('High shows label + triangle icon + risk colour', (
      tester,
    ) async {
      await pumpScope(
        tester,
        ProviderScope(
          overrides: [
            currentCityRiskProvider.overrideWith(
              (ref) => estimate(level: RiskLevel.high),
            ),
          ],
          child: _host,
        ),
      );

      expect(find.text('High Risk'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(find.textContaining('89% confidence'), findsOneWidget);
      expect(headlineColor(tester, 'High Risk'), AppColorsV2.riskHigh);
    });

    testWidgets('Medium shows label + caution icon + risk colour', (
      tester,
    ) async {
      await pumpScope(
        tester,
        ProviderScope(
          overrides: [
            currentCityRiskProvider.overrideWith(
              (ref) => estimate(level: RiskLevel.medium),
            ),
          ],
          child: _host,
        ),
      );

      expect(find.text('Medium Risk'), findsOneWidget);
      expect(find.byIcon(Icons.priority_high_rounded), findsOneWidget);
      expect(headlineColor(tester, 'Medium Risk'), AppColorsV2.riskMedium);
    });

    testWidgets('Low shows label + check icon + risk colour', (tester) async {
      await pumpScope(
        tester,
        ProviderScope(
          overrides: [
            currentCityRiskProvider.overrideWith(
              (ref) => estimate(level: RiskLevel.low),
            ),
          ],
          child: _host,
        ),
      );

      expect(find.text('Low Risk'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);
      expect(headlineColor(tester, 'Low Risk'), AppColorsV2.riskLow);
    });

    testWidgets('low-confidence renders the grey uncertainty treatment', (
      tester,
    ) async {
      await pumpScope(
        tester,
        ProviderScope(
          overrides: [
            currentCityRiskProvider.overrideWith(
              (ref) => estimate(level: RiskLevel.high, lowConfidence: true),
            ),
          ],
          child: _host,
        ),
      );

      // Grey "Uncertain" + question icon; the misleading level label is hidden.
      expect(find.text('Uncertain'), findsOneWidget);
      expect(find.byIcon(Icons.help_outline_rounded), findsOneWidget);
      expect(find.text('High Risk'), findsNothing);
      expect(find.textContaining('low confidence'), findsOneWidget);
      expect(headlineColor(tester, 'Uncertain'), AppColorsV2.riskUncertain);
    });
  });

  group('RiskCard non-data states', () {
    testWidgets('empty names the user\'s city', (tester) async {
      await pumpScope(
        tester,
        ProviderScope(
          overrides: [
            currentCityRiskProvider.overrideWith((ref) => null),
            userCityProvider.overrideWith((ref) => 'Lahore'),
          ],
          child: _host,
        ),
      );

      expect(find.text('No risk data yet'), findsOneWidget);
      expect(find.textContaining('Lahore'), findsOneWidget);
    });

    testWidgets('error shows a retry affordance', (tester) async {
      await pumpScope(
        tester,
        ProviderScope(
          overrides: [
            currentCityRiskProvider.overrideWith(
              (ref) => Future.error(Exception('offline')),
            ),
          ],
          child: _host,
        ),
      );

      expect(find.text("Couldn't load risk"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);

      // The retry control is wired (invalidates and re-reads); tapping it must
      // not throw and keeps the error state for this always-failing override.
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load risk"), findsOneWidget);
    });

    testWidgets('loading shows a skeleton, not a risk level', (tester) async {
      await pumpScope(
        tester,
        settle: false,
        ProviderScope(
          overrides: [
            // A future that never completes keeps the card loading.
            currentCityRiskProvider.overrideWith(
              (ref) => Completer<RiskEstimateModel?>().future,
            ),
          ],
          child: _host,
        ),
      );

      expect(find.byType(Shimmer), findsOneWidget);
      expect(find.text('High Risk'), findsNothing);
      expect(find.text('No risk data yet'), findsNothing);
    });
  });
}
