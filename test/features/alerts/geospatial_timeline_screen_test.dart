import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/features/alerts/domain/models/user_alert.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/alerts_providers.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/geospatial_timeline_screen.dart';

UserAlertModel _alert({
  required String id,
  required String city,
  required String riskLevel,
  required DateTime createdAt,
  bool read = false,
}) => UserAlertModel(
  id: id,
  title: '$riskLevel risk in $city',
  body: 'Body',
  category: 'respiratory',
  city: city,
  riskLevel: riskLevel,
  disease: 'Smog',
  recommendation: null,
  deepLink: '/risk-map',
  riskEstimateId: '$city-$id',
  createdAt: createdAt,
  read: read,
  readAt: null,
);

void main() {
  // `flutter_riverpod` 3.3.1 doesn't export the `Override` type name, so
  // `overrides` stays untyped here — `ProviderScope` performs its own runtime
  // check (mirrors the local-function pattern in pipeline_e2e_test.dart).
  Widget wrap(Widget home, {required dynamic overrides}) => ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    await Navigator.of(context).push<String>(
                      MaterialPageRoute(builder: (_) => home),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('groups alerts by date and shows risk-labelled entries', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 18, 12);
    await tester.pumpWidget(
      wrap(
        const GeospatialTimelineScreen(),
        overrides: [
          userAlertsStreamProvider.overrideWith(
            (ref) => Stream.value([
              _alert(
                id: 'a1',
                city: 'Lahore',
                riskLevel: 'High',
                createdAt: now,
              ),
              _alert(
                id: 'a2',
                city: 'Karachi',
                riskLevel: 'Medium',
                createdAt: now.subtract(const Duration(days: 1)),
              ),
            ]),
          ),
        ],
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('High risk in Lahore'), findsOneWidget);
    expect(find.text('Medium risk in Karachi'), findsOneWidget);
    expect(find.textContaining('Lahore ·'), findsOneWidget);
  });

  testWidgets('empty alerts → empty state, no crash', (tester) async {
    await tester.pumpWidget(
      wrap(
        const GeospatialTimelineScreen(),
        overrides: [
          userAlertsStreamProvider.overrideWith((ref) => Stream.value(const [])),
        ],
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('No activity yet'), findsOneWidget);
  });

  testWidgets('tapping an entry with a city pops that city back', (
    tester,
  ) async {
    String? poppedCity;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userAlertsStreamProvider.overrideWith(
            (ref) => Stream.value([
              _alert(
                id: 'a1',
                city: 'Lahore',
                riskLevel: 'High',
                createdAt: DateTime(2026, 7, 18),
              ),
            ]),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: '/host',
            routes: [
              GoRoute(
                path: '/host',
                builder: (context, state) => Scaffold(
                  body: Builder(
                    builder: (context) => ElevatedButton(
                      onPressed: () async {
                        poppedCity = await context.push<String>('/timeline');
                      },
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
              GoRoute(
                path: '/timeline',
                builder: (context, state) => const GeospatialTimelineScreen(),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('High risk in Lahore'));
    await tester.pumpAndSettle();

    expect(poppedCity, 'Lahore');
  });
}
