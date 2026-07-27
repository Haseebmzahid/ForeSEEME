import '../models/user_directory_entry.dart';

/// The admin user directory (Sprint M8.4, SDS FR8.5).
///
/// Mirrors [RiskOverrideRepository]: one interface for both the write side
/// (called by [AuthNotifier]/[HealthProfileNotifier] as a best-effort side
/// effect of account creation / profile completion) and the read side
/// (called by the admin surface). Writes are self-only, enforced server-side
/// by `firestore.rules`; reads are admin-only, same enforcement.
///
/// Deliberately does **not** expose suspend/block/delete — those need the
/// Firebase Auth Admin SDK, not Firestore, and ship as operator scripts
/// (`backend/scripts/set_user_status.py`, `delete_user.py`) instead. See
/// docs/user_management.md.
abstract class UserDirectoryRepository {
  /// Registers a newly created account. Called once, right after sign-up
  /// succeeds. Callers should treat a failure here as non-fatal to the
  /// account creation itself (mirrors [AdminOverrideController]'s activity-log
  /// pattern) — the directory is an admin convenience view, not a
  /// security-critical path.
  Future<void> register({required String uid, required String email, String? name});

  /// Marks [uid] as having completed health-profile setup at least once.
  /// Called once, on first-run profile save. Also non-fatal on failure.
  Future<void> markProfileActive(String uid);

  /// Every registered user, for the admin directory. Bounded, not paginated
  /// (matches this project's existing "cap the query window" choice for
  /// other admin-facing lists at this scale).
  Future<List<UserDirectoryEntry>> list({int limit = 200});
}
