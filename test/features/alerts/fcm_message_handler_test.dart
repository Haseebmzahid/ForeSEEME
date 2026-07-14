import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/alerts/domain/models/incoming_alert.dart';
import 'package:fyp_foreseeme/features/alerts/domain/models/notification_permission_status.dart';
import 'package:fyp_foreseeme/features/alerts/domain/services/alert_presenter.dart';
import 'package:fyp_foreseeme/features/alerts/domain/services/push_messaging_service.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/services/fcm_message_handler.dart';

IncomingAlert _alert({String? deepLink, String type = 'risk_alert'}) =>
    IncomingAlert(
      data: {
        'type': type,
        'deepLink': ?deepLink,
        'city': 'Lahore',
      },
      title: 'Air quality rising in Lahore',
      body: 'High Smog risk.',
      messageId: 'm1',
    );

class FakeMessaging implements PushMessagingService {
  final _foreground = StreamController<IncomingAlert>.broadcast();
  final _opened = StreamController<IncomingAlert>.broadcast();
  IncomingAlert? initialMessage;

  void emitForeground(IncomingAlert a) => _foreground.add(a);
  void emitOpened(IncomingAlert a) => _opened.add(a);

  @override
  Stream<IncomingAlert> get onForegroundMessage => _foreground.stream;
  @override
  Stream<IncomingAlert> get onMessageOpened => _opened.stream;
  @override
  Future<IncomingAlert?> getInitialMessage() async => initialMessage;

  // Unused by these tests.
  @override
  Future<NotificationPermissionStatus> requestPermission() async =>
      NotificationPermissionStatus.granted;
  @override
  Future<String?> getToken() async => null;
  @override
  Stream<String> onTokenRefresh() => const Stream.empty();
}

class RecordingPresenter implements AlertPresenter {
  final shown = <IncomingAlert>[];

  @override
  Future<void> showForegroundAlert(IncomingAlert alert) async =>
      shown.add(alert);
}

void main() {
  late FakeMessaging messaging;
  late RecordingPresenter presenter;
  late List<String> navigated;
  late List<Map<String, String>> readSyncCalls;
  late FcmMessageHandler handler;

  FcmMessageHandler build({bool withMarkRead = true}) => FcmMessageHandler(
    messaging: messaging,
    presenter: presenter,
    navigate: navigated.add,
    markRead: withMarkRead
        ? (data) async {
            readSyncCalls.add(data);
          }
        : null,
  );

  setUp(() {
    messaging = FakeMessaging();
    presenter = RecordingPresenter();
    navigated = <String>[];
    readSyncCalls = <Map<String, String>>[];
  });

  tearDown(() => handler.dispose());

  test('foreground message is displayed, not navigated, not read-synced', () async {
    handler = build();
    await handler.start();

    messaging.emitForeground(_alert(deepLink: '/resources'));
    await pumpEventQueue();

    expect(presenter.shown, hasLength(1));
    expect(navigated, isEmpty);
    expect(readSyncCalls, isEmpty);
  });

  test('background tap navigates to the resolved route', () async {
    handler = build();
    await handler.start();

    messaging.emitOpened(_alert(deepLink: '/nearby-hospitals'));
    await pumpEventQueue();

    expect(navigated, ['/nearby-hospitals']);
    expect(presenter.shown, isEmpty);
  });

  test('background tap marks the alert read via the injected callback', () async {
    handler = build();
    await handler.start();

    messaging.emitOpened(_alert(deepLink: '/nearby-hospitals'));
    await pumpEventQueue();

    expect(readSyncCalls, hasLength(1));
    expect(readSyncCalls.single['city'], 'Lahore');
  });

  test('terminated-launch tap routes from the initial message', () async {
    messaging.initialMessage = _alert(deepLink: '/resources');
    handler = build();

    await handler.start();

    expect(navigated, ['/resources']);
  });

  test('terminated-launch tap marks the alert read via the injected callback', () async {
    messaging.initialMessage = _alert(deepLink: '/resources');
    handler = build();

    await handler.start();

    expect(readSyncCalls, hasLength(1));
  });

  test('no initial message → no navigation, no read-sync, on start', () async {
    handler = build();
    await handler.start();

    expect(navigated, isEmpty);
    expect(readSyncCalls, isEmpty);
  });

  test('a failing markRead never blocks navigation', () async {
    handler = FcmMessageHandler(
      messaging: messaging,
      presenter: presenter,
      navigate: navigated.add,
      markRead: (data) async => throw StateError('offline'),
    );
    await handler.start();

    messaging.emitOpened(_alert(deepLink: '/resources'));
    await pumpEventQueue();

    expect(navigated, ['/resources']);
  });

  test('omitting markRead is safe (backward compatible)', () async {
    handler = build(withMarkRead: false);
    await handler.start();

    messaging.emitOpened(_alert(deepLink: '/resources'));
    await pumpEventQueue();

    expect(navigated, ['/resources']);
  });
}
