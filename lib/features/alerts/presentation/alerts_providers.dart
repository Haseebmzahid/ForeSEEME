import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fyp_foreseeme/core/routes/app_router.dart';
import 'package:fyp_foreseeme/features/alerts/data/repositories/firestore_fcm_token_repository.dart';
import 'package:fyp_foreseeme/features/alerts/data/repositories/firestore_notification_preferences_repository.dart';
import 'package:fyp_foreseeme/features/alerts/data/repositories/firestore_user_alerts_repository.dart';
import 'package:fyp_foreseeme/features/alerts/data/services/debug_alert_analytics.dart';
import 'package:fyp_foreseeme/features/alerts/data/services/firebase_push_messaging_service.dart';
import 'package:fyp_foreseeme/features/alerts/data/services/local_notification_alert_presenter.dart';
import 'package:fyp_foreseeme/features/alerts/domain/models/notification_permission_status.dart';
import 'package:fyp_foreseeme/features/alerts/domain/models/notification_preferences.dart';
import 'package:fyp_foreseeme/features/alerts/domain/models/user_alert.dart';
import 'package:fyp_foreseeme/features/alerts/domain/repositories/fcm_token_repository.dart';
import 'package:fyp_foreseeme/features/alerts/domain/repositories/notification_preferences_repository.dart';
import 'package:fyp_foreseeme/features/alerts/domain/repositories/user_alerts_repository.dart';
import 'package:fyp_foreseeme/features/alerts/domain/services/alert_analytics.dart';
import 'package:fyp_foreseeme/features/alerts/domain/services/alert_presenter.dart';
import 'package:fyp_foreseeme/features/alerts/domain/services/push_messaging_service.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/alerts_controller.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/notification_preferences_controller.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/services/alert_id_resolver.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/services/fcm_message_handler.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';

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

/// Deep-link engagement analytics sink (Prompt 9). Overridable in tests and
/// swappable for a real backend in production without touching call sites.
final alertAnalyticsProvider = Provider<AlertAnalytics>((ref) {
  return const DebugAlertAnalytics();
});

/// Wires inbound FCM messages to display + deep-link navigation (Prompt 4).
/// Started once at app launch; routes via the app GoRouter.
final fcmMessageHandlerProvider = Provider<FcmMessageHandler>((ref) {
  final handler = FcmMessageHandler(
    messaging: ref.watch(pushMessagingServiceProvider),
    presenter: ref.watch(alertPresenterProvider),
    navigate: (route) => ref.read(appRouterProvider).go(route),
    analytics: ref.watch(alertAnalyticsProvider),
    markRead: ref.watch(markAlertReadFromPushProvider),
  );
  ref.onDispose(handler.dispose);
  return handler;
});

/// In-app alert inbox read/mark-read (Firestore). Overridable in tests (Prompt 5).
final userAlertsRepositoryProvider = Provider<UserAlertsRepository>((ref) {
  return FirestoreUserAlertsRepository();
});

/// The current user's inbox alerts, newest first, as a live
/// `AsyncValue<List<UserAlertModel>>` (Prompt 5).
///
/// User-scoped: derives the owner uid from [authStateProvider] and streams only
/// that user's `userAlerts` subtree (the Firestore rule denies any other). When
/// there is no signed-in user it emits an empty list rather than erroring, so
/// the inbox shows a clean empty state. The `AsyncValue` maps onto the inbox UI
/// states: loading / data (list or empty) / error.
///
/// Awaits the auth *future* (like `currentCityRiskProvider` awaits the user's
/// city) so the uid is fully resolved before subscribing — avoiding a racy
/// loading→null→rebuild flip when the auth stream is still warming up.
final userAlertsStreamProvider = StreamProvider<List<UserAlertModel>>((
  ref,
) async* {
  final user = await ref.watch(authStateProvider.future);
  final uid = user?.uid;
  if (uid == null) {
    yield const <UserAlertModel>[];
    return;
  }
  yield* ref.watch(userAlertsRepositoryProvider).watchAlerts(uid);
});

/// Count of unread alerts for the current user — backs the dashboard badge.
///
/// Derived from [userAlertsStreamProvider]; `0` while loading, on error, or when
/// signed out, so the badge is only ever shown for a real unread count.
final unreadAlertCountProvider = Provider<int>((ref) {
  final alerts =
      ref.watch(userAlertsStreamProvider).value ?? const <UserAlertModel>[];
  return alerts.where((a) => !a.read).length;
});

/// Marks a single inbox alert read for the current user (Prompt 5).
///
/// Exposes a callback so the presentation layer never touches uid resolution or
/// the repository directly — it only watches a provider (GOLDEN_RULES rule 1).
/// No-op when signed out.
final markAlertReadProvider = Provider<Future<void> Function(String alertId)>((
  ref,
) {
  final uid = ref.watch(authStateProvider).value?.uid;
  final repository = ref.watch(userAlertsRepositoryProvider);
  return (alertId) async {
    if (uid == null) return;
    await repository.markRead(uid, alertId);
  };
});

/// Marks every currently-unread alert read for the current user
/// (Sprint 6A, S6A-02).
///
/// Exposes a no-arg callback so the presentation layer never touches uid
/// resolution or the repository directly — mirrors [markAlertReadProvider]'s
/// existing pattern exactly. No-op when signed out. Repository-only; no UI
/// consumes this yet (wired in S6A-03).
final markAllAlertsReadProvider = Provider<Future<void> Function()>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  final repository = ref.watch(userAlertsRepositoryProvider);
  return () async {
    if (uid == null) return;
    await repository.markAllRead(uid);
  };
});

/// Marks the alert referenced by an inbound push payload read, for the
/// current user (Sprint 6A, S6A-01).
///
/// Reconstructs the alert's document id via [AlertIdResolver] (no extra
/// Firestore read) and reuses [UserAlertsRepository.markRead] — the same write
/// path the inbox already uses on tap. No-op when signed out or the payload
/// doesn't resolve to a known alert id, so a malformed/foreign payload can
/// never write to the wrong document or throw.
final markAlertReadFromPushProvider =
    Provider<Future<void> Function(Map<String, String> data)>((ref) {
      final uid = ref.watch(authStateProvider).value?.uid;
      final repository = ref.watch(userAlertsRepositoryProvider);
      return (data) async {
        if (uid == null) return;
        final alertId = AlertIdResolver.resolve(data, uid: uid);
        if (alertId == null) return;
        await repository.markRead(uid, alertId);
      };
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
