import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/core/widgets/empty_state.dart';

void main() {
  group('EmptyState', () {
    testWidgets('renders icon, title, description — and no loading spinner', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyState(
              icon: Icons.inbox_outlined,
              title: 'Nothing here yet',
              description: 'Items will show up once there are some.',
            ),
          ),
        ),
      );

      expect(find.text('Nothing here yet'), findsOneWidget);
      expect(find.text('Items will show up once there are some.'), findsOneWidget);
      expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
      // Empty is not loading — never a spinner.
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows the optional CTA and fires its callback', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmptyState(
              icon: Icons.inbox_outlined,
              title: 'Empty',
              description: 'Add one to begin.',
              actionLabel: 'Add item',
              onAction: () => taps++,
            ),
          ),
        ),
      );

      expect(find.text('Add item'), findsOneWidget);
      await tester.tap(find.text('Add item'));
      expect(taps, 1);
    });

    testWidgets('no CTA renders when only a label (no callback) is given', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyState(
              icon: Icons.inbox_outlined,
              title: 'Empty',
              description: 'Nothing to do.',
              actionLabel: 'Add item',
            ),
          ),
        ),
      );

      expect(find.widgetWithText(OutlinedButton, 'Add item'), findsNothing);
    });

    testWidgets('a custom illustration replaces the default glyph', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyState(
              icon: Icons.inbox_outlined,
              illustration: Icon(Icons.rocket_launch_rounded),
              title: 'Empty',
              description: 'Custom art above.',
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.rocket_launch_rounded), findsOneWidget);
      expect(find.byIcon(Icons.inbox_outlined), findsNothing);
    });
  });
}
