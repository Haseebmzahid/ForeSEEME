import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/core/theme/a11y.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_palette.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
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

  // ── Risk colours meet AA on the surface they're actually drawn on ──────────
  group('risk colours on the ForeSeeMe surface', () {
    // RiskVisuals' static (brightness-independent) appearances are sourced
    // from the dark palette's semantic tokens (see risk_visuals.dart).
    final bg = ForeSeeMePalette.dark.background;

    test('every risk colour meets AA as a label/icon (4.5:1)', () {
      for (final a in [
        RiskVisuals.low,
        RiskVisuals.medium,
        RiskVisuals.high,
        RiskVisuals.uncertain,
      ]) {
        final ratio = A11y.contrastRatio(a.color, bg);
        expect(
          ratio,
          greaterThanOrEqualTo(A11y.aaText),
          reason: 'risk ${a.label} = ${ratio.toStringAsFixed(2)}:1 '
              '(needs ${A11y.aaText}:1)',
        );
      }
    });
  });

  // ── Reduced-transparency fallback (ForeSeeMeSurface, the one glass-card
  // recipe every screen now shares) ───────────────────────────────────────────
  group('reduced-transparency fallback', () {
    Future<BuildContext> contextWith(WidgetTester tester, bool highContrast) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          theme: ForeSeeMeTheme.dark,
          home: MediaQuery(
            data: MediaQueryData(highContrast: highContrast),
            child: Builder(
              builder: (context) {
                ctx = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      return ctx;
    }

    testWidgets('normal: translucent glass, blurred', (tester) async {
      final ctx = await contextWith(tester, false);
      expect(A11y.reduceTransparency(ctx), isFalse);
      expect(ForeSeeMeSurface.fill(ctx).a, lessThan(1.0)); // translucent
      expect(A11y.blurSigma(ctx, sigma: 16), 16);
    });

    testWidgets('high contrast: opaque solid fill, no blur, stronger stroke', (
      tester,
    ) async {
      final normalCtx = await contextWith(tester, false);
      final normalStroke = ForeSeeMeSurface.stroke(normalCtx).a;

      final ctx = await contextWith(tester, true);
      expect(A11y.reduceTransparency(ctx), isTrue);
      expect(ForeSeeMeSurface.fill(ctx).a, 1.0); // fully opaque
      expect(A11y.blurSigma(ctx, sigma: 16), 0); // blur dropped
      expect(ForeSeeMeSurface.stroke(ctx).a, greaterThan(normalStroke));
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
                backgroundColor: Colors.black,
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
