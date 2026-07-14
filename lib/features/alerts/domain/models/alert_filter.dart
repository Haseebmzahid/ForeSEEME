import 'user_alert.dart';

/// The inbox's fixed filter set (Sprint 6A, S6A-06, Decision 1).
///
/// Deliberately **not** a category taxonomy (Risk / Medication / System):
/// every `userAlerts` document is risk-driven — the backend's dispatch engine
/// is the only writer, and medication reminders are a separate, local-only
/// notification system that never reaches this collection. Inventing
/// Medication/System filters here would filter a fiction. The real, honest
/// axes are risk level and read state.
enum AlertFilter {
  all,
  unread,
  low,
  medium,
  high;

  /// Chip label, e.g. "All" / "Unread" / "High".
  String get label => switch (this) {
    AlertFilter.all => 'All',
    AlertFilter.unread => 'Unread',
    AlertFilter.low => 'Low',
    AlertFilter.medium => 'Medium',
    AlertFilter.high => 'High',
  };

  /// Whether [alert] belongs under this filter.
  ///
  /// Pure `data → bool` mapping, fully unit-testable without a widget.
  bool matches(UserAlertModel alert) => switch (this) {
    AlertFilter.all => true,
    AlertFilter.unread => !alert.read,
    AlertFilter.low => alert.riskLevel == 'Low',
    AlertFilter.medium => alert.riskLevel == 'Medium',
    AlertFilter.high => alert.riskLevel == 'High',
  };
}
