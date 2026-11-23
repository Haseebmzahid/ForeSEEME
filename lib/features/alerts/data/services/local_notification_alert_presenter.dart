import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:fyp_foreseeme/features/alerts/domain/models/incoming_alert.dart';
import 'package:fyp_foreseeme/features/alerts/domain/services/alert_presenter.dart';

/// Foreground display via `flutter_local_notifications` on a dedicated **Risk
/// Alerts** channel (separate from medication reminders).
///
/// [plugin] is `LocalNotificationService.plugin` in production (wired in
/// `alertPresenterProvider`) — the *same* app-wide plugin instance the
/// medication reminder path initialises, not a second one. This presenter
/// never calls `.initialize()`; it only ensures its own channel exists and
/// shows on it, so the medication path's registered tap handler and Android
/// activity binding are untouched. The `deepLink` rides along as the payload.
/// The optional constructor parameter defaults to a fresh instance only so
/// this class stays constructible in isolation (e.g. tests); production code
/// must always pass the shared instance explicitly.
class LocalNotificationAlertPresenter implements AlertPresenter {
  LocalNotificationAlertPresenter({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// Android notification channel for risk alerts. Referenced by the FCM
  /// default-channel manifest meta-data so background pushes use it too.
  static const String channelId = 'risk_alerts';
  static const String channelName = 'Risk Alerts';
  static const String channelDescription =
      'Environmental disease risk alerts for your city';

  bool _channelReady = false;

  Future<void> _ensureChannel() async {
    if (_channelReady) return;
    const channel = AndroidNotificationChannel(
      channelId,
      channelName,
      description: channelDescription,
      importance: Importance.high,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
    _channelReady = true;
  }

  @override
  Future<void> showForegroundAlert(IncomingAlert alert) async {
    await _ensureChannel();
    const disclaimer = 'Health awareness only — not a medical diagnosis.';
    final incoming = alert.body?.trim() ?? '';
    final body = incoming.startsWith('$disclaimer ') || incoming == disclaimer
        ? incoming
        : '$disclaimer $incoming'.trimRight();
    await _plugin.show(
      id:
          (alert.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch) &
          0x7fffffff,
      title: alert.title ?? 'Health alert',
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: alert.data['deepLink'],
    );
  }
}
