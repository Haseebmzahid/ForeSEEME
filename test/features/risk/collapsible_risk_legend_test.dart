import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/collapsible_risk_legend.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: ForeSeeMeTheme.light,
    home: Scaffold(body: child),
  );

  testWidgets('starts collapsed when initiallyExpanded is false', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(const CollapsibleRiskLegend(initiallyExpanded: false)),
    );

    expect(find.text('RISK LEVEL'), findsNothing);
    expect(find.byIcon(Icons.palette_outlined), findsOneWidget);
  });

  testWidgets('tapping expands to the full legend', (tester) async {
    await tester.pumpWidget(
      wrap(const CollapsibleRiskLegend(initiallyExpanded: false)),
    );

    await tester.tap(find.byIcon(Icons.palette_outlined));
    await tester.pumpAndSettle();

    // Labels are the approved Risk Map prototype's tracked mono form, and the
    // legend now also names the uncertain level the field can draw.
    expect(find.text('RISK LEVEL'), findsOneWidget);
    expect(find.text('LOW'), findsOneWidget);
    expect(find.text('MEDIUM'), findsOneWidget);
    expect(find.text('HIGH'), findsOneWidget);
    expect(find.text('UNKNOWN'), findsOneWidget);
  });

  testWidgets('tapping again collapses back to the icon', (tester) async {
    await tester.pumpWidget(
      wrap(const CollapsibleRiskLegend(initiallyExpanded: true)),
    );
    expect(find.text('RISK LEVEL'), findsOneWidget);

    await tester.tap(find.text('RISK LEVEL'));
    await tester.pumpAndSettle();

    expect(find.text('RISK LEVEL'), findsNothing);
    expect(find.byIcon(Icons.palette_outlined), findsOneWidget);
  });
}
