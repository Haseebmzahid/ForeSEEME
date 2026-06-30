import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/alerts/data/repositories/firestore_fcm_token_repository.dart';
import 'package:fyp_foreseeme/features/alerts/domain/models/notification_permission_status.dart';
import 'package:fyp_foreseeme/features/alerts/domain/repositories/fcm_token_repository.dart';
import 'package:fyp_foreseeme/features/alerts/domain/services/push_messaging_service.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/alerts_providers.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/notification_permission_screen.dart';

class FakePushMessagingService implements PushMessagingService {
  FakePushMessagingService({required this.status, this.token = 'tok-1'});

  final NotificationPermissionStatus status;
  final String? token;
  final StreamController<String> _refresh =
      StreamController<String>.broadcast();

  int permissionRequests = 0;

  @override
  Future<NotificationPermissionStatus> requestPermission() async {
    permissionRequests++;
    return status;
  }

  @override
  Future<String?> getToken() async => token;

  @override
  Stream<String> onTokenRefresh() => _refresh.stream;

  void emitRefresh(String token) => _refresh.add(token);
}

class RecordingFcmTokenRepository implements FcmTokenRepository {
  final List<(String uid, String token)> saves = [];

  @override
  Future<void> saveToken(String uid, String token) async {
    saves.add((uid, token));
  }
}

ProviderContainer _container(
  FakePushMessagingService messaging,
  RecordingFcmTokenRepository repo,
) {
  final container = ProviderContainer(
    overrides: [
      pushMessagingServiceProvider.overrideWithValue(messaging),
      fcmTokenRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('AlertsController.enableNotifications', () {
    test('on grant, captures and persists the FCM token', () async {
      final messaging = FakePushMessagingService(
        status: NotificationPermissionStatus.granted,
        token: 'tok-1',
      );
      final repo = RecordingFcmTokenRepository();
      final container = _container(messaging, repo);

      final status = await container
          .read(alertsControllerProvider.notifier)
          .enableNotifications('u1');

      expect(status, NotificationPermissionStatus.granted);
      expect(repo.saves, [('u1', 'tok-1')]);
    });

    test('token refresh updates the stored token', () async {
      final messaging = FakePushMessagingService(
        status: NotificationPermissionStatus.granted,
        token: 'tok-1',
      );
      final repo = RecordingFcmTokenRepository();
      final container = _container(messaging, repo);

      await container
          .read(alertsControllerProvider.notifier)
          .enableNotifications('u1');
      messaging.emitRefresh('tok-2');
      await pumpEventQueue();

      expect(repo.saves, contains(('u1', 'tok-2')));
    });

    test('declining permission writes nothing and does not throw', () async {
      final messaging = FakePushMessagingService(
        status: NotificationPermissionStatus.denied,
      );
      final repo = RecordingFcmTokenRepository();
      final container = _container(messaging, repo);

      final status = await container
          .read(alertsControllerProvider.notifier)
          .enableNotifications('u1');

      expect(status, NotificationPermissionStatus.denied);
      expect(repo.saves, isEmpty);
    });
  });

  group('FirestoreFcmTokenRepository', () {
    test('writes fcmToken onto the user document', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreFcmTokenRepository(firestore: firestore);

      await repo.saveToken('u1', 'tok-1');

      final doc = await firestore.collection('users').doc('u1').get();
      expect(doc.data()?['fcmToken'], 'tok-1');
      expect(doc.data()?['fcmTokenUpdatedAt'], isNotNull);
    });
  });

  group('NotificationPermissionScreen', () {
    testWidgets('renders the prompt, benefits and actions', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: NotificationPermissionScreen()),
        ),
      );

      expect(find.text('Stay ahead of risk'), findsOneWidget);
      expect(find.text('Allow notifications'), findsOneWidget);
      expect(find.text('Maybe later'), findsOneWidget);
      expect(find.text('Timely high-risk warnings'), findsOneWidget);
      expect(find.text('No spam, ever'), findsOneWidget);
    });
  });
}
