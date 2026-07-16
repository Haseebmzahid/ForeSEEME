import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/features/health_profile/presentation/profile_ready_screen.dart';

Future<void> _pump(
  WidgetTester tester, {
  required String city,
  required List<String> conditions,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ProfileReadyScreen(city: city, conditions: conditions),
    ),
  );
}

void main() {
  group('ProfileReadyScreen (S6C-04)', () {
    testWidgets('shows the real saved city, never a placeholder', (
      tester,
    ) async {
      await _pump(tester, city: 'Karachi', conditions: const ['Asthma']);

      expect(find.textContaining('Karachi'), findsWidgets);
    });

    testWidgets('names the real selected conditions', (tester) async {
      await _pump(
        tester,
        city: 'Lahore',
        conditions: const ['Asthma', 'Diabetes'],
      );

      expect(find.textContaining('Asthma'), findsWidgets);
      expect(find.textContaining('Diabetes'), findsWidgets);
    });

    testWidgets(
      '"None" is phrased honestly, never shown as a literal condition name',
      (tester) async {
        await _pump(tester, city: 'Lahore', conditions: const ['None']);

        expect(
          find.textContaining("You didn't note any chronic conditions"),
          findsOneWidget,
        );
        // The word "None" must not appear as if it were a real condition.
        expect(find.text('None'), findsNothing);
      },
    );

    testWidgets('an empty conditions list is phrased the same honest way', (
      tester,
    ) async {
      await _pump(tester, city: 'Lahore', conditions: const []);

      expect(
        find.textContaining("You didn't note any chronic conditions"),
        findsOneWidget,
      );
    });

    testWidgets('never claims specific diseases are monitored', (tester) async {
      // The app cannot know which diseases actually have data for a city at
      // profile-save time (that's derived from historical riskEstimates, a
      // separate weekly-computed collection) — so this screen must never
      // fabricate disease names, only reference the real city.
      await _pump(tester, city: 'Peshawar', conditions: const []);

      for (final disease in ['Dengue', 'ILI', 'Smog', 'Malaria']) {
        expect(find.textContaining(disease), findsNothing);
      }
    });

    testWidgets('the Continue button pushReplace-s to the permission screen', (
      tester,
    ) async {
      final router = GoRouter(
        initialLocation: '/profile-ready',
        routes: [
          GoRoute(
            path: '/profile-ready',
            builder: (context, state) =>
                const ProfileReadyScreen(city: 'Lahore', conditions: ['None']),
          ),
          GoRoute(
            path: '/notifications/permission',
            builder: (context, state) =>
                const Scaffold(body: Text('PERMISSION_SCREEN_STUB')),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('PERMISSION_SCREEN_STUB'), findsOneWidget);
      // pushReplacement, not push: the ready screen is gone from history,
      // not just covered — popping the permission screen must not return
      // to it (matches S6C-02's existing "pop lands on /health-profile,
      // then the router redirect finishes the job" mechanic).
      expect(find.byType(ProfileReadyScreen), findsNothing);
    });
  });
}
