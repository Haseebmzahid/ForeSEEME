import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/widgets/timeline_row.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: ForeSeeMeTheme.light,
    home: Scaffold(body: child),
  );

  testWidgets('renders eyebrow, title and subtitle', (tester) async {
    await tester.pumpWidget(
      wrap(
        const TimelineRow(
          eyebrow: 'Morning',
          title: 'Medication completed',
          subtitle: 'Ventolin',
          icon: Icons.check_rounded,
          color: Colors.green,
          isLast: false,
        ),
      ),
    );

    expect(find.text('Morning'), findsOneWidget);
    expect(find.text('Medication completed'), findsOneWidget);
    expect(find.text('Ventolin'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });

  testWidgets('omits the eyebrow when null', (tester) async {
    await tester.pumpWidget(
      wrap(
        const TimelineRow(
          title: 'High AQI detected',
          icon: Icons.air_rounded,
          color: Colors.orange,
          isLast: true,
        ),
      ),
    );

    expect(find.text('High AQI detected'), findsOneWidget);
  });

  testWidgets('tappable when onTap is set, fires on tap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      wrap(
        TimelineRow(
          title: 'Outbreak reported',
          icon: Icons.warning_amber_rounded,
          color: Colors.red,
          isLast: true,
          onTap: () => tapped = true,
        ),
      ),
    );

    await tester.tap(find.text('Outbreak reported'));
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets('not tappable when onTap is null', (tester) async {
    await tester.pumpWidget(
      wrap(
        const TimelineRow(
          title: 'Area stabilized',
          icon: Icons.check_rounded,
          color: Colors.green,
          isLast: true,
        ),
      ),
    );

    expect(find.byType(InkWell), findsNothing);
  });
}
