// Pure-Dart model for one entry in the admin user directory (Sprint M8.4,
// SDS FR8.5). Framework-free, mirroring [RiskOverride]/[JobHeartbeat].
//
/// Directory onboarding status and the backend's Firebase Auth suspension state.
enum UserStatus {
  /// Registered (account created) but has not yet completed health-profile
  /// setup — the router blocks them from the rest of the app until they do,
  /// so this is a genuinely meaningful, if usually short-lived, state.
  pending,

  /// Has completed health-profile setup at least once.
  active,

  /// Firebase Authentication has disabled this account.
  blocked;

  String get label => switch (this) {
    UserStatus.pending => 'Pending',
    UserStatus.active => 'Active',
    UserStatus.blocked => 'Blocked',
  };
}

extension UserStatusX on UserStatus {
  static UserStatus fromJson(String? value) => switch (value) {
    'active' => UserStatus.active,
    _ => UserStatus.pending,
  };
}

/// One registered user, as shown in the admin directory.
class UserDirectoryEntry {
  /// The Firebase Auth uid — also the Firestore document id.
  final String uid;

  /// From the registration form's "Full Name" field, when the account was
  /// created via email/password. `null` for a Google-sign-in-only account
  /// (see docs/user_management.md — Google sign-in does not yet register a
  /// directory entry, a documented gap, not a crash).
  final String? name;

  final String email;

  /// When the account was registered (UTC).
  final DateTime createdAt;

  final UserStatus status;

  const UserDirectoryEntry({
    required this.uid,
    this.name,
    required this.email,
    required this.createdAt,
    required this.status,
  });

  factory UserDirectoryEntry.fromJson(
    Map<String, dynamic> json, {
    required String uid,
  }) {
    return UserDirectoryEntry(
      uid: uid,
      name: json['name'] as String?,
      email: (json['email'] as String?) ?? '',
      // Defensive: a doc created only by markProfileActive's merge-write (no
      // prior register() call — e.g. a Google-sign-in account, see class doc)
      // would have no createdAt at all. Never throw parsing one bad/missing
      // entry and break the whole admin list for every other user.
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      status: json['authDisabled'] == true
          ? UserStatus.blocked
          : UserStatusX.fromJson(json['status'] as String?),
    );
  }

  @override
  String toString() => 'UserDirectoryEntry(status: ${status.name})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserDirectoryEntry &&
          other.uid == uid &&
          other.name == name &&
          other.email == email &&
          other.createdAt == createdAt &&
          other.status == status;

  @override
  int get hashCode => Object.hash(uid, name, email, createdAt, status);
}
