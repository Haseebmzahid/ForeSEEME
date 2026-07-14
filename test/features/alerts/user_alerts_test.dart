import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/alerts/data/repositories/firestore_user_alerts_repository.dart';
import 'package:fyp_foreseeme/features/alerts/domain/models/user_alert.dart';
import 'package:fyp_foreseeme/features/alerts/domain/repositories/user_alerts_repository.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/alert_inbox_screen.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/alerts_providers.dart';
import 'package:fyp_foreseeme/features/auth/domain/models/user_model.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';

UserModel _user([String uid = 'u1']) =>
    UserModel(uid: uid, email: 'a@b.com', createdAt: DateTime.utc(2026, 1, 1));

/// Builds a fully-populated inbox document body (frozen §4.2 shape).
Map<String, dynamic> _alertBody({
  required String title,
  required DateTime createdAt,
  bool read = false,
  String riskLevel = 'High',
  String deepLink = '/resources',
}) => {
  'title': title,
  'body': 'Air quality is rising.',
  'category': 'respiratory',
  'city': 'Lahore',
  'riskLevel': riskLevel,
  'disease': 'Smog',
  'recommendation': {
    'id': 'rec_air_respiratory',
    'text': 'Limit outdoor activity and keep windows closed.',
    'source': 'WHO',
    'sourceUrl': 'https://who.int',
  },
  'deepLink': deepLink,
  'riskEstimateId': 'Lahore_2026-06-30',
  'createdAt': Timestamp.fromDate(createdAt),
  'read': read,
  'readAt': null,
};

UserAlertModel _model({
  String id = 'a1',
  String title = 'Air quality rising in Lahore',
  bool read = false,
  String deepLink = '',
}) => UserAlertModel.fromJson(
  id,
  _alertBody(
    title: title,
    createdAt: DateTime.utc(2026, 6, 30),
    read: read,
    deepLink: deepLink,
  ),
);

/// In-memory inbox repo that records mark-read and re-emits the updated list.
class RecordingUserAlertsRepository implements UserAlertsRepository {
  RecordingUserAlertsRepository(this._alerts);

  List<UserAlertModel> _alerts;
  final _controller = StreamController<List<UserAlertModel>>.broadcast();
  final List<String> markedRead = [];

  @override
  Stream<List<UserAlertModel>> watchAlerts(String uid) async* {
    yield _alerts;
    yield* _controller.stream;
  }

  @override
  Future<void> markRead(String uid, String alertId) async {
    markedRead.add(alertId);
    _alerts = [
      for (final a in _alerts)
        if (a.id == alertId)
          UserAlertModel(
            id: a.id,
            title: a.title,
            body: a.body,
            category: a.category,
            city: a.city,
            riskLevel: a.riskLevel,
            disease: a.disease,
            recommendation: a.recommendation,
            deepLink: a.deepLink,
            riskEstimateId: a.riskEstimateId,
            createdAt: a.createdAt,
            read: true,
            readAt: DateTime.utc(2026, 6, 30, 12),
          )
        else
          a,
    ];
    _controller.add(_alerts);
  }

  @override
  Future<void> markAllRead(String uid) async {
    _alerts = [
      for (final a in _alerts)
        if (!a.read)
          UserAlertModel(
            id: a.id,
            title: a.title,
            body: a.body,
            category: a.category,
            city: a.city,
            riskLevel: a.riskLevel,
            disease: a.disease,
            recommendation: a.recommendation,
            deepLink: a.deepLink,
            riskEstimateId: a.riskEstimateId,
            createdAt: a.createdAt,
            read: true,
            readAt: DateTime.utc(2026, 6, 30, 12),
          )
        else
          a,
    ];
    markedAllRead++;
    _controller.add(_alerts);
  }

  int markedAllRead = 0;

  void dispose() => _controller.close();
}

void main() {
  group('UserAlertModel serialization', () {
    test('fromJson parses every field including nested recommendation', () {
      final m = UserAlertModel.fromJson(
        'u1__Lahore_2026-06-30__respiratory',
        _alertBody(
          title: 'Air quality rising in Lahore',
          createdAt: DateTime.utc(2026, 6, 30, 8),
        ),
      );

      expect(m.id, 'u1__Lahore_2026-06-30__respiratory');
      expect(m.title, 'Air quality rising in Lahore');
      expect(m.category, 'respiratory');
      expect(m.city, 'Lahore');
      expect(m.riskLevel, 'High');
      expect(m.deepLink, '/resources');
      expect(m.read, isFalse);
      expect(m.readAt, isNull);
      // Timestamp.toDate() yields a local DateTime; compare the instant.
      expect(
        m.createdAt!.isAtSameMomentAs(DateTime.utc(2026, 6, 30, 8)),
        isTrue,
      );
      expect(m.recommendation, isNotNull);
      expect(m.recommendation!.source, 'WHO');
      expect(m.recommendation!.id, 'rec_air_respiratory');
    });

    test('fromJson tolerates a missing recommendation and null timestamps', () {
      final m = UserAlertModel.fromJson('a2', {'title': 't', 'read': true});
      expect(m.recommendation, isNull);
      expect(m.createdAt, isNull);
      expect(m.read, isTrue);
    });

    test('toJson round-trips through fromJson', () {
      final original = _model(read: true);
      final restored = UserAlertModel.fromJson(original.id, original.toJson());
      expect(restored, original);
      expect(restored.recommendation, original.recommendation);
    });
  });

  group('FirestoreUserAlertsRepository', () {
    test('watchAlerts streams the user\'s alerts newest first', () async {
      final firestore = FakeFirebaseFirestore();
      final items = firestore
          .collection('userAlerts')
          .doc('u1')
          .collection('items');
      await items
          .doc('older')
          .set(
            _alertBody(title: 'Older', createdAt: DateTime.utc(2026, 6, 28)),
          );
      await items
          .doc('newer')
          .set(
            _alertBody(title: 'Newer', createdAt: DateTime.utc(2026, 6, 30)),
          );

      final repo = FirestoreUserAlertsRepository(firestore: firestore);
      final alerts = await repo.watchAlerts('u1').first;

      expect(alerts.map((a) => a.title), ['Newer', 'Older']);
    });

    test('watchAlerts only returns the caller\'s own alerts', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore
          .collection('userAlerts')
          .doc('u1')
          .collection('items')
          .doc('mine')
          .set(_alertBody(title: 'Mine', createdAt: DateTime.utc(2026, 6, 30)));
      await firestore
          .collection('userAlerts')
          .doc('u2')
          .collection('items')
          .doc('theirs')
          .set(
            _alertBody(title: 'Theirs', createdAt: DateTime.utc(2026, 6, 30)),
          );

      final repo = FirestoreUserAlertsRepository(firestore: firestore);
      final alerts = await repo.watchAlerts('u1').first;

      expect(alerts.map((a) => a.title), ['Mine']);
    });

    test('markRead persists read=true and a readAt timestamp', () async {
      final firestore = FakeFirebaseFirestore();
      final items = firestore
          .collection('userAlerts')
          .doc('u1')
          .collection('items');
      await items
          .doc('a1')
          .set(_alertBody(title: 'A', createdAt: DateTime.utc(2026, 6, 30)));

      final repo = FirestoreUserAlertsRepository(firestore: firestore);
      await repo.markRead('u1', 'a1');

      final doc = await items.doc('a1').get();
      expect(doc.data()!['read'], isTrue);
      expect(doc.data()!['readAt'], isNotNull);
    });

    test(
      'markAllRead marks every unread doc read and leaves read docs alone '
      '(S6A-02)',
      () async {
        final firestore = FakeFirebaseFirestore();
        final items = firestore
            .collection('userAlerts')
            .doc('u1')
            .collection('items');
        await items
            .doc('unread1')
            .set(
              _alertBody(
                title: 'Unread 1',
                createdAt: DateTime.utc(2026, 6, 28),
                read: false,
              ),
            );
        await items
            .doc('unread2')
            .set(
              _alertBody(
                title: 'Unread 2',
                createdAt: DateTime.utc(2026, 6, 29),
                read: false,
              ),
            );
        await items
            .doc('alreadyRead')
            .set(
              _alertBody(
                title: 'Already read',
                createdAt: DateTime.utc(2026, 6, 27),
                read: true,
              ),
            );

        final repo = FirestoreUserAlertsRepository(firestore: firestore);
        await repo.markAllRead('u1');

        final alerts = await repo.watchAlerts('u1').first;
        expect(alerts.every((a) => a.read), isTrue);
        expect(
          alerts.firstWhere((a) => a.id == 'unread1').readAt,
          isNotNull,
        );
        expect(
          alerts.firstWhere((a) => a.id == 'unread2').readAt,
          isNotNull,
        );
      },
    );

    test('markAllRead only touches the calling user\'s own alerts', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore
          .collection('userAlerts')
          .doc('u1')
          .collection('items')
          .doc('mine')
          .set(
            _alertBody(
              title: 'Mine',
              createdAt: DateTime.utc(2026, 6, 30),
              read: false,
            ),
          );
      await firestore
          .collection('userAlerts')
          .doc('u2')
          .collection('items')
          .doc('theirs')
          .set(
            _alertBody(
              title: 'Theirs',
              createdAt: DateTime.utc(2026, 6, 30),
              read: false,
            ),
          );

      final repo = FirestoreUserAlertsRepository(firestore: firestore);
      await repo.markAllRead('u1');

      final theirsDoc = await firestore
          .collection('userAlerts')
          .doc('u2')
          .collection('items')
          .doc('theirs')
          .get();
      expect(theirsDoc.data()!['read'], isFalse);
    });

    test('markAllRead is a no-op when nothing is unread', () async {
      final firestore = FakeFirebaseFirestore();
      final items = firestore
          .collection('userAlerts')
          .doc('u1')
          .collection('items');
      await items
          .doc('a1')
          .set(
            _alertBody(
              title: 'Already read',
              createdAt: DateTime.utc(2026, 6, 30),
              read: true,
            ),
          );

      final repo = FirestoreUserAlertsRepository(firestore: firestore);
      await repo.markAllRead('u1'); // must not throw on an empty batch

      final doc = await items.doc('a1').get();
      expect(doc.data()!['read'], isTrue);
    });
  });

  group('inbox providers', () {
    test('userAlertsStreamProvider is empty when signed out', () async {
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((ref) => Stream.value(null)),
        ],
      );
      addTearDown(container.dispose);
      container.listen(
        userAlertsStreamProvider,
        (_, _) {},
        fireImmediately: true,
      );

      final alerts = await container.read(userAlertsStreamProvider.future);
      expect(alerts, isEmpty);
    });

    test(
      'userAlertsStreamProvider streams the signed-in user\'s alerts',
      () async {
        final repo = RecordingUserAlertsRepository([_model(title: 'Hi')]);
        addTearDown(repo.dispose);

        final container = ProviderContainer(
          overrides: [
            authStateProvider.overrideWith((ref) => Stream.value(_user())),
            userAlertsRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(container.dispose);
        container.listen(
          userAlertsStreamProvider,
          (_, _) {},
          fireImmediately: true,
        );

        final alerts = await container.read(userAlertsStreamProvider.future);
        expect(alerts.single.title, 'Hi');
      },
    );

    test('unreadAlertCountProvider counts only unread alerts', () async {
      final repo = RecordingUserAlertsRepository([
        _model(id: 'a1', read: false),
        _model(id: 'a2', read: true),
        _model(id: 'a3', read: false),
      ]);
      addTearDown(repo.dispose);

      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((ref) => Stream.value(_user())),
          userAlertsRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      container.listen(
        userAlertsStreamProvider,
        (_, _) {},
        fireImmediately: true,
      );

      // Resolve the stream first so the derived count sees data.
      await container.read(userAlertsStreamProvider.future);
      expect(container.read(unreadAlertCountProvider), 2);
    });

    test(
      'markAlertReadProvider marks the alert read via the repository',
      () async {
        final repo = RecordingUserAlertsRepository([_model(id: 'a1')]);
        addTearDown(repo.dispose);

        final container = ProviderContainer(
          overrides: [
            authStateProvider.overrideWith((ref) => Stream.value(_user())),
            userAlertsRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(container.dispose);
        container.listen(
          userAlertsStreamProvider,
          (_, _) {},
          fireImmediately: true,
        );

        await container.read(userAlertsStreamProvider.future);
        await container.read(markAlertReadProvider)('a1');

        expect(repo.markedRead, ['a1']);
      },
    );

    test(
      'markAllAlertsReadProvider marks every alert read via the repository '
      '(S6A-02)',
      () async {
        final repo = RecordingUserAlertsRepository([
          _model(id: 'a1', read: false),
          _model(id: 'a2', read: false),
        ]);
        addTearDown(repo.dispose);

        final container = ProviderContainer(
          overrides: [
            authStateProvider.overrideWith((ref) => Stream.value(_user())),
            userAlertsRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(container.dispose);
        container.listen(
          userAlertsStreamProvider,
          (_, _) {},
          fireImmediately: true,
        );

        await container.read(userAlertsStreamProvider.future);
        await container.read(markAllAlertsReadProvider)();

        expect(repo.markedAllRead, 1);
        // Query the repository directly (a fresh subscription) rather than
        // re-reading userAlertsStreamProvider.future: the provider's cached
        // future can still reflect the pre-mutation snapshot for a
        // microtask, since the fake's stream update and Riverpod's rebuild
        // are both async. The repository itself is the source of truth here.
        final alerts = await repo.watchAlerts('u1').first;
        expect(alerts.every((a) => a.read), isTrue);
      },
    );

    test(
      'markAllAlertsReadProvider no-ops when signed out',
      () async {
        final repo = RecordingUserAlertsRepository([
          _model(id: 'a1', read: false),
        ]);
        addTearDown(repo.dispose);

        final container = ProviderContainer(
          overrides: [
            authStateProvider.overrideWith((ref) => Stream.value(null)),
            userAlertsRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(container.dispose);

        await container.read(markAllAlertsReadProvider)();

        expect(repo.markedAllRead, 0);
      },
    );

    test(
      'markAlertReadFromPushProvider reconstructs the id and marks it read '
      '(S6A-01)',
      () async {
        final repo = RecordingUserAlertsRepository([
          _model(id: 'u1__Lahore_2026-06-30__respiratory'),
        ]);
        addTearDown(repo.dispose);

        final container = ProviderContainer(
          overrides: [
            authStateProvider.overrideWith((ref) => Stream.value(_user())),
            userAlertsRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(container.dispose);
        container.listen(
          userAlertsStreamProvider,
          (_, _) {},
          fireImmediately: true,
        );

        await container.read(userAlertsStreamProvider.future);
        await container.read(markAlertReadFromPushProvider)({
          'type': 'risk_alert',
          'riskEstimateId': 'Lahore_2026-06-30',
          'category': 'respiratory',
          'city': 'Lahore',
        });

        expect(repo.markedRead, ['u1__Lahore_2026-06-30__respiratory']);
      },
    );

    test(
      'markAlertReadFromPushProvider no-ops on an unresolvable payload',
      () async {
        final repo = RecordingUserAlertsRepository([_model(id: 'a1')]);
        addTearDown(repo.dispose);

        final container = ProviderContainer(
          overrides: [
            authStateProvider.overrideWith((ref) => Stream.value(_user())),
            userAlertsRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(container.dispose);

        await container.read(markAlertReadFromPushProvider)({
          'type': 'weekly_report',
        });

        expect(repo.markedRead, isEmpty);
      },
    );

    test(
      'markAlertReadFromPushProvider no-ops when signed out',
      () async {
        final repo = RecordingUserAlertsRepository([_model(id: 'a1')]);
        addTearDown(repo.dispose);

        final container = ProviderContainer(
          overrides: [
            authStateProvider.overrideWith((ref) => Stream.value(null)),
            userAlertsRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(container.dispose);

        await container.read(markAlertReadFromPushProvider)({
          'riskEstimateId': 'Lahore_2026-06-30',
          'category': 'respiratory',
        });

        expect(repo.markedRead, isEmpty);
      },
    );
  });

  group('AlertInboxScreen', () {
    Widget wrap(ProviderContainer container) => UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AlertInboxScreen()),
    );

    testWidgets('renders the empty state when there are no alerts', (
      tester,
    ) async {
      final repo = RecordingUserAlertsRepository(const []);
      addTearDown(repo.dispose);
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((ref) => Stream.value(_user())),
          userAlertsRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(wrap(container));
      await tester.pumpAndSettle();

      expect(find.text('No alerts yet'), findsOneWidget);
    });

    testWidgets('lists delivered alerts with their cited source', (
      tester,
    ) async {
      final repo = RecordingUserAlertsRepository([
        _model(title: 'Air quality rising in Lahore'),
      ]);
      addTearDown(repo.dispose);
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((ref) => Stream.value(_user())),
          userAlertsRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(wrap(container));
      await tester.pumpAndSettle();

      expect(find.text('Air quality rising in Lahore'), findsOneWidget);
      expect(find.text('Source: WHO'), findsOneWidget);
    });

    testWidgets('tapping an alert marks it read', (tester) async {
      // deepLink '' is not a known route, so no navigation is attempted.
      final repo = RecordingUserAlertsRepository([
        _model(id: 'a1', title: 'Tap me', deepLink: ''),
      ]);
      addTearDown(repo.dispose);
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((ref) => Stream.value(_user())),
          userAlertsRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(wrap(container));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tap me'));
      await tester.pumpAndSettle();

      expect(repo.markedRead, ['a1']);
    });
  });
}
