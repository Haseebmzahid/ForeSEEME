import 'dart:async';

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
    AlertAnalytics? analytics,
    Future<void> Function(Map<String, String> data)? markRead,
  }) : _messaging = messaging,
       _presenter = presenter,
       _navigate = navigate,
       _analytics = analytics,
       _markRead = markRead;

  final PushMessagingService _messaging;
  final AlertPresenter _presenter;
  final void Function(String route) _navigate;
  final AlertAnalytics? _analytics;

  /// Marks the tapped push's underlying `userAlerts` doc read (S6A-01), so the
  /// inbox/badge stay in sync even when the user never opens the inbox itself.
  /// Optional so existing callers/tests are unaffected when omitted.
  final Future<void> Function(Map<String, String> data)? _markRead;

  StreamSubscription<IncomingAlert>? _foregroundSub;
  StreamSubscription<IncomingAlert>? _openedSub;

  /// Subscribes to foreground/opened streams and routes a terminated-launch tap.
  /// Idempotent — calling twice does not double-subscribe.
  Future<void> start() async {
    await _foregroundSub?.cancel();
    await _openedSub?.cancel();

    _foregroundSub = _messaging.onForegroundMessage.listen(
      _presenter.showForegroundAlert,
    );
    _openedSub = _messaging.onMessageOpened.listen(_route);

    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      await _route(initial); // app launched from a terminated-state tap
    }
  }

  Future<void> _route(IncomingAlert alert) async {
    final route = AlertDeepLinkRouter.resolve(alert.data);
    // Engagement hook (Prompt 9): records the open before navigating; a null
    // sink or an analytics failure must never block the tap.
    _analytics?.logAlertOpened(route: route, source: AlertOpenSource.push);
    _navigate(route);
    // Read-sync (S6A-01): fires after navigation so a slow/failed write never
    // delays the tap. Best-effort — the inbox's own tap-to-read remains the
    // fallback if this write fails (e.g. offline), so a swallowed error here
    // never leaves the user stuck.
    try {
      await _markRead?.call(alert.data);
    } catch (_) {
      // Non-fatal: badge/inbox simply catch up next time the alert is opened.
    }
  }

  void dispose() {
    _foregroundSub?.cancel();
    _openedSub?.cancel();
  }
}
