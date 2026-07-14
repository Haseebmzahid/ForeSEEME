import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/core/theme/app_design_v2.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/confidence_meter.dart';

Future<FractionallySizedBox> pumpMeter(
  WidgetTester tester,
  double confidence,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: ConfidenceMeter(confidence: confidence)),
    ),
  );
  return tester.widget<FractionallySizedBox>(find.byType(FractionallySizedBox));
}

Color fillColor(FractionallySizedBox box) => (box.child as Container).color!;

void main() {
  group('ConfidenceMeter', () {
    testWidgets('fill proportion matches the real confidence value', (
      tester,
    ) async {
      final box = await pumpMeter(tester, 0.42);
      expect(box.widthFactor, closeTo(0.42, 0.0001));
    });

    testWidgets('a fraction above 1.0 clamps rather than overflowing', (
      tester,
    ) async {
      final box = await pumpMeter(tester, 1.4);
      expect(box.widthFactor, 1.0);
    });

    testWidgets('a negative fraction clamps to zero', (tester) async {
      final box = await pumpMeter(tester, -0.2);
      expect(box.widthFactor, 0.0);
    });

    testWidgets('strong confidence (>=0.75) uses the low-risk colour', (
      tester,
    ) async {
      final box = await pumpMeter(tester, 0.9);
      expect(fillColor(box), AppColorsV2.riskLow);
    });

    testWidgets('moderate confidence uses the medium-risk colour', (
      tester,
    ) async {
      final box = await pumpMeter(tester, 0.6);
      expect(fillColor(box), AppColorsV2.riskMedium);
    });

    testWidgets(
      'weak confidence uses the neutral uncertain colour, never riskHigh',
      (tester) async {
        final box = await pumpMeter(tester, 0.2);
        expect(fillColor(box), AppColorsV2.riskUncertain);
        expect(fillColor(box), isNot(AppColorsV2.riskHigh));
      },
    );

    testWidgets(
      'is excluded from the semantics tree (pill already labels it)',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: ConfidenceMeter(confidence: 0.8)),
          ),
        );
        expect(find.byType(ExcludeSemantics), findsWidgets);
      },
    );
  });
}
