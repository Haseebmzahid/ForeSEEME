import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/core/widgets/error_state.dart';

void main() {
  group('ErrorState', () {
    testWidgets('shows title, explanation, Retry — and no loading spinner', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ErrorState(
              title: "Couldn't load",
              explanation: 'Something went wrong. Please try again.',
              onRetry: () {},
            ),
          ),
        ),
      );

      expect(find.text("Couldn't load"), findsOneWidget);
      expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      // Error is not loading — never a spinner.
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('Retry invokes the provided callback', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ErrorState(
              title: 'Oops',
              explanation: 'x',
              onRetry: () => taps++,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Retry'));
      expect(taps, 1);
    });

    testWidgets('technical detail is hidden until toggled', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ErrorState(
              title: 'Oops',
              explanation: 'x',
              onRetry: () {},
              detail: 'StateError: bad state at line 42',
            ),
          ),
        ),
      );

      // Collapsed by default: the toggle shows, the raw detail does not.
      expect(find.text('Technical details'), findsOneWidget);
      expect(find.text('StateError: bad state at line 42'), findsNothing);

      await tester.tap(find.text('Technical details'));
      await tester.pump();

      expect(find.text('StateError: bad state at line 42'), findsOneWidget);
      expect(find.text('Hide details'), findsOneWidget);
    });

    testWidgets('no detail → no disclosure toggle', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ErrorState(title: 'Oops', explanation: 'x', onRetry: () {}),
          ),
        ),
      );

      expect(find.text('Technical details'), findsNothing);
    });
  });
}
