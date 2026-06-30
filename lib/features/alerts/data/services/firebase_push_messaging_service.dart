import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:fyp_foreseeme/features/alerts/domain/models/notification_permission_status.dart';
import 'package:fyp_foreseeme/features/alerts/domain/services/push_messaging_service.dart';

/// `firebase_messaging`-backed [PushMessagingService]. Capture-only: it requests
/// permission and reads the token/refresh stream; it registers no message
/// handlers (dispatch/receiving is Sprint 4).
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
