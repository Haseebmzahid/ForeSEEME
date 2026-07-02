import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/core/widgets/brand_loading.dart';

void main() {
  group('BrandLoading', () {
    testWidgets('renders the branded mark instead of a spinner', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: BrandLoading())),
      );
      await tester.pump(); // let the fade-in begin

      expect(find.byType(BrandLoading), findsOneWidget);
      // Never a CircularProgressIndicator — this is the branded replacement.
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows the optional message and announces it to a11y', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: BrandLoading(message: 'Loading your risk…')),
        ),
      );
      await tester.pump();

      expect(find.text('Loading your risk…'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Loading. Loading your risk…'),
        findsOneWidget,
      );
    });

    testWidgets('announces plain "Loading" when no message is given', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: BrandLoading())),
      );
      await tester.pump();

      expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    });

    testWidgets('holds still and settles under reduced motion', (tester) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MaterialApp(home: Scaffold(body: BrandLoading())),
        ),
      );
      // With animations disabled the tree must settle (no perpetual pulse),
      // otherwise pumpAndSettle would time out.
      await tester.pumpAndSettle();

      expect(find.byType(BrandLoading), findsOneWidget);
    });
  });
}
