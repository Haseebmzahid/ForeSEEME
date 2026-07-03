import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/core/theme/a11y.dart';
import 'package:fyp_foreseeme/core/theme/app_design_v2.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/trend_direction.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_override_provider.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_card.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_visuals.dart';

void main() {
  // ── WCAG maths sanity (the audit's measuring stick is itself correct) ──────
  group('A11y contrast maths', () {
    test('luminance anchors: black = 0, white = 1', () {
      expect(A11y.relativeLuminance(const Color(0xFF000000)), closeTo(0, 1e-6));
      expect(A11y.relativeLuminance(const Color(0xFFFFFFFF)), closeTo(1, 1e-6));
    });

    test('black-on-white contrast is the canonical 21:1', () {
      expect(
        A11y.contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
        closeTo(21, 0.1),
      );
    });

    test('compositeOver flattens a translucent fill onto an opaque base', () {
      // White @ 50% over black → mid grey (~128).
      final c = A11y.compositeOver(const Color(0x80FFFFFF), const Color(0xFF000000));
      expect(c.a, 1.0);
      expect((c.r * 255).round(), closeTo(128, 2));
    });
  });

  // ── Contrast on the glass surface (audit M4) ───────────────────────────────
  group('text & risk colours on the glass surface', () {
    final bg = A11y.glassSurface; // glassFill composited over the shell

    void expectAtLeast(String name, Color fg, double min) {
      final ratio = A11y.contrastRatio(fg, bg);
      expect(
        ratio,
        greaterThanOrEqualTo(min),
        reason: '$name on glass = ${ratio.toStringAsFixed(2)}:1 (needs $min:1)',
      );
    }

    test('body text tiers meet AA (4.5:1)', () {
      expectAtLeast('textPrimary', AppColorsV2.textPrimary, 7.0); // near-AAA
      expectAtLeast('textSecondary', AppColorsV2.textSecondary, A11y.aaText);
      expectAtLeast('textTertiary', AppColorsV2.textTertiary, A11y.aaText);
      expectAtLeast('textFaint', AppColorsV2.textFaint, A11y.aaText);
    });

    test('every risk colour meets AA as a label/icon (4.5:1)', () {
      for (final a in [
        RiskVisuals.low,
        RiskVisuals.medium,
        RiskVisuals.high,
        RiskVisuals.uncertain,
      ]) {
        expectAtLeast('risk ${a.label}', a.color, A11y.aaText);
      }
    });

    test('the interactive teal meets the UI-component threshold (3:1)', () {
      expectAtLeast('teal', AppColorsV2.teal, A11y.aaLargeText);
    });
  });

  // ── Reduced-transparency fallback ──────────────────────────────────────────
  group('reduced-transparency fallback', () {
    Future<BuildContext> contextWith(WidgetTester tester, bool highContrast) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(highContrast: highContrast),
          child: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox();
            },
          ),
        ),
      );
      return ctx;
    }

    testWidgets('normal: translucent glass, blurred', (tester) async {
      final ctx = await contextWith(tester, false);
      expect(A11y.reduceTransparency(ctx), isFalse);
      expect(A11y.glassFill(ctx), AppColorsV2.glassFill); // translucent
      expect(A11y.glassFill(ctx).a, lessThan(1.0));
      expect(A11y.blurSigma(ctx, sigma: 16), 16);
    });

    testWidgets('high contrast: opaque solid fill, no blur, stronger stroke', (
      tester,
    ) async {
      final ctx = await contextWith(tester, true);
      expect(A11y.reduceTransparency(ctx), isTrue);
      expect(A11y.glassFill(ctx).a, 1.0); // fully opaque
      expect(A11y.blurSigma(ctx, sigma: 16), 0); // blur dropped
      expect(A11y.stroke(ctx).a, greaterThan(AppColorsV2.stroke.a));
    });
  });

  // ── Risk is never colour-only, even under reduced motion ───────────────────
  group('risk encoding: label + icon (reduced-motion path)', () {
    RiskEstimateModel highEstimate() => RiskEstimateModel(
      city: 'Lahore',
      riskLevel: RiskLevel.high,
      disease: 'Smog',
      confidence: 0.9,
      temperature: 34,
      humidity: 55,
      aqi: 210,
      generatedAt: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
      modelVersion: 'rf-1.0.0',
    );

    testWidgets('RiskCard shows a label AND a distinct icon with motion off', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentCityRiskProvider.overrideWith((ref) async => highEstimate()),
            currentCityOverrideProvider.overrideWith((ref) async => null),
            riskTrendProvider.overrideWith((ref) async => TrendDirection.rising),
          ],
          child: const MediaQuery(
            data: MediaQueryData(disableAnimations: true), // reduced motion
            child: MaterialApp(
              home: Scaffold(
                backgroundColor: AppColorsV2.shell,
                body: Center(child: RiskCard()),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Text label + a distinct glyph — never colour alone; renders fully with
      // animations disabled (no information is motion-dependent).
      expect(find.text('High Risk'), findsOneWidget);
      expect(find.byIcon(RiskVisuals.high.icon), findsWidgets);
    });
  });
}
