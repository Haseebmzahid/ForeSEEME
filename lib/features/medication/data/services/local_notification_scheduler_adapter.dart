import 'package:fyp_foreseeme/core/services/local_notification_service.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/notification_content.dart';
import 'package:fyp_foreseeme/features/medication/domain/services/notification_scheduler.dart';
import 'medication_schedule_ledger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wraps `LocalNotificationService`'s static calls behind the
/// `NotificationScheduler` interface — mirrors
/// `LocalNotificationAlertPresenter implements AlertPresenter` in
/// `features/alerts`. Reuses the plugin instance `LocalNotificationService`
/// already initialises; adds no new I/O of its own.
class LocalNotificationSchedulerAdapter
    implements NotificationScheduler, MedicationNotificationInventory {
  const LocalNotificationSchedulerAdapter();

  @override
  Future<List<MedicationPendingNotification>> pending() async =>
      (await LocalNotificationService.plugin.pendingNotificationRequests())
          .map((p) => MedicationPendingNotification(p.id, p.payload))
          .toList();

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
  }) async {
    final id = await MedicationImmediateIds.allocate(
      await SharedPreferences.getInstance(),
      content.identity ?? 'celebration:$notificationId:${content.payload}',
    );
    return LocalNotificationService.showNow(
      notificationId: id,
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
