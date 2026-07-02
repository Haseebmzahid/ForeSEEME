import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:fyp_foreseeme/features/alerts/domain/models/incoming_alert.dart';
import 'package:fyp_foreseeme/features/alerts/domain/models/notification_permission_status.dart';
import 'package:fyp_foreseeme/features/alerts/domain/services/push_messaging_service.dart';

/// `firebase_messaging`-backed [PushMessagingService]. Covers both legs:
/// token capture (permission request + token/refresh stream) and inbound
/// receiving — it exposes the foreground / opened-app / initial-message streams
/// that [FcmMessageHandler] wires to display + deep-link routing (Sprint 4 P4).
///
/// It maps `firebase_messaging`'s `RemoteMessage` to the domain [IncomingAlert]
/// so no Firebase type crosses the port. It intentionally does **not** register a
/// top-level background *data-only* handler (`onBackgroundMessage`): the backend
/// dispatch engine sends notification-type payloads that the OS renders while
/// backgrounded/terminated, and the tap is handled via
/// [onMessageOpened]/[getInitialMessage]. Add one only if a silent
/// background-processing use case appears.
class FirebasePushMessagingService implements PushMessagingService {
  final FirebaseMessaging _messaging;

  FirebasePushMessagingService({FirebaseMessaging? messaging})
    : _messaging = messaging ?? FirebaseMessaging.instance;

  @override
  Future<NotificationPermissionStatus> requestPermission() async {
    final settings = await _messaging.requestPermission();
    return _map(settings.authorizationStatus);
  }

  @override
  Future<String?> getToken() => _messaging.getToken();

  @override
  Stream<String> onTokenRefresh() => _messaging.onTokenRefresh;

  @override
  Stream<IncomingAlert> get onForegroundMessage =>
      FirebaseMessaging.onMessage.map(_toAlert);

  @override
  Stream<IncomingAlert> get onMessageOpened =>
      FirebaseMessaging.onMessageOpenedApp.map(_toAlert);

  @override
  Future<IncomingAlert?> getInitialMessage() async {
    final message = await _messaging.getInitialMessage();
    return message == null ? null : _toAlert(message);
  }

  IncomingAlert _toAlert(RemoteMessage message) => IncomingAlert(
    data: message.data.map((key, value) => MapEntry(key, '$value')),
    title: message.notification?.title,
    body: message.notification?.body,
    messageId: message.messageId,
  );

  NotificationPermissionStatus _map(AuthorizationStatus status) {
    switch (status) {
      case AuthorizationStatus.authorized:
        return NotificationPermissionStatus.granted;
      case AuthorizationStatus.provisional:
        return NotificationPermissionStatus.provisional;
      case AuthorizationStatus.denied:
        return NotificationPermissionStatus.denied;
      case AuthorizationStatus.notDetermined:
        return NotificationPermissionStatus.notDetermined;
    }
  }
}
