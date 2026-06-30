import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/core/theme/app_design_v2.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/trend_direction.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/trend_badge.dart';

Future<void> pumpBadge(WidgetTester tester, TrendDirection d) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(child: TrendBadge(direction: d)),
      ),
    ),
  );
}

Color? labelColor(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

void main() {
  testWidgets('rising: up arrow + label + high colour', (tester) async {
    await pumpBadge(tester, TrendDirection.rising);
    expect(find.text('Rising'), findsOneWidget);
    expect(find.byIcon(Icons.trending_up_rounded), findsOneWidget);
    expect(labelColor(tester, 'Rising'), AppColorsV2.riskHigh);
  });

  testWidgets('stable: flat arrow + label + medium colour', (tester) async {
    await pumpBadge(tester, TrendDirection.stable);
    expect(find.text('Stable'), findsOneWidget);
    expect(find.byIcon(Icons.trending_flat_rounded), findsOneWidget);
    expect(labelColor(tester, 'Stable'), AppColorsV2.riskMedium);
  });

  testWidgets('falling: down arrow + label + low colour', (tester) async {
    await pumpBadge(tester, TrendDirection.falling);
    expect(find.text('Falling'), findsOneWidget);
    expect(find.byIcon(Icons.trending_down_rounded), findsOneWidget);
    expect(labelColor(tester, 'Falling'), AppColorsV2.riskLow);
  });

  testWidgets(
    'insufficient: dash + label, and NO arrow (never wrong direction)',
    (tester) async {
      await pumpBadge(tester, TrendDirection.insufficient);
      expect(find.text('Insufficient data'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
      expect(
        labelColor(tester, 'Insufficient data'),
        AppColorsV2.riskUncertain,
      );

      // No directional arrow may be shown for insufficient history.
      expect(find.byIcon(Icons.trending_up_rounded), findsNothing);
      expect(find.byIcon(Icons.trending_flat_rounded), findsNothing);
      expect(find.byIcon(Icons.trending_down_rounded), findsNothing);
    },
  );
}
