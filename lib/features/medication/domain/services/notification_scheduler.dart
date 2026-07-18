import 'package:fyp_foreseeme/features/medication/domain/models/notification_content.dart';

/// Abstraction over the OS notification plugin — mirrors `AlertPresenter` /
/// `PushMessagingService` in `features/alerts` (the same seam that lets FCM
/// message handling be tested without Firebase). Lets
/// `MedicationNotificationOrchestrator` be exercised with a fake, with zero
/// platform-channel dependency.
abstract class NotificationScheduler {
  /// (Re)schedules a repeating daily reminder at [notificationId] with
  /// [content] at [time] — the reliable, always-fires baseline (Action
  /// category only; survives the app never reopening).
  Future<void> scheduleDaily({
    required int notificationId,
    required NotificationContent content,
    required DateTime time,
  });

  /// Schedules a one-off notification (escalation stages, weekly
  /// reflection) for [time]. A [time] that has already passed is a no-op.
  Future<void> scheduleOnce({
    required int notificationId,
    required NotificationContent content,
    required DateTime time,
  });

  /// Shows [content] immediately (celebrations).
  Future<void> showNow({
    required int notificationId,
    required NotificationContent content,
  });

  /// Cancels a single scheduled/pending notification, if any.
  Future<void> cancel(int notificationId);
}
