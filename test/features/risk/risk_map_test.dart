import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:fyp_foreseeme/core/theme/app_design_v2.dart';
import 'package:fyp_foreseeme/features/risk/data/repositories/fake_risk_repository.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';
import 'package:fyp_foreseeme/features/risk/presentation/screens/risk_map_screen.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_visuals.dart';

RiskEstimateModel est(
  String city,
  RiskLevel level, {
  bool lowConfidence = false,
}) => RiskEstimateModel(
  city: city,
  riskLevel: level,
  disease: 'Dengue',
  confidence: 0.8,
  temperature: 30,
  humidity: 50,
  aqi: 100,
  generatedAt: DateTime.utc(2026, 6, 30),
  modelVersion: 'rf-1.0.0',
  lowConfidence: lowConfidence,
);

void main() {
  group('getLatestRiskAllCities (latest-per-city)', () {
    test(
      'returns one estimate per city that has data, omitting the rest',
      () async {
        final repo = FakeRiskRepository(
          seed: {
            'Lahore': est('Lahore', RiskLevel.high),
            'Karachi': est('Karachi', RiskLevel.medium),
          },
        );

        final all = await repo.getLatestRiskAllCities([
          'Lahore',
          'Karachi',
          'Peshawar', // no data -> omitted
        ]);

        expect(all.length, 2);
        expect(
          all.map((e) => e.city),
          containsAll(<String>['Lahore', 'Karachi']),
        );
      },
    );

    test('allCitiesRiskProvider streams the repository result', () async {
      final container = ProviderContainer(
        overrides: [
          riskRepositoryProvider.overrideWithValue(
            FakeRiskRepository(seed: {'Lahore': est('Lahore', RiskLevel.high)}),
          ),
        ],
      );
      addTearDown(container.dispose);

      final list = await container.read(allCitiesRiskProvider.future);

      expect(list, isNotEmpty);
      expect(list.first.city, 'Lahore');
    });
  });

  group('riskMarkerHue', () {
    test('maps each appearance to a distinct hue', () {
      expect(riskMarkerHue(RiskVisuals.high), BitmapDescriptor.hueRed);
      expect(riskMarkerHue(RiskVisuals.medium), BitmapDescriptor.hueOrange);
      expect(riskMarkerHue(RiskVisuals.low), BitmapDescriptor.hueGreen);
      expect(riskMarkerHue(RiskVisuals.uncertain), BitmapDescriptor.hueAzure);
    });
  });

  group('CityDetailSheet', () {
    testWidgets('shows city, disease and an accessible risk pill', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CityDetailSheet(estimate: est('Lahore', RiskLevel.high)),
          ),
        ),
      );

      expect(find.text('Lahore'), findsOneWidget);
      expect(find.text('Dengue'), findsOneWidget);
      expect(find.text('High'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('High')).style?.color,
        AppColorsV2.riskHigh,
      );
    });

    testWidgets('low-confidence shows the grey Uncertain treatment', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CityDetailSheet(
              estimate: est('Karachi', RiskLevel.high, lowConfidence: true),
            ),
          ),
        ),
      );

      expect(find.text('Uncertain'), findsOneWidget);
      expect(find.byIcon(Icons.help_outline_rounded), findsOneWidget);
      expect(find.text('High'), findsNothing);
    });

    testWidgets('a stale city estimate labels the sheet honestly', (
      tester,
    ) async {
      // A year in the past → stale regardless of the machine clock.
      final stale = est(
        'Lahore',
        RiskLevel.high,
      ).copyWith(generatedAt: DateTime.utc(2000, 1, 1));
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: CityDetailSheet(estimate: stale))),
      );

      expect(find.text('Lahore'), findsOneWidget);
      expect(find.text('This estimate may be out of date'), findsOneWidget);
    });

    testWidgets('a fresh city estimate shows no staleness notice', (
      tester,
    ) async {
      final fresh = est(
        'Lahore',
        RiskLevel.high,
      ).copyWith(generatedAt: DateTime.now().toUtc());
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: CityDetailSheet(estimate: fresh))),
      );

      expect(find.text('This estimate may be out of date'), findsNothing);
    });
  });
}
