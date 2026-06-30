import 'package:fyp_foreseeme/features/alerts/domain/models/notification_permission_status.dart';

/// Abstraction over the push-messaging SDK (keeps `firebase_messaging` out of
/// domain/presentation; mockable in tests).
///
/// Capture-only for Sprint 3: permission + token + refresh. No message
/// receiving/dispatch — that is Sprint 4.
abstract class PushMessagingService {
  /// Requests notification permission and returns the resulting status.
  Future<NotificationPermissionStatus> requestPermission();

  /// The current device FCM registration token, or `null` if unavailable.
  Future<String?> getToken();

  /// Emits a new token whenever the SDK rotates it.
  Stream<String> onTokenRefresh();
}
