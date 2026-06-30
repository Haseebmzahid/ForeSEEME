import 'dart:async';

import 'package:fyp_foreseeme/features/alerts/domain/models/incoming_alert.dart';
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
  }) : _messaging = messaging,
       _presenter = presenter,
       _navigate = navigate;

  final PushMessagingService _messaging;
  final AlertPresenter _presenter;
  final void Function(String route) _navigate;

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
      _route(initial); // app launched from a terminated-state tap
    }
  }

  void _route(IncomingAlert alert) {
    _navigate(AlertDeepLinkRouter.resolve(alert.data));
  }

  void dispose() {
    _foregroundSub?.cancel();
    _openedSub?.cancel();
  }
}
