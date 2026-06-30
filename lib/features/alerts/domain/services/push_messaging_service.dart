import 'package:fyp_foreseeme/features/alerts/domain/models/incoming_alert.dart';
import 'package:fyp_foreseeme/features/alerts/domain/models/notification_permission_status.dart';

/// Abstraction over the push-messaging SDK (keeps `firebase_messaging` out of
/// domain/presentation; mockable in tests).
///
/// Sprint 3: permission + token + refresh. Sprint 4 (Prompt 4) adds the inbound
/// message streams so in-app handling has no firebase dependency.
abstract class PushMessagingService {
  /// Requests notification permission and returns the resulting status.
  Future<NotificationPermissionStatus> requestPermission();

  /// The current device FCM registration token, or `null` if unavailable.
  Future<String?> getToken();

  /// Emits a new token whenever the SDK rotates it.
  Stream<String> onTokenRefresh();

  /// Messages received while the app is in the foreground.
  Stream<IncomingAlert> get onForegroundMessage;

  /// Emits when a background notification is tapped and opens the app.
  Stream<IncomingAlert> get onMessageOpened;

  /// The message that launched the app from a terminated state (tap), if any.
  Future<IncomingAlert?> getInitialMessage();
}
