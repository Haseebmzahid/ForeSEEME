import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/core/widgets/app_motion.dart';

void main() {
  group('AppReveal', () {
    testWidgets('renders its child and settles (finite animation)', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AppReveal(child: Text('hello'))),
        ),
      );
      // Findable immediately (only opacity animates), and settles cleanly.
      expect(find.text('hello'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('hello'), findsOneWidget);
    });

    testWidgets('under reduced motion renders the child directly', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            home: Scaffold(body: AppReveal(child: Text('instant'))),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('instant'), findsOneWidget);
      // No TweenAnimationBuilder is inserted when motion is reduced.
      expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
    });
  });

  group('PressableScale', () {
    testWidgets('fires onTap and wraps its child', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PressableScale(
                onTap: () => taps++,
                child: const Text('press'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('press'));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });
  });

  group('AppMotion.stateSwitcher', () {
    testWidgets('renders the current state child', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) =>
                  AppMotion.stateSwitcher(context, const Text('state-a')),
            ),
          ),
        ),
      );
      expect(find.text('state-a'), findsOneWidget);
      expect(find.byType(AnimatedSwitcher), findsOneWidget);
    });
  });
}
