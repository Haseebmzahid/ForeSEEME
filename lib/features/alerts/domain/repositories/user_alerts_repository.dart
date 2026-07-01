import '../models/user_alert.dart';

/// Abstract interface for the in-app alert inbox (Sprint 4, Prompt 5).
///
/// Pure, read-oriented data operations, mirroring [MedicationRepository] /
/// [RiskRepository]. The inbox is user-scoped: every method takes the owner
/// [uid] and the Firestore rule (`docs/alert_dispatch_design.md` §6) guarantees a
/// signed-in user can only read and mark-read their own `userAlerts` subtree.
/// The engine (Admin SDK) is the only creator; this interface never creates,
/// deletes, or edits alert content.
abstract class UserAlertsRepository {
  /// Real-time stream of the user's alerts, newest first.
  ///
  /// Backs the inbox list so a freshly delivered alert appears without a manual
  /// refresh, and a mark-read reflects immediately.
  Stream<List<UserAlertModel>> watchAlerts(String uid);

  /// Marks a single alert read (sets `read = true`, `readAt = now`).
  ///
  /// The Firestore rule permits the owner to change only `read`/`readAt`, so
  /// this is the sole permitted mutation from the client.
  Future<void> markRead(String uid, String alertId);
}
