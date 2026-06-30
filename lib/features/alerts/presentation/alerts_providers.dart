import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fyp_foreseeme/core/routes/app_router.dart';
import 'package:fyp_foreseeme/features/alerts/data/repositories/firestore_fcm_token_repository.dart';
import 'package:fyp_foreseeme/features/alerts/data/repositories/firestore_notification_preferences_repository.dart';
import 'package:fyp_foreseeme/features/alerts/data/services/firebase_push_messaging_service.dart';
import 'package:fyp_foreseeme/features/alerts/data/services/local_notification_alert_presenter.dart';
import 'package:fyp_foreseeme/features/alerts/domain/models/notification_permission_status.dart';
import 'package:fyp_foreseeme/features/alerts/domain/models/notification_preferences.dart';
import 'package:fyp_foreseeme/features/alerts/domain/repositories/fcm_token_repository.dart';
import 'package:fyp_foreseeme/features/alerts/domain/repositories/notification_preferences_repository.dart';
import 'package:fyp_foreseeme/features/alerts/domain/services/alert_presenter.dart';
import 'package:fyp_foreseeme/features/alerts/domain/services/push_messaging_service.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/alerts_controller.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/notification_preferences_controller.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/services/fcm_message_handler.dart';

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

/// Foreground alert display (local notifications). Overridable in tests.
final alertPresenterProvider = Provider<AlertPresenter>((ref) {
  return LocalNotificationAlertPresenter();
});

/// Wires inbound FCM messages to display + deep-link navigation (Prompt 4).
/// Started once at app launch; routes via the app GoRouter.
final fcmMessageHandlerProvider = Provider<FcmMessageHandler>((ref) {
  final handler = FcmMessageHandler(
    messaging: ref.watch(pushMessagingServiceProvider),
    presenter: ref.watch(alertPresenterProvider),
    navigate: (route) => ref.read(appRouterProvider).go(route),
  );
  ref.onDispose(handler.dispose);
  return handler;
});

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
