import 'package:fyp_foreseeme/core/services/local_notification_service.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/notification_content.dart';
import 'package:fyp_foreseeme/features/medication/domain/services/notification_scheduler.dart';

/// Wraps `LocalNotificationService`'s static calls behind the
/// `NotificationScheduler` interface — mirrors
/// `LocalNotificationAlertPresenter implements AlertPresenter` in
/// `features/alerts`. Reuses the plugin instance `LocalNotificationService`
/// already initialises; adds no new I/O of its own.
class LocalNotificationSchedulerAdapter implements NotificationScheduler {
  const LocalNotificationSchedulerAdapter();

  @override
  Future<void> scheduleDaily({
    required int notificationId,
    required NotificationContent content,
    required DateTime time,
  }) {
    return LocalNotificationService.scheduleDailyWithContent(
      notificationId: notificationId,
      title: content.title,
      body: content.body,
      scheduledTime: time,
      payload: content.payload,
    );
  }

  @override
  Future<void> scheduleOnce({
    required int notificationId,
    required NotificationContent content,
    required DateTime time,
  }) {
    return LocalNotificationService.scheduleOnce(
      notificationId: notificationId,
      title: content.title,
      body: content.body,
      scheduledTime: time,
      payload: content.payload,
    );
  }

  @override
  Future<void> showNow({
    required int notificationId,
    required NotificationContent content,
  }) {
    return LocalNotificationService.showNow(
      notificationId: notificationId,
      title: content.title,
      body: content.body,
      payload: content.payload,
    );
  }

  @override
  Future<void> cancel(int notificationId) {
    return LocalNotificationService.cancelNotification(notificationId);
  }
}
