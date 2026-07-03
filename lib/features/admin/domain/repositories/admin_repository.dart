/// Authorisation gate for the operator-only admin surface (Sprint 5, Prompt 13).
///
/// Pure data interface (mirrors [AuthRepository]); the Firebase Auth SDK stays in
/// the implementation. The in-app admin surface uses this only to *show/hide*
/// itself — the authoritative enforcement is server-side in `firestore.rules`
/// (an `admin` custom claim), so a spoofed client can never actually write an
/// override even if it forced the screen open.
abstract class AdminRepository {
  /// Whether the currently signed-in user carries the `admin` custom claim.
  /// Returns `false` when signed out. Implementations should force-refresh the
  /// ID token so a freshly granted/revoked claim is reflected.
  Future<bool> isCurrentUserAdmin();
}
