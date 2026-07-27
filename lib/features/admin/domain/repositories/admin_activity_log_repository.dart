import '../models/admin_activity_log_entry.dart';

/// Append-only audit trail of admin actions (Sprint M8.2, SDS FR8.4).
///
/// Mirrors [RiskOverrideRepository]/[SystemStatusRepository]: a pure data
/// interface, no business logic. [append] is called by admin controllers
/// (e.g. [AdminOverrideController]) after their real write succeeds; [recent]
/// backs the log-viewer screen. Both are enforced server-side by
/// `firestore.rules` to the `admin` claim — a non-admin caller is denied by
/// the rules, not by this interface. Entries are immutable once written: this
/// interface deliberately exposes no update/delete method.
abstract class AdminActivityLogRepository {
  /// Records one admin action. Callers should treat a failure here as
  /// non-fatal to the action itself (see [AdminOverrideController]) — the
  /// audit trail's completeness matters less than the admin action it
  /// describes actually succeeding.
  Future<void> append(AdminActivityLogEntry entry);

  /// The [limit] most recent entries, newest first. Bounded rather than
  /// paginated (matches the project's existing "cap the query window" choice
  /// for other admin-facing lists) — sufficient at this project's scale.
  Future<List<AdminActivityLogEntry>> recent({int limit = 100});
}
