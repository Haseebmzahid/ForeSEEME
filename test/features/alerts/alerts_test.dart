import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:fyp_foreseeme/features/alerts/domain/models/incoming_alert.dart';
import 'package:fyp_foreseeme/features/alerts/domain/models/notification_permission_status.dart';
import 'package:fyp_foreseeme/features/alerts/domain/services/push_messaging_service.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/alerts_providers.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/notification_permission_screen.dart';
import 'package:fyp_foreseeme/features/auth/data/repositories/session_api_client.dart';
import 'package:fyp_foreseeme/features/auth/domain/models/user_model.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';

class TestUser extends Fake implements User {
  TestUser(this.uid);
  @override
  final String uid;
  Completer<String?>? bearerGate;

  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async =>
      bearerGate == null ? 'bearer-$uid' : await bearerGate!.future;
}

class FakePushMessagingService implements PushMessagingService {
  NotificationPermissionStatus status = NotificationPermissionStatus.granted;
  String token = 'device-one';
  final _refresh = StreamController<String>.broadcast();
  int subscriptions = 0;

  @override
  Future<NotificationPermissionStatus> permissionStatus() async => status;
  @override
  Future<NotificationPermissionStatus> requestPermission() async => status;
  @override
  Future<String?> getToken() async => token;
  @override
  Stream<String> onTokenRefresh() {
    subscriptions++;
    return _refresh.stream;
  }

  void rotate(String value) {
    token = value;
    _refresh.add(value);
  }

  @override
  Stream<IncomingAlert> get onForegroundMessage => const Stream.empty();
  @override
  Stream<IncomingAlert> get onMessageOpened => const Stream.empty();
  @override
  Future<IncomingAlert?> getInitialMessage() async => null;
}

class RecordingSessionApi extends SessionApiClient {
  RecordingSessionApi() : super(http.Client(), '');
  final registrations = <(String, String, String?)>[];
  final removals = <(String, String)>[];
  bool failRegister = false;
  Completer<void>? removalGate;

  @override
  Future<void> registerNotification(
    String bearer,
    String token, {
    String? previousToken,
  }) async {
    if (failRegister) throw StateError('connection failed');
    registrations.add((bearer, token, previousToken));
  }

  @override
  Future<void> unregisterNotification(String bearer, String token) async {
    await removalGate?.future;
    removals.add((bearer, token));
  }
}

void main() {
  group('notification registration lifecycle', () {
    late TestUser? active;
    late StreamController<UserModel?> auth;
    late FakePushMessagingService messaging;
    late RecordingSessionApi api;
    late ProviderContainer container;

    void transition(TestUser? user) {
      active = user;
      auth.add(
        user == null
            ? null
            : UserModel(
                uid: user.uid,
                email: 'example@example.test',
                createdAt: DateTime.utc(2026),
              ),
      );
    }

    setUp(() {
      active = TestUser('a');
      auth = StreamController<UserModel?>.broadcast();
      messaging = FakePushMessagingService();
      api = RecordingSessionApi();
      container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((ref) => auth.stream),
          notificationAuthUserProvider.overrideWithValue(() => active),
          pushMessagingServiceProvider.overrideWithValue(messaging),
          sessionApiClientProvider.overrideWithValue(api),
        ],
      );
      container.listen(alertsControllerProvider, (_, _) {});
    });

    tearDown(() {
      container.dispose();
      unawaited(auth.close());
      unawaited(messaging._refresh.close());
    });

    test('registers A, rotates, and keeps one subscription', () async {
      final controller = container.read(alertsControllerProvider.notifier);
      await controller.enableNotifications();
      await controller.enableNotifications();
      expect(messaging.subscriptions, 1);
      messaging.rotate('device-two');
      await pumpEventQueue();
      expect(api.registrations.first, ('bearer-a', 'device-one', null));
      expect(api.registrations.last, ('bearer-a', 'device-two', 'device-one'));
    });

    test('logout retires A, then synchronizes B on the same device', () async {
      final controller = container.read(alertsControllerProvider.notifier);
      await controller.enableNotifications();
      await controller.unregister('a', 'bearer-a');
      transition(null);
      await pumpEventQueue();
      transition(TestUser('b'));
      await pumpEventQueue();
      expect(api.removals, [('bearer-a', 'device-one')]);
      expect(api.registrations.last, ('bearer-b', 'device-one', null));
      expect(messaging.subscriptions, 2);
    });

    test(
      'delayed unregister retains the departing bearer after B registers',
      () async {
        final controller = container.read(alertsControllerProvider.notifier);
        await controller.enableNotifications();
        api.removalGate = Completer<void>();
        final removal = controller.unregister('a', 'bearer-a');
        await pumpEventQueue();

        transition(TestUser('b'));
        await pumpEventQueue();
        expect(api.registrations.last, ('bearer-b', 'device-one', null));
        api.removalGate!.complete();
        await removal;
        expect(api.removals.single, ('bearer-a', 'device-one'));
      },
    );

    test(
      'discards an old refresh callback suspended during account switch',
      () async {
        final a = active!;
        final controller = container.read(alertsControllerProvider.notifier);
        await controller.enableNotifications();
        a.bearerGate = Completer<String?>();
        messaging.rotate('device-two');
        await pumpEventQueue();
        transition(TestUser('b'));
        await pumpEventQueue();
        a.bearerGate!.complete('bearer-a');
        await pumpEventQueue();
        expect(api.registrations, [
          ('bearer-a', 'device-one', null),
          ('bearer-b', 'device-two', null),
        ]);
        await expectLater(
          controller.unregister('a', 'bearer-a'),
          throwsStateError,
        );
        expect(api.removals, isEmpty);
      },
    );

    test('denied permission makes no registration or subscription', () async {
      messaging.status = NotificationPermissionStatus.denied;
      final result = await container
          .read(alertsControllerProvider.notifier)
          .enableNotifications();
      expect(result, NotificationPermissionStatus.denied);
      expect(api.registrations, isEmpty);
      expect(messaging.subscriptions, 0);
    });

    test('registration failure is safe and can be retried', () async {
      api.failRegister = true;
      final controller = container.read(alertsControllerProvider.notifier);
      await expectLater(controller.enableNotifications(), throwsStateError);
      api.failRegister = false;
      await controller.syncGrantedPermission();
      expect(api.registrations, [('bearer-a', 'device-one', null)]);
      expect(messaging.subscriptions, 1);
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
