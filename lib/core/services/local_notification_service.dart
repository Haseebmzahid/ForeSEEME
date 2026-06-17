import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../../features/medication/domain/models/medication_model.dart';

class LocalNotificationService {
  LocalNotificationService._();

  static const String _medicationChannelId = 'medication_reminders';
  static const String _medicationChannelName = 'Medication Reminders';
  static const String _medicationChannelDescription =
      'Daily reminders to take scheduled medications';

  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;

    await _configureLocalTimeZone();

    const androidInitSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const darwinInitSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidInitSettings,
      iOS: darwinInitSettings,
      macOS: darwinInitSettings,
    );

    await _notificationsPlugin.initialize(settings: initSettings);
    await _createMedicationReminderChannel();
    await _requestAndroidPermissions();

    _initialized = true;
  }

  static Future<void> scheduleMedicationReminder({
    required int notificationId,
    required String medicationName,
    required String dosage,
    required DateTime scheduledTime,
  }) async {
    await _ensureInitialized();

    final scheduledDate = _nextDailyInstance(scheduledTime);
    final title = '\u{1F48A} Time to take $medicationName';
    final body = '$dosage \u2022 Scheduled Medication Reminder';

    await _zonedScheduleDaily(
      notificationId: notificationId,
      medicationName: medicationName,
      title: title,
      body: body,
      scheduledDate: scheduledDate,
      payload: 'medication_reminder:$notificationId',
      scheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  static Future<void> scheduleMedicationRemindersForMedication(
    MedicationModel medication,
  ) async {
    await _ensureInitialized();

    if (!medication.isActive) {
      await cancelMedicationReminders(medication.id);
      return;
    }

    await cancelMedicationReminders(medication.id);

    for (var i = 0; i < medication.reminderTimes.length; i++) {
      final scheduledTime = _parseReminderTime(medication.reminderTimes[i]);
      if (scheduledTime == null) continue;

      await scheduleMedicationReminder(
        notificationId: generateMedicationNotificationId(medication.id, i),
        medicationName: medication.name,
        dosage: medication.dosage,
        scheduledTime: scheduledTime,
      );
    }
  }

  static Future<void> cancelNotification(int notificationId) async {
    await _ensureInitialized();
    await _notificationsPlugin.cancel(id: notificationId);
  }

  static Future<void> cancelMedicationReminders(String medicationId) async {
    await _ensureInitialized();

    for (var i = 0; i < 3; i++) {
      await cancelNotification(
        generateMedicationNotificationId(medicationId, i),
      );
    }
  }

  static Future<void> cancelAllNotifications() async {
    await _ensureInitialized();
    await _notificationsPlugin.cancelAll();
  }

  static int generateMedicationNotificationId(String medicationId, int index) {
    return Object.hash(medicationId, index) & 0x7fffffff;
  }

  static Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await initialize();
    }
  }

  static Future<void> _configureLocalTimeZone() async {
    tz.initializeTimeZones();

    if (kIsWeb || Platform.isLinux || Platform.isWindows) {
      return;
    }

    final timeZoneInfo = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timeZoneInfo.identifier));
  }

  static Future<void> _requestAndroidPermissions() async {
    final androidImplementation = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    await androidImplementation?.requestNotificationsPermission();
    await androidImplementation?.requestExactAlarmsPermission();
  }

  static Future<void> _createMedicationReminderChannel() async {
    const channel = AndroidNotificationChannel(
      _medicationChannelId,
      _medicationChannelName,
      description: _medicationChannelDescription,
      importance: Importance.high,
    );

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
  }

  static NotificationDetails _notificationDetails() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        _medicationChannelId,
        _medicationChannelName,
        channelDescription: _medicationChannelDescription,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
      ),
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
    );
  }

  static Future<void> _zonedScheduleDaily({
    required int notificationId,
    required String medicationName,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required String payload,
    required AndroidScheduleMode scheduleMode,
  }) async {
    try {
      await _notificationsPlugin.zonedSchedule(
        id: notificationId,
        title: title,
        body: body,
        scheduledDate: scheduledDate,
        notificationDetails: _notificationDetails(),
        androidScheduleMode: scheduleMode,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: payload,
      );
    } on Exception catch (error) {
      if (scheduleMode != AndroidScheduleMode.exactAllowWhileIdle) {
        rethrow;
      }

      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          library: 'notifications',
          context: ErrorDescription(
            'scheduling exact medication reminder; falling back to inexact',
          ),
        ),
      );

      debugPrint(
        'Medication reminder exact scheduling failed. '
        'notificationId=$notificationId, '
        'medicationName="$medicationName", '
        'scheduledTime=${scheduledDate.toIso8601String()}, '
        'exception="$error"',
      );
      debugPrint(
        'Falling back to inexactAllowWhileIdle scheduling for '
        'notificationId=$notificationId, medicationName="$medicationName".',
      );

      await _zonedScheduleDaily(
        notificationId: notificationId,
        medicationName: medicationName,
        title: title,
        body: body,
        scheduledDate: scheduledDate,
        payload: payload,
        scheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  static tz.TZDateTime _nextDailyInstance(DateTime scheduledTime) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      scheduledTime.hour,
      scheduledTime.minute,
    );

    if (!scheduledDate.isAfter(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    return scheduledDate;
  }

  static DateTime? _parseReminderTime(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return null;

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;

    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, hour, minute);
  }
}
