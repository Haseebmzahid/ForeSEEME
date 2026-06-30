import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/alerts/data/repositories/firestore_notification_preferences_repository.dart';
import 'package:fyp_foreseeme/features/alerts/domain/models/notification_preferences.dart';
import 'package:fyp_foreseeme/features/alerts/domain/repositories/notification_preferences_repository.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/alerts_providers.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/notification_settings_screen.dart';
import 'package:fyp_foreseeme/features/auth/domain/models/user_model.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';

UserModel _user() =>
    UserModel(uid: 'u1', email: 'a@b.com', createdAt: DateTime.utc(2026, 1, 1));

class RecordingPrefsRepository implements NotificationPreferencesRepository {
  RecordingPrefsRepository([NotificationPreferences? initial])
    : stored = initial ?? NotificationPreferences.defaults();

  NotificationPreferences stored;
  final List<NotificationPreferences> saves = [];

  @override
  Future<NotificationPreferences> load(String uid) async => stored;

  @override
  Future<void> save(String uid, NotificationPreferences preferences) async {
    stored = preferences;
    saves.add(preferences);
  }
}

void main() {
  group('NotificationPreferences serialization', () {
    test('defaults are sensible', () {
      final d = NotificationPreferences.defaults();
      expect(d.highRiskAlerts, isTrue);
      expect(d.mediumRiskAlerts, isTrue);
      expect(d.lowRiskUpdates, isFalse);
      expect(d.conditions['respiratory'], isTrue);
      expect(d.conditions['cardiovascular'], isFalse);
    });

    test('fromJson(toJson(x)) round-trips', () {
      final prefs = NotificationPreferences.defaults()
          .copyWith(lowRiskUpdates: true)
          .withCondition('cardiovascular', true);

      expect(NotificationPreferences.fromJson(prefs.toJson()), prefs);
    });

    test('fromJson(null) returns defaults', () {
      expect(
        NotificationPreferences.fromJson(null),
        NotificationPreferences.defaults(),
      );
    });

    test('fromJson fills missing fields with defaults', () {
      final prefs = NotificationPreferences.fromJson({'highRiskAlerts': false});
      expect(prefs.highRiskAlerts, isFalse);
      expect(prefs.mediumRiskAlerts, isTrue); // default
      expect(prefs.conditions['respiratory'], isTrue); // default
    });
  });

  group('FirestoreNotificationPreferencesRepository round-trip', () {
    test('save then load returns the same preferences', () async {
      final repo = FirestoreNotificationPreferencesRepository(
        firestore: FakeFirebaseFirestore(),
      );
      final prefs = NotificationPreferences.defaults()
          .copyWith(lowRiskUpdates: true)
          .withCondition('cardiovascular', true);

      await repo.save('u1', prefs);

      expect(await repo.load('u1'), prefs);
    });

    test('load with no document returns defaults', () async {
      final repo = FirestoreNotificationPreferencesRepository(
        firestore: FakeFirebaseFirestore(),
      );
      expect(await repo.load('u1'), NotificationPreferences.defaults());
    });
  });

  group('NotificationPreferencesController', () {
    test('loads and persists toggle changes', () async {
      final repo = RecordingPrefsRepository();
      final auth = StreamController<UserModel?>();
      auth.add(_user());
      addTearDown(auth.close);

      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((ref) => auth.stream),
          notificationPreferencesRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      container.listen(
        notificationPreferencesControllerProvider,
        (_, _) {},
        fireImmediately: true,
      );

      final loaded = await container.read(
        notificationPreferencesControllerProvider.future,
      );
      expect(loaded, NotificationPreferences.defaults());

      await container
          .read(notificationPreferencesControllerProvider.notifier)
          .setHighRiskAlerts(false);

      expect(repo.saves.last.highRiskAlerts, isFalse);
      expect(
        container
            .read(notificationPreferencesControllerProvider)
            .value!
            .highRiskAlerts,
        isFalse,
      );
    });
  });

  group('NotificationSettingsScreen', () {
    testWidgets('renders toggles and persists a change', (tester) async {
      final repo = RecordingPrefsRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith((ref) => Stream.value(_user())),
            notificationPreferencesRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(home: NotificationSettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('High risk alerts'), findsOneWidget);
      expect(find.text('Low risk updates'), findsOneWidget);
      expect(find.text('Respiratory'), findsOneWidget);
      expect(find.text('Cardiovascular'), findsOneWidget);

      // High is on by default — toggling it off persists.
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      expect(repo.saves.last.highRiskAlerts, isFalse);
    });
  });
}
