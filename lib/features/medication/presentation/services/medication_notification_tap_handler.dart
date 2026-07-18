import 'dart:async';

import 'package:flutter/services.dart';

import 'medication_deep_link_router.dart';

/// Wires medication-notification taps to navigation across both app states
/// this plugin distinguishes: alive (foreground/backgrounded) via
/// [tapStream], and terminated-launch via [consumeInitialPayload] — mirrors
/// `FcmMessageHandler`'s shape (Sprint 4, `features/alerts`) so the two
/// notification pipelines read as one family. No Firebase, no plugin
/// types, no business logic — just `payload → route → navigate`, so it's
/// fully testable with fakes.
class MedicationNotificationTapHandler {
  MedicationNotificationTapHandler({
    required Stream<String> tapStream,
    required Future<String?> Function() consumeInitialPayload,
    required void Function(String route) navigate,
  }) : _tapStream = tapStream,
       _consumeInitialPayload = consumeInitialPayload,
       _navigate = navigate;

  final Stream<String> _tapStream;
  final Future<String?> Function() _consumeInitialPayload;
  final void Function(String route) _navigate;

  StreamSubscription<String>? _sub;

  /// Subscribes to live taps and routes a terminated-launch tap.
  /// Idempotent — calling twice does not double-subscribe.
  Future<void> start() async {
    await _sub?.cancel();
    _sub = _tapStream.listen(_route);

    final initialPayload = await _consumeInitialPayload();
    if (initialPayload != null) {
      _route(initialPayload); // app launched from a terminated-state tap
    }
  }

  void _route(String payload) {
    final route = MedicationDeepLinkRouter.resolve(payload);
    // Micro-interaction (Phase 9): a light tap confirms the notification was
    // received before the screen transitions.
    HapticFeedback.lightImpact();
    _navigate(route);
  }

  void dispose() {
    _sub?.cancel();
  }
}
