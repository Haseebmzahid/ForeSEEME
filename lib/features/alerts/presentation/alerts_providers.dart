import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fyp_foreseeme/features/alerts/data/repositories/firestore_fcm_token_repository.dart';
import 'package:fyp_foreseeme/features/alerts/data/repositories/firestore_notification_preferences_repository.dart';
import 'package:fyp_foreseeme/features/alerts/data/services/firebase_push_messaging_service.dart';
import 'package:fyp_foreseeme/features/alerts/domain/models/notification_permission_status.dart';
import 'package:fyp_foreseeme/features/alerts/domain/models/notification_preferences.dart';
import 'package:fyp_foreseeme/features/alerts/domain/repositories/fcm_token_repository.dart';
import 'package:fyp_foreseeme/features/alerts/domain/repositories/notification_preferences_repository.dart';
import 'package:fyp_foreseeme/features/alerts/domain/services/push_messaging_service.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/alerts_controller.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/notification_preferences_controller.dart';

/// Push-messaging SDK service. Overridable with a fake in tests.
final pushMessagingServiceProvider = Provider<PushMessagingService>((ref) {
  return FirebasePushMessagingService();
});

/// FCM-token persistence (Firestore). Overridable with a fake in tests.
final fcmTokenRepositoryProvider = Provider<FcmTokenRepository>((ref) {
  return FirestoreFcmTokenRepository();
});

/// Coordinates the permission request + token capture/refresh.
final alertsControllerProvider =
    AsyncNotifierProvider<AlertsController, NotificationPermissionStatus?>(
      AlertsController.new,
    );

/// Notification-preferences persistence (Firestore). Overridable in tests.
final notificationPreferencesRepositoryProvider =
    Provider<NotificationPreferencesRepository>((ref) {
      return FirestoreNotificationPreferencesRepository();
    });

/// Loads/persists the user's notification preferences for the settings screen.
final notificationPreferencesControllerProvider =
    AsyncNotifierProvider<
      NotificationPreferencesController,
      NotificationPreferences
    >(NotificationPreferencesController.new);
