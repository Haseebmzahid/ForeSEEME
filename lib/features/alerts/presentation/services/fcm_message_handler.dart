import 'dart:async';
import 'dart:convert';

import 'package:fyp_foreseeme/features/alerts/domain/models/incoming_alert.dart';
import 'package:fyp_foreseeme/features/alerts/domain/services/alert_analytics.dart';
import 'package:fyp_foreseeme/features/alerts/domain/services/alert_presenter.dart';
import 'package:fyp_foreseeme/features/alerts/domain/services/push_messaging_service.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/services/alert_deep_link_router.dart';

/// Wires inbound FCM messages to display + navigation across all three app
/// states (Sprint 4, Prompt 4).
///
/// **No Firebase and no business logic here** — it consumes the abstracted
/// [PushMessagingService] streams and delegates: foreground → [AlertPresenter];
/// background/terminated taps → [AlertDeepLinkRouter] then the injected
/// [navigate] callback. This keeps Clean Architecture intact and makes the whole
/// flow testable with fakes.
class FcmMessageHandler {
  FcmMessageHandler({
    required PushMessagingService messaging,
    required AlertPresenter presenter,
    required void Function(String route) navigate,
    required String? Function() currentUid,
    required Future<String?> Function() restoredUid,
    required Future<({String id, String route})?> Function(
      String uid,
      String pushId,
    )
    resolveInboxRoute,
    AlertAnalytics? analytics,
    Future<void> Function(String uid, String alertId)? markRead,
  }) : _messaging = messaging,
       _presenter = presenter,
       _navigate = navigate,
       _currentUid = currentUid,
       _restoredUid = restoredUid,
       _resolveInboxRoute = resolveInboxRoute,
       _analytics = analytics,
       _markRead = markRead;

  final PushMessagingService _messaging;
  final AlertPresenter _presenter;
  final void Function(String route) _navigate;
  final String? Function() _currentUid;
  final Future<String?> Function() _restoredUid;
  final Future<({String id, String route})?> Function(String uid, String pushId)
  _resolveInboxRoute;
  final AlertAnalytics? _analytics;

  /// Marks the tapped push's underlying `userAlerts` doc read (S6A-01), so the
  /// inbox/badge stay in sync even when the user never opens the inbox itself.
  /// Optional so existing callers/tests are unaffected when omitted.
  final Future<void> Function(String uid, String alertId)? _markRead;

  StreamSubscription<IncomingAlert>? _foregroundSub;
  StreamSubscription<IncomingAlert>? _openedSub;

  /// Subscribes to foreground/opened streams and routes a terminated-launch tap.
  /// Idempotent — calling twice does not double-subscribe.
  Future<void> start() async {
    await _foregroundSub?.cancel();
    await _openedSub?.cancel();

    _foregroundSub = _messaging.onForegroundMessage.listen((alert) {
      if (!_isRecipient(alert.data)) return;
      unawaited(_displayNeutral(alert));
    });
    _openedSub = _messaging.onMessageOpened.listen(_route);

    try {
      final initial = await _messaging.getInitialMessage();
      if (initial != null &&
          await _restoredUid() == initial.data['recipientUid']) {
        await _route(initial);
      }
    } catch (_) {
      // The live subscriptions remain active when initial restoration fails.
    }
  }

  bool _isRecipient(Map<String, String> data) {
    final uid = _currentUid();
    return uid != null && uid == data['recipientUid'];
  }

  Future<void> _displayNeutral(IncomingAlert alert) async {
    try {
      await _presenter.showForegroundAlert(
        IncomingAlert(
          data: {
            'recipientUid': alert.data['recipientUid']!,
            'alertId': alert.data['alertId'] ?? '',
          },
          title: 'ForeSeeMe update',
          body:
              'Health awareness only — not a medical diagnosis. Open ForeSeeMe to view your updates.',
          messageId: alert.messageId,
        ),
      );
    } catch (_) {
      // A local display failure must not interrupt the message stream.
    }
  }

  Future<void> openLocalPayload(
    String payload, {
    bool restoring = false,
  }) async {
    try {
      final value = jsonDecode(payload);
      if (value is! Map<String, dynamic>) return;
      final uid = value['recipientUid'];
      final id = value['alertId'];
      if (uid is! String || id is! String) return;
      if (restoring && await _restoredUid() != uid) return;
      await _route(IncomingAlert(data: {'recipientUid': uid, 'alertId': id}));
    } catch (_) {
      // Ignore invalid local notification data.
    }
  }

  Future<void> _route(IncomingAlert alert) async {
    if (!_isRecipient(alert.data)) return;
    final uid = alert.data['recipientUid']!;
    final alertId = alert.data['alertId'];
    if (alertId == null || alertId.isEmpty || alertId.contains('/')) return;
    ({String id, String route})? inboxAlert;
    try {
      inboxAlert = await _resolveInboxRoute(
        uid,
        alertId,
      ).timeout(const Duration(seconds: 5));
    } catch (_) {
      // The sender can finish writing the inbox after the push arrives.
    }

    if (!_isRecipient(alert.data)) return;
    final route = AlertDeepLinkRouter.knownRoutes.contains(inboxAlert?.route)
        ? inboxAlert!.route
        : '/alerts';
    // Engagement hook (Prompt 9): records the open before navigating; a null
    // sink or an analytics failure must never block the tap.
    _analytics?.logAlertOpened(route: route, source: AlertOpenSource.push);
    _navigate(route);
    // Read-sync (S6A-01): fires after navigation so a slow/failed write never
    // delays the tap. Best-effort — the inbox's own tap-to-read remains the
    // fallback if this write fails (e.g. offline), so a swallowed error here
    // never leaves the user stuck.
    try {
      if (inboxAlert != null && _isRecipient(alert.data)) {
        await _markRead?.call(uid, inboxAlert.id);
      }
    } catch (_) {
      // Non-fatal: badge/inbox simply catch up next time the alert is opened.
    }
  }

  void dispose() {
    _foregroundSub?.cancel();
    _openedSub?.cancel();
  }
}
