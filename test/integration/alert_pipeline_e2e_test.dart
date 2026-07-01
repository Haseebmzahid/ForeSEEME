// End-to-end alert pipeline (Sprint 4, Prompt 9): the "receive → inbox" leg.
//
// The backend engine (`dispatch_alerts._alert_body`) is the only writer of
// `userAlerts/{uid}/items/{logId}`. This test seeds a document with that exact
// frozen shape into a fake Firestore, then drives the REAL Flutter read path
// (`FirestoreUserAlertsRepository` → `userAlertsStreamProvider` →
// `AlertInboxScreen`) to prove the contract end-to-end: a delivered alert
// appears in the owner's inbox, is user-scoped, and unread→read persists back to
// Firestore. It also proves the deep-link engagement hook fires on an inbox tap.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/features/alerts/data/repositories/firestore_user_alerts_repository.dart';
import 'package:fyp_foreseeme/features/alerts/domain/services/alert_analytics.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/alert_inbox_screen.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/alerts_providers.dart';
import 'package:fyp_foreseeme/features/auth/domain/models/user_model.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';

const _logId = 'asthma_ok__Lahore_2026-06-30__respiratory';

UserModel _user(String uid) => UserModel(
  uid: uid,
  email: '$uid@b.com',
  createdAt: DateTime.utc(2026, 1, 1),
);

/// The exact document the backend engine writes on a successful send.
Map<String, dynamic> _engineAlertDoc() => {
  'title': 'Air quality rising in Lahore',
  'body': 'High Smog risk. Limit outdoor activity.',
  'category': 'respiratory',
  'city': 'Lahore',
  'riskLevel': 'High',
  'disease': 'Smog',
  'recommendation': {
    'id': 'rec-resp-air',
    'text': 'Keep windows closed during peak smog.',
    'source': 'WHO — Air pollution',
    'sourceUrl': 'https://www.who.int/health-topics/air-pollution',
  },
  'deepLink': '/resources',
  'riskEstimateId': 'Lahore_2026-06-30',
  'createdAt': Timestamp.fromDate(DateTime.utc(2026, 6, 30, 12)),
  'read': false,
  'readAt': null,
};

class RecordingAnalytics implements AlertAnalytics {
  final opens = <({String route, AlertOpenSource source})>[];
  @override
  void logAlertOpened({
    required String route,
    required AlertOpenSource source,
  }) => opens.add((route: route, source: source));
}

Future<FakeFirebaseFirestore> _seed({String owner = 'asthma_ok'}) async {
  final firestore = FakeFirebaseFirestore();
  await firestore
      .collection('userAlerts')
      .doc(owner)
      .collection('items')
      .doc(_logId)
      .set(_engineAlertDoc());
  return firestore;
}

void main() {
  group('alert pipeline e2e — receive → inbox', () {
    test(
      'delivered engine alert surfaces in the owner inbox, scoped',
      () async {
        final firestore = await _seed();
        // A different user's alert must never leak across.
        await firestore
            .collection('userAlerts')
            .doc('someone_else')
            .collection('items')
            .doc('x')
            .set(_engineAlertDoc());

        final container = ProviderContainer(
          overrides: [
            authStateProvider.overrideWith(
              (ref) => Stream.value(_user('asthma_ok')),
            ),
            userAlertsRepositoryProvider.overrideWithValue(
              FirestoreUserAlertsRepository(firestore: firestore),
            ),
          ],
        );
        addTearDown(container.dispose);
        container.listen(
          userAlertsStreamProvider,
          (_, _) {},
          fireImmediately: true,
        );

        final alerts = await container.read(userAlertsStreamProvider.future);
        expect(alerts, hasLength(1)); // only the owner's alert
        expect(alerts.single.title, 'Air quality rising in Lahore');
        expect(alerts.single.recommendation!.id, 'rec-resp-air');
        expect(container.read(unreadAlertCountProvider), 1);
      },
    );

    test('unread → read persists back to Firestore', () async {
      final firestore = await _seed();
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream.value(_user('asthma_ok')),
          ),
          userAlertsRepositoryProvider.overrideWithValue(
            FirestoreUserAlertsRepository(firestore: firestore),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(
        userAlertsStreamProvider,
        (_, _) {},
        fireImmediately: true,
      );

      await container.read(userAlertsStreamProvider.future);
      await container.read(markAlertReadProvider)(_logId);

      final doc = await firestore
          .collection('userAlerts')
          .doc('asthma_ok')
          .collection('items')
          .doc(_logId)
          .get();
      expect(doc.data()!['read'], isTrue);
      expect(doc.data()!['readAt'], isNotNull);
    });

    testWidgets(
      'inbox renders the engine alert and logs an inbox open on tap',
      (tester) async {
        final firestore = await _seed();
        final analytics = RecordingAnalytics();

        final router = GoRouter(
          initialLocation: '/alerts',
          routes: [
            GoRoute(
              path: '/alerts',
              builder: (_, _) => const AlertInboxScreen(),
            ),
            GoRoute(
              path: '/resources',
              builder: (_, _) => const Scaffold(body: Text('Resources')),
            ),
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authStateProvider.overrideWith(
                (ref) => Stream.value(_user('asthma_ok')),
              ),
              userAlertsRepositoryProvider.overrideWithValue(
                FirestoreUserAlertsRepository(firestore: firestore),
              ),
              alertAnalyticsProvider.overrideWithValue(analytics),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Air quality rising in Lahore'), findsOneWidget);
        expect(find.text('Source: WHO — Air pollution'), findsOneWidget);

        await tester.tap(find.text('Air quality rising in Lahore'));
        await tester.pumpAndSettle();

        // Engagement hook fired for the inbox open, and it navigated.
        expect(analytics.opens.single.source, AlertOpenSource.inbox);
        expect(analytics.opens.single.route, '/resources');
        expect(find.text('Resources'), findsOneWidget);
      },
    );
  });
}
