import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../../features/medication/domain/services/notification_identity.dart';

class LocalNotificationService {
  LocalNotificationService._();

  static const String _medicationChannelId = 'medication_reminders';
  static const String _medicationChannelName = 'Medication Reminders';
  static const String _medicationChannelDescription =
      'Daily reminders to take scheduled medications';

  /// A second, lower-importance channel for the coaching layer (recovery
  /// nudges, celebrations, weekly reflections, adaptive coaching) — kept
  /// separate from [_medicationChannelId] so a user can mute the "extra"
  /// messages in system settings while keeping the primary reminder
  /// (Sprint UX-M2.5, Phase 2: five distinct categories).
  static const String _coachingChannelId = 'medication_coaching';
  static const String _coachingChannelName = 'Health Coaching';
  static const String _coachingChannelDescription =
      'Encouragement, recovery nudges, celebrations, and weekly reflections';

  /// The maximum reminders a single medication can ever have
  /// ([MedicationFrequency.thriceDaily]) — the ID-cancellation loop's bound.
  static const int maxRemindersPerMedication = 3;

  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  /// The single app-wide plugin instance, for callers outside this class that
  /// need to show/schedule on their own channel without re-initialising the
  /// plugin (e.g. `LocalNotificationAlertPresenter` in `features/alerts`,
  /// which owns the separate `risk_alerts` channel). Safe to read before
  /// [initialize] has run — [_notificationsPlugin] is created eagerly.
  static FlutterLocalNotificationsPlugin get plugin => _notificationsPlugin;

  static bool _initialized = false;

  /// Broadcasts the `payload` of every notification tap received while the
  /// app process is alive (foreground or backgrounded-but-running). A
  /// terminated-app launch tap is *not* delivered here — use
  /// [consumeLaunchPayload] once, after the router is ready, instead (mirrors
  /// how `PushMessagingService.getInitialMessage()` handles the FCM
  /// equivalent).
  static final StreamController<String> _tapController =
      StreamController<String>.broadcast();

  static const pushPayloadPrefix = 'foreseeme-push-v1:';

  static Stream<String> get onNotificationTapped => _tapController.stream.where(
    (payload) => !payload.startsWith(pushPayloadPrefix),
  );

  static Stream<String> get onPushNotificationTapped => _tapController.stream
      .where((payload) => payload.startsWith(pushPayloadPrefix));

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

    await _notificationsPlugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
    );
    await _createMedicationReminderChannel();
    await _createCoachingChannel();
    await _requestAndroidPermissions();

    _initialized = true;
  }

  static void _handleNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty) {
      _tapController.add(payload);
    }
  }

  /// The payload of the notification that launched the app from a
  /// terminated state, or null if the app wasn't launched by a tap. Reads
  /// the plugin's launch details exactly once per cold start — call it after
  /// [initialize] and after the router is ready to navigate.
  static Future<String?> consumeLaunchPayload({bool push = false}) async {
    await _ensureInitialized();
    final details = await _notificationsPlugin
        .getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return null;
    final payload = details.notificationResponse?.payload;
    return payload != null && payload.startsWith(pushPayloadPrefix) == push
        ? payload
        : null;
  }

  /// Schedules (or reschedules in place) the primary daily reminder at
  /// [notificationId] with coaching-aware content and an adaptively-tuned
  /// [scheduledTime] — a repeating alarm, guaranteed to fire even if the app
  /// is never reopened. [title]/[body]/[payload] always come from
  /// `MedicationCoachingService` via `MedicationNotificationOrchestrator`
  /// (Sprint UX-M2.5): it's the single source of truth for notification
  /// content, used for the very first scheduling as well as every refresh.
  static Future<void> scheduleDailyWithContent({
    required int notificationId,
    required String title,
    required String body,
    required DateTime scheduledTime,
    required String payload,
  }) async {
    await _ensureInitialized();
    await _zonedScheduleDaily(
      notificationId: notificationId,
      medicationName: title,
      title: title,
      body: body,
      scheduledDate: _nextDailyInstance(scheduledTime),
      payload: payload,
      scheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      channelId: _medicationChannelId,
      channelName: _medicationChannelName,
      channelDescription: _medicationChannelDescription,
    );
  }

  /// Schedules a one-off (non-repeating) coaching notification — escalation
  /// stages (recovery), weekly reflection, etc. Always on the lower-priority
  /// [_coachingChannelId].
  static Future<void> scheduleOnce({
    required int notificationId,
    required String title,
    required String body,
    required DateTime scheduledTime,
    required String payload,
  }) async {
    await _ensureInitialized();
    if (!scheduledTime.isAfter(DateTime.now())) {
      await _notificationsPlugin.cancel(id: notificationId);
      return;
    }

    final zoned = tz.TZDateTime.from(scheduledTime, tz.local);
    try {
      await _notificationsPlugin.zonedSchedule(
        id: notificationId,
        title: title,
        body: body,
        scheduledDate: zoned,
        notificationDetails: _notificationDetails(
          channelId: _coachingChannelId,
          channelName: _coachingChannelName,
          channelDescription: _coachingChannelDescription,
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload,
      );
    } on Exception catch (error) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          library: 'notifications',
          context: ErrorDescription('scheduling one-off coaching notification'),
        ),
      );
      await _notificationsPlugin.zonedSchedule(
        id: notificationId,
        title: title,
        body: body,
        scheduledDate: zoned,
        notificationDetails: _notificationDetails(
          channelId: _coachingChannelId,
          channelName: _coachingChannelName,
          channelDescription: _coachingChannelDescription,
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: payload,
      );
    }
  }

  /// Shows a coaching notification immediately (celebrations).
  static Future<void> showNow({
    required int notificationId,
    required String title,
    required String body,
    required String payload,
  }) async {
    await _ensureInitialized();
    await _notificationsPlugin.show(
      id: notificationId,
      title: title,
      body: body,
      notificationDetails: _notificationDetails(
        channelId: _coachingChannelId,
        channelName: _coachingChannelName,
        channelDescription: _coachingChannelDescription,
      ),
      payload: payload,
    );
  }

  static Future<void> cancelNotification(int notificationId) async {
    await _ensureInitialized();
    await _notificationsPlugin.cancel(id: notificationId);
  }

  static Future<void> cancelMedicationReminders(String medicationId) async {
    await _ensureInitialized();

    for (var i = 0; i < maxRemindersPerMedication; i++) {
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
    return medicationNotificationId('primary:$medicationId:$index');
  }

  /// Deterministic candidate for coaching notifications. Production scheduling
  /// resolves collisions through the persisted medication ownership ledger;
  /// immediate celebrations use their own persisted allocation range.
  static int generateCoachingNotificationId(String key) {
    return medicationNotificationId('coaching:$key');
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

  static Future<void> _createCoachingChannel() async {
    const channel = AndroidNotificationChannel(
      _coachingChannelId,
      _coachingChannelName,
      description: _coachingChannelDescription,
      importance: Importance.defaultImportance,
    );

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
  }

  static NotificationDetails _notificationDetails({
    String channelId = _medicationChannelId,
    String channelName = _medicationChannelName,
    String channelDescription = _medicationChannelDescription,
  }) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
      ),
      iOS: const DarwinNotificationDetails(),
      macOS: const DarwinNotificationDetails(),
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
    required String channelId,
    required String channelName,
    required String channelDescription,
  }) async {
    try {
      await _notificationsPlugin.zonedSchedule(
        id: notificationId,
        title: title,
        body: body,
        scheduledDate: scheduledDate,
        notificationDetails: _notificationDetails(
          channelId: channelId,
          channelName: channelName,
          channelDescription: channelDescription,
        ),
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
        channelId: channelId,
        channelName: channelName,
        channelDescription: channelDescription,
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
}
