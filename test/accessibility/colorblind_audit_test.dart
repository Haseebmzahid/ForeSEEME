import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/risk/domain/models/trend_direction.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_legend.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_visuals.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/trend_badge.dart';

/// Sprint 3 accessibility audit (codified): every risk/status indicator must
/// pair colour with a label and a distinct icon/glyph, so it reads correctly in
/// greyscale / for colorblind users. "Never colour alone."
void main() {
  group('risk levels', () {
    final appearances = <RiskAppearance>[
      RiskVisuals.low,
      RiskVisuals.medium,
      RiskVisuals.high,
      RiskVisuals.uncertain,
    ];

    test('every level has a label and a headline', () {
      for (final a in appearances) {
        expect(a.label, isNotEmpty);
        expect(a.headline, isNotEmpty);
      }
    });

    test('icons are mutually distinct (survive greyscale)', () {
      final icons = appearances.map((a) => a.icon).toSet();
      expect(icons.length, appearances.length);
    });

    test(
      'colours are distinct (colour is a secondary cue, not the only one)',
      () {
        final colours = appearances.map((a) => a.color).toSet();
        expect(colours.length, appearances.length);
      },
    );
  });

  group('trend badge', () {
    Future<void> pump(WidgetTester tester, TrendDirection d) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: TrendBadge(direction: d)),
          ),
        );

    testWidgets('rising/stable/falling each show an arrow + label', (
      tester,
    ) async {
      await pump(tester, TrendDirection.rising);
      expect(find.text('Rising'), findsOneWidget);
      expect(find.byIcon(Icons.trending_up_rounded), findsOneWidget);

      await pump(tester, TrendDirection.stable);
      expect(find.text('Stable'), findsOneWidget);
      expect(find.byIcon(Icons.trending_flat_rounded), findsOneWidget);

      await pump(tester, TrendDirection.falling);
      expect(find.text('Falling'), findsOneWidget);
      expect(find.byIcon(Icons.trending_down_rounded), findsOneWidget);
    });

    testWidgets(
      'insufficient shows a dash + label, never a directional arrow',
      (tester) async {
        await pump(tester, TrendDirection.insufficient);
        expect(find.text('Insufficient data'), findsOneWidget);
        expect(find.text('—'), findsOneWidget);
        expect(find.byIcon(Icons.trending_up_rounded), findsNothing);
        expect(find.byIcon(Icons.trending_down_rounded), findsNothing);
        expect(find.byIcon(Icons.trending_flat_rounded), findsNothing);
      },
    );
  });

  group('risk legend', () {
    testWidgets('labels every level (readable without colour)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: RiskLegend())),
      );
      expect(find.text('Low'), findsOneWidget);
      expect(find.text('Medium'), findsOneWidget);
      expect(find.text('High'), findsOneWidget);
    });
  });
}
