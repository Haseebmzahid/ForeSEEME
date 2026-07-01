import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/alerts/domain/models/incoming_alert.dart';
import 'package:fyp_foreseeme/features/alerts/domain/models/notification_permission_status.dart';
import 'package:fyp_foreseeme/features/alerts/domain/services/alert_analytics.dart';
import 'package:fyp_foreseeme/features/alerts/domain/services/alert_presenter.dart';
import 'package:fyp_foreseeme/features/alerts/domain/services/push_messaging_service.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/services/fcm_message_handler.dart';

IncomingAlert _alert(String deepLink) => IncomingAlert(
  data: {'type': 'risk_alert', 'deepLink': deepLink, 'city': 'Lahore'},
  title: 'Air quality rising in Lahore',
  body: 'High Smog risk.',
  messageId: 'm1',
);

class FakeMessaging implements PushMessagingService {
  final _foreground = StreamController<IncomingAlert>.broadcast();
  final _opened = StreamController<IncomingAlert>.broadcast();
  IncomingAlert? initialMessage;

  void emitOpened(IncomingAlert a) => _opened.add(a);

  @override
  Stream<IncomingAlert> get onForegroundMessage => _foreground.stream;
  @override
  Stream<IncomingAlert> get onMessageOpened => _opened.stream;
  @override
  Future<IncomingAlert?> getInitialMessage() async => initialMessage;
  @override
  Future<NotificationPermissionStatus> requestPermission() async =>
      NotificationPermissionStatus.granted;
  @override
  Future<String?> getToken() async => null;
  @override
  Stream<String> onTokenRefresh() => const Stream.empty();
}

class _NoopPresenter implements AlertPresenter {
  @override
  Future<void> showForegroundAlert(IncomingAlert alert) async {}
}

class RecordingAnalytics implements AlertAnalytics {
  final opens = <({String route, AlertOpenSource source})>[];

  @override
  void logAlertOpened({
    required String route,
    required AlertOpenSource source,
  }) {
    opens.add((route: route, source: source));
  }
}

void main() {
  late FakeMessaging messaging;
  late RecordingAnalytics analytics;
  late FcmMessageHandler handler;

  setUp(() {
    messaging = FakeMessaging();
    analytics = RecordingAnalytics();
  });

  tearDown(() => handler.dispose());

  test(
    'a background tap logs a push-source open for the resolved route',
    () async {
      handler = FcmMessageHandler(
        messaging: messaging,
        presenter: _NoopPresenter(),
        navigate: (_) {},
        analytics: analytics,
      );
      await handler.start();

      messaging.emitOpened(_alert('/nearby-hospitals'));
      await pumpEventQueue();

      expect(analytics.opens, hasLength(1));
      expect(analytics.opens.single.route, '/nearby-hospitals');
      expect(analytics.opens.single.source, AlertOpenSource.push);
    },
  );

  test('a terminated-launch tap logs a push-source open', () async {
    messaging.initialMessage = _alert('/resources');
    handler = FcmMessageHandler(
      messaging: messaging,
      presenter: _NoopPresenter(),
      navigate: (_) {},
      analytics: analytics,
    );

    await handler.start();

    expect(analytics.opens.single.source, AlertOpenSource.push);
    expect(analytics.opens.single.route, '/resources');
  });

  test('analytics is optional — a null sink never blocks navigation', () async {
    final navigated = <String>[];
    handler = FcmMessageHandler(
      messaging: messaging,
      presenter: _NoopPresenter(),
      navigate: navigated.add,
    );
    await handler.start();

    messaging.emitOpened(_alert('/resources'));
    await pumpEventQueue();

    expect(navigated, ['/resources']); // no analytics, still routes
  });
}
