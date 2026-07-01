/// Where an alert deep-link was followed from (Sprint 4, Prompt 9).
enum AlertOpenSource {
  /// Tapped a push notification (foreground/background/terminated).
  push,

  /// Tapped an entry in the in-app inbox.
  inbox,
}

/// Analytics seam for alert engagement (Sprint 4, Prompt 9).
///
/// A thin abstraction (no Firebase, no Flutter) so deep-link opens can be
/// measured without leaking an SDK into presentation. The dispatch cost/fatigue
/// audit (`docs/alert_fatigue_cost_audit.md`) uses these opens as the engagement
/// signal against the `alertDispatchLog` send volume. Implementations must be
/// non-throwing and side-effect-light — an analytics failure must never affect
/// navigation.
abstract class AlertAnalytics {
  /// Records that the user opened [route] from [source].
  void logAlertOpened({required String route, required AlertOpenSource source});
}
