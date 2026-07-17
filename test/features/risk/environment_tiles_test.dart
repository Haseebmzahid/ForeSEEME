import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/environment_tiles.dart';

RiskEstimateModel _est({
  required double aqi,
  required double temperature,
  required double humidity,
}) => RiskEstimateModel(
  city: 'Lahore',
  riskLevel: RiskLevel.high,
  disease: 'Smog',
  confidence: 0.9,
  temperature: temperature,
  humidity: humidity,
  aqi: aqi,
  generatedAt: DateTime.utc(2026, 7, 1),
  modelVersion: 'rf-1.0.0',
);

Future<void> pumpTiles(WidgetTester tester, RiskEstimateModel estimate) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: EnvironmentTiles(estimate: estimate)),
    ),
  );
}

Color? textColor(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

/// The ambient design-system tokens the tiles resolve their band colour from.
BuildContext _ctx(WidgetTester tester) =>
    tester.element(find.byType(EnvironmentTiles));

void main() {
  testWidgets('shows both an AQI value+band and a weather value', (
    tester,
  ) async {
    await pumpTiles(tester, _est(aqi: 180, temperature: 32, humidity: 55));

    expect(find.text('180'), findsOneWidget);
    expect(find.text('Unhealthy'), findsOneWidget);
    expect(find.text('32°C'), findsOneWidget);
    expect(find.text('55% humidity'), findsOneWidget);
  });

  testWidgets('a Good AQI band uses the low-risk colour', (tester) async {
    await pumpTiles(tester, _est(aqi: 20, temperature: 25, humidity: 40));

    expect(find.text('Good'), findsOneWidget);
    expect(textColor(tester, 'Good'), _ctx(tester).fsmColors.success);
  });

  testWidgets('a Hazardous AQI band uses the high-risk colour', (tester) async {
    await pumpTiles(tester, _est(aqi: 350, temperature: 30, humidity: 50));

    expect(find.text('Hazardous'), findsOneWidget);
    expect(textColor(tester, 'Hazardous'), _ctx(tester).fsmPalette.error);
  });

  testWidgets('each tile carries a Semantics node (not colour-only)', (
    tester,
  ) async {
    await pumpTiles(tester, _est(aqi: 60, temperature: 28, humidity: 45));

    final semantics = tester.getSemantics(find.byType(EnvironmentTiles));
    expect(semantics, isNotNull);
  });
}
