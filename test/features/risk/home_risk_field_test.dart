import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyp_foreseeme/core/widgets/app_skeleton.dart';

import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/trend_direction.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_override_provider.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/home_risk_field.dart';

RiskEstimateModel estimate({
  RiskLevel level = RiskLevel.high,
  String disease = 'Respiratory Illness',
  double confidence = 0.89,
  bool lowConfidence = false,
  Duration age = const Duration(hours: 2),
}) => RiskEstimateModel(
  city: 'Lahore',
  riskLevel: level,
  disease: disease,
  confidence: confidence,
  temperature: 34.0,
  humidity: 55.0,
  aqi: 210.0,
  generatedAt: DateTime.now().toUtc().subtract(age),
  modelVersion: 'rf-v1.2',
  lowConfidence: lowConfidence,
);

Widget host({VoidCallback? onTap}) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(child: HomeRiskField(onTap: onTap)),
  ),
);

/// Mirrors `risk_card_test.dart`'s `pumpScope`: the enclosing [ProviderScope]
/// supplies the overrides.
///
/// [settle] defaults to **false** here, unlike the risk card's helper. A loaded
/// field runs an ambient drift (a ticker that never finishes by design), so
/// `pumpAndSettle` would time out on any data state. The synchronous provider
/// overrides land on the first frame, so a single pump is enough. [settle] is
/// used only where a state must be *awaited* — an asynchronously-resolved
/// provider — and those states are the static lattice, which does settle.
Future<void> pumpScope(
  WidgetTester tester,
  ProviderScope scope, {
  bool settle = false,
}) async {
  await tester.pumpWidget(scope);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

void main() {
  group('HomeRiskField data state', () {
    testWidgets('shows the level, its glyph and the measured channels', (
      tester,
    ) async {
      await pumpScope(
        tester,
        ProviderScope(
          overrides: [
            currentCityOverrideProvider.overrideWith((ref) => null),
            currentCityRiskProvider.overrideWith((ref) => estimate()),
            riskTrendProvider.overrideWith((ref) => TrendDirection.rising),
          ],
          child: host(),
        ),
      );

      // Level: written label + distinct glyph, never colour alone.
      expect(find.text('High Risk'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(find.text('ELEVATED FIELD'), findsOneWidget);

      // Provenance strip, sourced from the estimate and the city centroid.
      expect(find.text('LAHORE · REGIONAL FIELD'), findsOneWidget);
      expect(find.text('31.550°N 74.344°E'), findsOneWidget);

      // Every environmental channel is a stored value on the estimate.
      expect(find.text('AQI'), findsOneWidget);
      expect(find.text('210'), findsOneWidget);
      expect(find.text('TEMP'), findsOneWidget);
      expect(find.text('34°'), findsOneWidget);
      expect(find.text('HUMIDITY'), findsOneWidget);
      expect(find.text('DISEASE'), findsOneWidget);
      expect(find.text('Respiratory Illness'), findsOneWidget);

      // Telemetry footer.
      expect(find.text('CONFIDENCE'), findsOneWidget);
      expect(find.text('89%'), findsOneWidget);
      expect(find.text('UPDATED'), findsOneWidget);
      expect(find.text('2h ago'), findsOneWidget);
      expect(find.text('TREND'), findsOneWidget);
      expect(find.text('↑ RISING'), findsOneWidget);
    });

    testWidgets('never shows a rainfall channel — the contract has none', (
      tester,
    ) async {
      await pumpScope(
        tester,
        ProviderScope(
          overrides: [
            currentCityOverrideProvider.overrideWith((ref) => null),
            currentCityRiskProvider.overrideWith((ref) => estimate()),
            riskTrendProvider.overrideWith((ref) => TrendDirection.stable),
          ],
          child: host(),
        ),
      );

      // The prototype's fourth readout is rainfall; RiskEstimateModel does not
      // carry it, so the slot must never be filled with a placeholder value.
      expect(find.textContaining('RAINFALL'), findsNothing);
      expect(find.textContaining('mm'), findsNothing);
      expect(find.text('0.0'), findsNothing);
    });

    testWidgets('insufficient history reads as a dash, never an arrow', (
      tester,
    ) async {
      await pumpScope(
        tester,
        ProviderScope(
          overrides: [
            currentCityOverrideProvider.overrideWith((ref) => null),
            currentCityRiskProvider.overrideWith((ref) => estimate()),
            riskTrendProvider.overrideWith(
              (ref) => TrendDirection.insufficient,
            ),
          ],
          child: host(),
        ),
      );

      expect(find.text('— INSUFFICIENT'), findsOneWidget);
      expect(find.text('↑ RISING'), findsNothing);
      expect(find.text('↓ FALLING'), findsNothing);
    });

    testWidgets('low confidence shows the uncertainty treatment', (
      tester,
    ) async {
      await pumpScope(
        tester,
        ProviderScope(
          overrides: [
            currentCityOverrideProvider.overrideWith((ref) => null),
            currentCityRiskProvider.overrideWith(
              (ref) => estimate(level: RiskLevel.high, lowConfidence: true),
            ),
            riskTrendProvider.overrideWith(
              (ref) => TrendDirection.insufficient,
            ),
          ],
          child: host(),
        ),
      );

      expect(find.text('Uncertain'), findsOneWidget);
      expect(find.byIcon(Icons.help_outline_rounded), findsOneWidget);
      expect(find.text('NOT ENOUGH CERTAINTY'), findsOneWidget);
      // The unreliable classification is never asserted.
      expect(find.text('High Risk'), findsNothing);
      expect(find.text('ELEVATED FIELD'), findsNothing);
    });

    testWidgets('a stale estimate says so', (tester) async {
      await pumpScope(
        tester,
        ProviderScope(
          overrides: [
            currentCityOverrideProvider.overrideWith((ref) => null),
            currentCityRiskProvider.overrideWith(
              (ref) => estimate(age: const Duration(days: 30)),
            ),
            riskTrendProvider.overrideWith((ref) => TrendDirection.rising),
          ],
          child: host(),
        ),
      );

      expect(find.text('This estimate may be out of date'), findsOneWidget);
    });

    testWidgets('a fresh estimate does not', (tester) async {
      await pumpScope(
        tester,
        ProviderScope(
          overrides: [
            currentCityOverrideProvider.overrideWith((ref) => null),
            currentCityRiskProvider.overrideWith((ref) => estimate()),
            riskTrendProvider.overrideWith((ref) => TrendDirection.rising),
          ],
          child: host(),
        ),
      );

      expect(find.text('This estimate may be out of date'), findsNothing);
    });

    testWidgets('opens risk details, announced as one node with the readings', (
      tester,
    ) async {
      var opened = 0;
      await pumpScope(
        tester,
        ProviderScope(
          overrides: [
            currentCityOverrideProvider.overrideWith((ref) => null),
            currentCityRiskProvider.overrideWith((ref) => estimate()),
            riskTrendProvider.overrideWith((ref) => TrendDirection.rising),
          ],
          child: host(onTap: () => opened++),
        ),
      );

      await tester.tap(find.text('High Risk'));
      await tester.pump();
      expect(opened, 1);

      // The readings and the action live on one semantics node, so a screen
      // reader announces "…, opens risk details" rather than two nodes.
      final semantics = tester.getSemantics(find.byType(HomeRiskField));
      expect(semantics.label, contains('High Risk'));
      expect(semantics.label, contains('89 percent confidence'));
      expect(semantics.label, contains('Opens risk details'));
    });
  });

  group('HomeRiskField non-data states', () {
    testWidgets('no estimate renders an explicit gap, not a low reading', (
      tester,
    ) async {
      await pumpScope(
        tester,
        ProviderScope(
          overrides: [
            currentCityOverrideProvider.overrideWith((ref) => null),
            currentCityRiskProvider.overrideWith((ref) => null),
            userCityProvider.overrideWith((ref) => 'Lahore'),
          ],
          child: host(),
        ),
      );

      expect(find.text('No estimate yet'), findsOneWidget);
      expect(find.text('NO ESTIMATE AVAILABLE'), findsOneWidget);
      expect(find.textContaining('Lahore'), findsWidgets);
      // Absent telemetry reads as absent, never as a number.
      expect(find.text('—'), findsNWidgets(3));
      expect(find.text('Low Risk'), findsNothing);
    });

    testWidgets('error offers a retry that stays reachable', (tester) async {
      await pumpScope(
        tester,
        ProviderScope(
          overrides: [
            currentCityOverrideProvider.overrideWith((ref) => null),
            currentCityRiskProvider.overrideWith(
              (ref) => Future.error(Exception('offline')),
            ),
          ],
          child: host(),
        ),
        settle: true,
      );

      expect(find.text("Couldn't load risk"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      // The error surface must not be collapsed into one semantics node, or the
      // retry action would be lost to a screen reader.
      final retry = tester.getSemantics(find.text('Retry'));
      expect(retry.label, 'Retry');
      expect(
        retry.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
        reason: 'the retry action must survive as its own semantics node',
      );

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load risk"), findsOneWidget);
    });

    testWidgets('loading shows a skeleton, never a risk level', (tester) async {
      await pumpScope(
        tester,
        ProviderScope(
          overrides: [
            currentCityOverrideProvider.overrideWith((ref) => null),
            currentCityRiskProvider.overrideWith(
              (ref) => Completer<RiskEstimateModel?>().future,
            ),
          ],
          child: host(),
        ),
      );

      // `AppSkeleton` is the assertion, not `Shimmer`: it correctly drops the
      // shimmer sweep under reduced motion, which this host requests.
      expect(find.byType(AppSkeleton), findsOneWidget);
      expect(find.byType(SkeletonBar), findsWidgets);
      expect(find.text('High Risk'), findsNothing);
      expect(find.text('No estimate yet'), findsNothing);
    });
  });

  group('HomeRiskField responsiveness', () {
    for (final size in const [Size(360, 640), Size(412, 915)]) {
      testWidgets('lays out cleanly at ${size.width}x${size.height}', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await pumpScope(
          tester,
          ProviderScope(
            overrides: [
              currentCityOverrideProvider.overrideWith((ref) => null),
              currentCityRiskProvider.overrideWith((ref) => estimate()),
              riskTrendProvider.overrideWith((ref) => TrendDirection.rising),
            ],
            child: host(),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(find.text('High Risk'), findsOneWidget);
      });
    }

    testWidgets('survives a large text scale on a small phone', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpScope(
        tester,
        ProviderScope(
          overrides: [
            currentCityOverrideProvider.overrideWith((ref) => null),
            currentCityRiskProvider.overrideWith((ref) => estimate()),
            riskTrendProvider.overrideWith((ref) => TrendDirection.rising),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.6)),
                child: const Scaffold(
                  body: SingleChildScrollView(child: HomeRiskField()),
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('High Risk'), findsOneWidget);
    });
  });
}
