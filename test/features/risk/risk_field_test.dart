import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_field.dart';

/// The Risk Field's visual encoding is a pure function of application state, so
/// the contract that matters — which state produces which field — is tested
/// directly, without pumping a painter.
void main() {
  group('RiskFieldState encoding', () {
    test('each level raises elevation, turbulence and isoline count', () {
      final low = RiskFieldState.forEstimate(
        level: RiskLevel.low,
        confidence: 0.9,
      );
      final medium = RiskFieldState.forEstimate(
        level: RiskLevel.medium,
        confidence: 0.9,
      );
      final high = RiskFieldState.forEstimate(
        level: RiskLevel.high,
        confidence: 0.9,
      );

      expect(low.tone, RiskFieldTone.low);
      expect(medium.tone, RiskFieldTone.moderate);
      expect(high.tone, RiskFieldTone.high);

      // Magnitude, instability and line density all rise together, so the level
      // survives greyscale and colour-blindness on three independent channels.
      expect(low.elevation, lessThan(medium.elevation));
      expect(medium.elevation, lessThan(high.elevation));
      expect(low.turbulence, lessThan(medium.turbulence));
      expect(medium.turbulence, lessThan(high.turbulence));
      expect(low.isolines, lessThan(medium.isolines));
      expect(medium.isolines, lessThan(high.isolines));

      // A classified estimate is never drawn as the "no estimate" lattice.
      for (final state in [low, medium, high]) {
        expect(state.dashed, isFalse);
      }
    });

    test('low confidence renders the lattice whatever the level says', () {
      for (final level in RiskLevel.values) {
        final state = RiskFieldState.forEstimate(
          level: level,
          confidence: 0.30,
          lowConfidence: true,
        );
        expect(
          state.tone,
          RiskFieldTone.unknown,
          reason: 'an unreliable $level estimate must not assert a crest',
        );
        expect(state.dashed, isTrue);
        expect(state.elevation, lessThan(0.2));
      }
    });

    test('unavailable is a different object, not a quiet low', () {
      const unavailable = RiskFieldState.unavailable;
      final low = RiskFieldState.forEstimate(
        level: RiskLevel.low,
        confidence: 0.9,
      );

      expect(unavailable.tone, RiskFieldTone.unknown);
      expect(unavailable.dashed, isTrue);
      // The distinction is structural (dashed, flat), not merely dimmer.
      expect(low.dashed, isFalse);
      expect(unavailable.elevation, lessThan(low.elevation));
      expect(unavailable, isNot(equals(low)));
    });

    test('confidence drives definition, monotonically and never to zero', () {
      expect(RiskFieldState.definitionFor(0.0), 0.35);
      expect(RiskFieldState.definitionFor(1.0), 1.0);
      expect(
        RiskFieldState.definitionFor(0.5),
        greaterThan(RiskFieldState.definitionFor(0.2)),
      );
      // Out-of-range input is clamped rather than producing an invalid field.
      expect(RiskFieldState.definitionFor(-1), 0.35);
      expect(RiskFieldState.definitionFor(2), 1.0);
    });

    test('confidence changes definition but never the level', () {
      final confident = RiskFieldState.forEstimate(
        level: RiskLevel.high,
        confidence: 0.95,
      );
      final unsure = RiskFieldState.forEstimate(
        level: RiskLevel.high,
        confidence: 0.55,
      );

      expect(unsure.definition, lessThan(confident.definition));
      expect(unsure.tone, confident.tone);
      expect(unsure.elevation, confident.elevation);
      expect(unsure.isolines, confident.isolines);
    });

    test('a stale estimate is muted but keeps its shape', () {
      final fresh = RiskFieldState.forEstimate(
        level: RiskLevel.medium,
        confidence: 0.8,
      );
      final stale = RiskFieldState.forEstimate(
        level: RiskLevel.medium,
        confidence: 0.8,
        stale: true,
      );

      expect(fresh.muted, isFalse);
      expect(stale.muted, isTrue);
      expect(stale.elevation, fresh.elevation);
      expect(stale, isNot(equals(fresh)));
    });

    test('equal states are equal (so the painter can skip repaints)', () {
      expect(
        RiskFieldState.forEstimate(level: RiskLevel.low, confidence: 0.7),
        RiskFieldState.forEstimate(level: RiskLevel.low, confidence: 0.7),
      );
      expect(
        RiskFieldState.forEstimate(
          level: RiskLevel.low,
          confidence: 0.7,
        ).hashCode,
        RiskFieldState.forEstimate(
          level: RiskLevel.low,
          confidence: 0.7,
        ).hashCode,
      );
    });
  });

  group('RiskField widget', () {
    Widget host(RiskFieldState state, {required bool animate}) => MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: !animate),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                height: 300,
                child: RiskField(state: state, tint: const Color(0xFF4ADE80)),
              ),
            ),
          ),
        ),
      ),
    );

    testWidgets('paints, and isolates its repaints from the readouts', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          RiskFieldState.forEstimate(level: RiskLevel.high, confidence: 0.88),
          animate: false,
        ),
      );

      // The field paints itself behind its own repaint boundary, so its ambient
      // drift never dirties the readouts stacked above it.
      final boundary = find.descendant(
        of: find.byType(RiskField),
        matching: find.byType(RepaintBoundary),
      );
      expect(boundary, findsOneWidget);
      expect(
        find.descendant(of: boundary, matching: find.byType(CustomPaint)),
        findsOneWidget,
      );
    });

    testWidgets('renders every state without throwing', (tester) async {
      for (final state in [
        RiskFieldState.forEstimate(level: RiskLevel.low, confidence: 0.93),
        RiskFieldState.forEstimate(level: RiskLevel.medium, confidence: 0.82),
        RiskFieldState.forEstimate(level: RiskLevel.high, confidence: 0.88),
        RiskFieldState.forEstimate(
          level: RiskLevel.high,
          confidence: 0.2,
          lowConfidence: true,
        ),
        RiskFieldState.unavailable,
      ]) {
        await tester.pumpWidget(host(state, animate: false));
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('under reduced motion it renders a still — no ticker', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          RiskFieldState.forEstimate(level: RiskLevel.medium, confidence: 0.82),
          animate: false,
        ),
      );

      // A running ticker would keep frames scheduled forever; settling proves
      // the ambient drift really is off rather than merely slower.
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('drifts when motion is allowed, and disposes cleanly', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          RiskFieldState.forEstimate(level: RiskLevel.medium, confidence: 0.82),
          animate: true,
        ),
      );

      // Advance past several ~24fps ticks; the field keeps scheduling frames.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);

      // Tearing the widget down must stop and release the ticker.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      expect(tester.takeException(), isNull);
    });
  });
}
