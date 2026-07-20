import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/location_comparison.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/trend_direction.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/location_comparison_card.dart';

RiskEstimateModel _est(String city, RiskLevel level, double aqi) =>
    RiskEstimateModel(
      city: city,
      riskLevel: level,
      disease: 'Dengue',
      confidence: 0.8,
      temperature: 30,
      humidity: 50,
      aqi: aqi,
      generatedAt: DateTime.utc(2026, 7, 18),
      modelVersion: 'rf-1.0.0',
    );

void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: ForeSeeMeTheme.light,
    home: Scaffold(body: Align(alignment: Alignment.topRight, child: child)),
  );

  /// The card is a small overlay in production, but the default 800x600 test
  /// surface is tighter than any real phone viewport — widen it, mirroring
  /// the `_tallSurface` pattern used elsewhere in this suite for
  /// size-sensitive widgets.
  void tallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('shows both real cities, their levels, and the AQI delta', (
    tester,
  ) async {
    tallSurface(tester);
    final comparison = LocationComparison(
      yourCity: 'Islamabad',
      yourEstimate: _est('Islamabad', RiskLevel.low, 60),
      yourTrend: TrendDirection.stable,
      nearbyCity: 'Rawalpindi',
      nearbyEstimate: _est('Rawalpindi', RiskLevel.medium, 90),
      nearbyTrend: TrendDirection.rising,
    );

    await tester.pumpWidget(
      wrap(LocationComparisonCard(comparison: comparison)),
    );

    expect(find.text('Islamabad'), findsOneWidget);
    expect(find.text('Rawalpindi'), findsOneWidget);
    expect(find.text('Low'), findsOneWidget);
    expect(find.text('Medium'), findsOneWidget);
    expect(find.text('AQI +30 there'), findsOneWidget);
  });

  testWidgets('negative delta reads as lower AQI there', (tester) async {
    tallSurface(tester);
    final comparison = LocationComparison(
      yourCity: 'Lahore',
      yourEstimate: _est('Lahore', RiskLevel.high, 210),
      yourTrend: TrendDirection.insufficient,
      nearbyCity: 'Karachi',
      nearbyEstimate: _est('Karachi', RiskLevel.medium, 150),
      nearbyTrend: TrendDirection.insufficient,
    );

    await tester.pumpWidget(
      wrap(LocationComparisonCard(comparison: comparison)),
    );

    expect(find.text('AQI -60 there'), findsOneWidget);
  });

  testWidgets('dismiss button fires the callback', (tester) async {
    tallSurface(tester);
    var dismissed = false;
    final comparison = LocationComparison(
      yourCity: 'Islamabad',
      yourEstimate: _est('Islamabad', RiskLevel.low, 60),
      yourTrend: TrendDirection.stable,
      nearbyCity: 'Rawalpindi',
      nearbyEstimate: _est('Rawalpindi', RiskLevel.low, 62),
      nearbyTrend: TrendDirection.stable,
    );

    await tester.pumpWidget(
      wrap(
        LocationComparisonCard(
          comparison: comparison,
          onDismiss: () => dismissed = true,
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    expect(dismissed, isTrue);
  });

  testWidgets('dismiss button is independently reachable for screen readers', (
    tester,
  ) async {
    tallSurface(tester);
    final handle = tester.ensureSemantics();
    final comparison = LocationComparison(
      yourCity: 'Islamabad',
      yourEstimate: _est('Islamabad', RiskLevel.low, 60),
      yourTrend: TrendDirection.stable,
      nearbyCity: 'Rawalpindi',
      nearbyEstimate: _est('Rawalpindi', RiskLevel.low, 62),
      nearbyTrend: TrendDirection.stable,
    );

    await tester.pumpWidget(
      wrap(
        LocationComparisonCard(comparison: comparison, onDismiss: () {}),
      ),
    );

    expect(
      find.bySemanticsLabel('Dismiss location comparison'),
      findsOneWidget,
    );
    handle.dispose();
  });
}
