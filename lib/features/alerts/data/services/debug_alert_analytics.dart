import 'package:flutter/foundation.dart';

import 'package:fyp_foreseeme/features/alerts/domain/services/alert_analytics.dart';

/// Default [AlertAnalytics] sink (Sprint 4, Prompt 9).
///
/// Logs deep-link opens to the debug console — a lightweight, dependency-free
/// hook point. A production build can swap this for a real analytics backend by
/// overriding `alertAnalyticsProvider`; the call sites never change. Non-throwing
/// by contract, so it can never disrupt navigation.
class DebugAlertAnalytics implements AlertAnalytics {
  const DebugAlertAnalytics();

  @override
  void logAlertOpened({
    required String route,
    required AlertOpenSource source,
  }) {
    debugPrint('[alert_analytics] opened route=$route source=${source.name}');
  }
}
