import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/core/theme/app_design_v2.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/staleness_indicator.dart';

Widget _host(DateTime generatedAt, {DateTime? now}) => MaterialApp(
  home: Scaffold(
    backgroundColor: AppColorsV2.shell,
    body: Center(
      child: RiskStalenessNotice(generatedAt: generatedAt, now: now),
    ),
  ),
);

void main() {
  final now = DateTime.utc(2026, 7, 2, 12);

  testWidgets('a stale estimate renders the labelled amber notice', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(now.subtract(const Duration(days: 30)), now: now),
    );

    // Never colour-only: the notice pairs an icon with the honest text.
    expect(find.text(RiskStalenessNotice.message), findsOneWidget);
    expect(find.byIcon(Icons.history_toggle_off_rounded), findsOneWidget);
  });

  testWidgets('a fresh estimate collapses to nothing', (tester) async {
    await tester.pumpWidget(
      _host(now.subtract(const Duration(days: 2)), now: now),
    );

    expect(find.text(RiskStalenessNotice.message), findsNothing);
    expect(find.byIcon(Icons.history_toggle_off_rounded), findsNothing);
    // Self-guarding: the widget shrinks away entirely when fresh.
    expect(tester.getSize(find.byType(RiskStalenessNotice)), Size.zero);
  });
}
