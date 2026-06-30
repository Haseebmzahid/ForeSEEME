/// Persists the device FCM token for a user (Sprint 4 alert delivery will read
/// it). Write-only here — no dispatch.
abstract class FcmTokenRepository {
  /// Upserts [token] onto `users/{uid}` (with a refresh timestamp).
  Future<void> saveToken(String uid, String token);
}
