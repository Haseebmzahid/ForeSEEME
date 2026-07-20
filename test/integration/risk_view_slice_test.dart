import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fyp_foreseeme/core/theme/theme_provider.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/resources/presentation/resource_center_screen.dart';
import 'package:fyp_foreseeme/features/risk/data/repositories/fake_risk_repository.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/trend_direction.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_card.dart';

RiskEstimateModel at(String city, int week, RiskLevel level) =>
    RiskEstimateModel(
      city: city,
      riskLevel: level,
      disease: 'Respiratory Illness',
      confidence: 0.89,
      temperature: 34,
      humidity: 55,
      aqi: 210,
      generatedAt: DateTime.now().toUtc().subtract(
        Duration(days: 7 * (5 - week)),
      ),
      modelVersion: 'rf-1.0.0',
    );

/// Integration across the risk-view slice: one seeded repository feeds the
/// dashboard risk card, the trend, the national-map data, AND the Resource
/// Center's High-risk hospital prominence — proving the providers compose.
void main() {
  FakeRiskRepository seededRepo() => FakeRiskRepository(
    seed: {
      'Lahore': at('Lahore', 5, RiskLevel.high),
      'Karachi': at('Karachi', 5, RiskLevel.medium),
      'Islamabad': at('Islamabad', 5, RiskLevel.low),
    },
    history: {
      'Lahore': [
        at('Lahore', 0, RiskLevel.low),
        at('Lahore', 1, RiskLevel.low),
        at('Lahore', 2, RiskLevel.medium),
        at('Lahore', 5, RiskLevel.high),
      ],
    },
  );

  group('data vertical', () {
    test('one feed drives current risk, trend, and all-cities', () async {
      final container = ProviderContainer(
        overrides: [
          userCityProvider.overrideWith((ref) => 'Lahore'),
          riskRepositoryProvider.overrideWithValue(seededRepo()),
        ],
      );
      addTearDown(container.dispose);
      container.listen(
        currentCityRiskProvider,
        (_, _) {},
        fireImmediately: true,
      );
      container.listen(riskTrendProvider, (_, _) {}, fireImmediately: true);
      container.listen(allCitiesRiskProvider, (_, _) {}, fireImmediately: true);

      final current = await container.read(currentCityRiskProvider.future);
      final trend = await container.read(riskTrendProvider.future);
      final allCities = await container.read(allCitiesRiskProvider.future);

      expect(current?.riskLevel, RiskLevel.high);
      expect(trend, TrendDirection.rising);
      expect(allCities.map((e) => e.city), containsAll(['Lahore', 'Karachi']));
    });
  });

  group('UI slice', () {
    testWidgets('High risk reaches the dashboard card with its trend', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentCityRiskProvider.overrideWith(
              (ref) => at('Lahore', 5, RiskLevel.high),
            ),
            riskTrendProvider.overrideWith((ref) => TrendDirection.rising),
          ],
          child: const MaterialApp(home: Scaffold(body: RiskCard())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('High Risk'), findsOneWidget);
      expect(find.text('Rising'), findsOneWidget);
    });

    testWidgets(
      'High risk surfaces hospitals prominently in the Resource Center',
      (tester) async {
        tester.view.physicalSize = const Size(900, 2600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              currentCityRiskProvider.overrideWith(
                (ref) => at('Lahore', 5, RiskLevel.high),
              ),
              sharedPreferencesProvider.overrideWithValue(prefs),
            ],
            child: const MaterialApp(home: ResourceCenterScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('Surfaced because risk is High in your area'),
          findsOneWidget,
        );
      },
    );
  });
}
