import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fyp_foreseeme/features/alerts/domain/models/notification_permission_status.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/alerts_providers.dart';

/// Drives notification-permission capture (Sprint 3, Prompt 7).
///
/// On grant it reads the FCM token, persists it to `users/{uid}`, and keeps the
/// stored token in sync with the SDK's refresh stream for the session. Declining
/// is non-fatal — the status is recorded and nothing is written. **No dispatch.**
///
/// `state` is the last [NotificationPermissionStatus] (null until first asked).
class AlertsController extends AsyncNotifier<NotificationPermissionStatus?> {
  StreamSubscription<String>? _refreshSub;

  @override
  FutureOr<NotificationPermissionStatus?> build() {
    ref.onDispose(() => _refreshSub?.cancel());
    return null;
  }

  /// Requests permission and, if granted, captures + persists the token (and
  /// wires refresh). Returns the resulting status.
  Future<NotificationPermissionStatus> enableNotifications(String uid) async {
    state = const AsyncValue.loading();
    try {
      final messaging = ref.read(pushMessagingServiceProvider);
      final repository = ref.read(fcmTokenRepositoryProvider);

      final status = await messaging.requestPermission();

      if (status.isGranted) {
        final token = await messaging.getToken();
        if (token != null && token.isNotEmpty) {
          await repository.saveToken(uid, token);
        }
        // Keep the stored token current as the SDK rotates it.
        await _refreshSub?.cancel();
        _refreshSub = messaging.onTokenRefresh().listen(
          (refreshed) => repository.saveToken(uid, refreshed),
        );
      }

      state = AsyncValue.data(status);
      return status;
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
      rethrow;
    }
  }
}
