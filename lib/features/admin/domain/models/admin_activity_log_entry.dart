// Pure-Dart model for one entry in the admin activity log (Sprint M8.2,
// SDS FR8.4). Framework-free, mirroring [RiskOverride]/[JobHeartbeat].
//
// Append-only and immutable once written (enforced server-side —
// `firestore.rules` denies update/delete on `adminActivityLog` to everyone,
// including admins) — a queryable audit trail of admin actions, distinct from
// the `overrides` collection itself (which is last-write-wins per city and
// therefore not a history).

/// One recorded admin action.
class AdminActivityLogEntry {
  /// The Firestore document id (auto-generated). `null` before the entry has
  /// been written.
  final String? id;

  /// A short, stable action code, e.g. `"override_set"` / `"override_clear"`.
  /// Deliberately an open string, not a closed enum — future admin modules
  /// (content management, user management) add new action codes without
  /// changing this model.
  final String action;

  /// What the action was performed on, e.g. a city name for an override.
  final String target;

  /// Human-readable one-line description shown in the log viewer, e.g.
  /// `"Set Lahore risk to High (Smog)"`.
  final String summary;

  /// Audit: the authenticated operator who performed the action.
  final String authorUid;
  final String authorEmail;

  /// Audit: when the action was performed (UTC).
  final DateTime createdAt;

  const AdminActivityLogEntry({
    this.id,
    required this.action,
    required this.target,
    required this.summary,
    required this.authorUid,
    required this.authorEmail,
    required this.createdAt,
  });

  factory AdminActivityLogEntry.fromJson(
    Map<String, dynamic> json, {
    String? id,
  }) {
    return AdminActivityLogEntry(
      id: id,
      action: (json['action'] as String?) ?? '',
      target: (json['target'] as String?) ?? '',
      summary: (json['summary'] as String?) ?? '',
      authorUid: (json['authorUid'] as String?) ?? '',
      authorEmail: (json['authorEmail'] as String?) ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
    );
  }

  /// Serialises for the write path. [id] is never included — it is the
  /// Firestore-assigned document id, not a field.
  Map<String, dynamic> toJson() {
    return {
      'action': action,
      'target': target,
      'summary': summary,
      'authorUid': authorUid,
      'authorEmail': authorEmail,
      'createdAt': createdAt.toUtc().toIso8601String(),
    };
  }

  @override
  String toString() =>
      'AdminActivityLogEntry(action: $action, target: $target, '
      'createdAt: ${createdAt.toUtc().toIso8601String()})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdminActivityLogEntry &&
          other.id == id &&
          other.action == action &&
          other.target == target &&
          other.summary == summary &&
          other.authorUid == authorUid &&
          other.authorEmail == authorEmail &&
          other.createdAt == createdAt;

  @override
  int get hashCode =>
      Object.hash(id, action, target, summary, authorUid, authorEmail, createdAt);
}
