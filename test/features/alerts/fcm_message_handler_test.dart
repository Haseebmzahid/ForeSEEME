import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/alerts/domain/models/incoming_alert.dart';
import 'package:fyp_foreseeme/features/alerts/domain/models/notification_permission_status.dart';
import 'package:fyp_foreseeme/features/alerts/domain/services/alert_presenter.dart';
import 'package:fyp_foreseeme/features/alerts/domain/services/push_messaging_service.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/services/fcm_message_handler.dart';

IncomingAlert _alert({String recipient = 'u1', String id = 'example-alert'}) =>
    IncomingAlert(
      data: {'recipientUid': recipient, 'alertId': id},
      title: 'Private example title',
      body: 'Private example detail.',
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

  @override
  Future<NotificationPermissionStatus> permissionStatus() =>
      requestPermission();

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
  late List<(String, String)> marked;
  late String? active;
  late FcmMessageHandler handler;

  FcmMessageHandler build({
    Future<({String id, String route})?> Function(String, String)? resolver,
  }) => FcmMessageHandler(
    messaging: messaging,
    presenter: presenter,
    navigate: navigated.add,
    currentUid: () => active,
    restoredUid: () async => active,
    resolveInboxRoute:
        resolver ??
        (uid, id) async =>
            (id: id, route: id == 'weekly' ? '/weekly-report' : '/resources'),
    markRead: (uid, id) async => marked.add((uid, id)),
  );

  setUp(() {
    messaging = FakeMessaging();
    presenter = RecordingPresenter();
    active = 'u1';
    navigated = [];
    marked = [];
  });
  tearDown(() => handler.dispose());

  test(
    'foreground for the active recipient is displayed with neutral copy',
    () async {
      handler = build();
      await handler.start();
      messaging.emitForeground(_alert());
      await pumpEventQueue();

      expect(presenter.shown.single.title, 'ForeSeeMe update');
      expect(
        presenter.shown.single.body,
        startsWith('Health awareness only — not a medical diagnosis.'),
      );
      expect(presenter.shown.single.body, isNot(contains('Private')));
      expect(navigated, isEmpty);
      expect(marked, isEmpty);
    },
  );

  test(
    'background and local taps resolve the authenticated inbox item',
    () async {
      handler = build();
      await handler.start();
      messaging.emitOpened(_alert());
      await pumpEventQueue();
      await handler.openLocalPayload(
        '{"recipientUid":"u1","alertId":"weekly"}',
      );

      expect(navigated, ['/resources', '/weekly-report']);
      expect(marked, [('u1', 'example-alert'), ('u1', 'weekly')]);
    },
  );

  test(
    'terminated launch uses the restored UID and server-backed route',
    () async {
      messaging.initialMessage = _alert(id: 'weekly');
      handler = build();
      await handler.start();
      expect(navigated, ['/weekly-report']);
    },
  );

  test('foreign pushes and taps are ignored in every delivery path', () async {
    final foreign = _alert(recipient: 'previous-user');
    messaging.initialMessage = foreign;
    handler = build();
    await handler.start();
    messaging.emitForeground(foreign);
    messaging.emitOpened(foreign);
    await handler.openLocalPayload(
      '{"recipientUid":"previous-user","alertId":"weekly"}',
    );
    await pumpEventQueue();

    expect(presenter.shown, isEmpty);
    expect(navigated, isEmpty);
    expect(marked, isEmpty);
  });

  test(
    'sign-out during the inbox read prevents navigation and read marking',
    () async {
      final pending = Completer<({String id, String route})?>();
      handler = build(resolver: (_, _) => pending.future);
      await handler.start();
      messaging.emitOpened(_alert());
      await pumpEventQueue();
      active = 'u2';
      pending.complete((id: 'example-alert', route: '/weekly-report'));
      await pumpEventQueue();

      expect(navigated, isEmpty);
      expect(marked, isEmpty);
    },
  );

  test(
    'a missing inbox document opens the owner inbox without a read write',
    () async {
      handler = build(resolver: (_, _) async => null);
      await handler.start();
      messaging.emitOpened(_alert());
      await pumpEventQueue();

      expect(navigated, ['/alerts']);
      expect(marked, isEmpty);
    },
  );

  test('a document reference containing a path is rejected', () async {
    handler = build();
    await handler.start();
    messaging.emitOpened(_alert(id: 'other/path'));
    await pumpEventQueue();
    expect(navigated, isEmpty);
  });
}
