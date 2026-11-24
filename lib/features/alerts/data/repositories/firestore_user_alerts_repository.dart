import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/user_alert.dart';
import '../../domain/repositories/user_alerts_repository.dart';

/// Firestore implementation of [UserAlertsRepository].
///
/// Reads the owner's `userAlerts/{uid}/items` subcollection and marks single
/// alerts read. The subcollection is populated exclusively by the backend
/// dispatch engine via the Admin SDK (`docs/alert_dispatch_design.md`); the app
/// never creates or deletes entries — the Firestore rules enforce this.
class FirestoreUserAlertsRepository implements UserAlertsRepository {
  final FirebaseFirestore _firestore;

  FirestoreUserAlertsRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Inbox display window (Sprint 6A, S6A-08): a deliberate scale decision,
  /// not backend pagination. At FYP scale a user accumulates at most a
  /// handful of risk alerts a week, so 50 is generously beyond what anyone
  /// will realistically have unread/recent at once. If the inbox ever needs
  /// to show more, the fix is cursor-based pagination on this same query —
  /// not raising this constant indefinitely.
  static const int _inboxWindowSize = 50;

  /// Per-user inbox items live at `userAlerts/{uid}/items`.
  CollectionReference<Map<String, dynamic>> _itemsRef(String uid) =>
      _firestore.collection('userAlerts').doc(uid).collection('items');

  @override
  Future<UserAlertModel?> getAlertForPush(String uid, String pushId) async {
    final snapshot = await _itemsRef(uid)
        .where('pushId', isEqualTo: pushId)
        .limit(1)
        .get(const GetOptions(source: Source.server));
    final doc = snapshot.docs.firstOrNull;
    return doc == null ? null : UserAlertModel.fromJson(doc.id, doc.data());
  }

  @override
  Stream<List<UserAlertModel>> watchAlerts(String uid) {
    // Newest first: `createdAt` is a server Timestamp set by the engine, so it
    // sorts chronologically. A real-time snapshot keeps the inbox and its unread
    // badge live without a manual refresh. Capped at `_inboxWindowSize` — see
    // its doc comment; `markAllRead` below intentionally has no such cap since
    // it must act on every unread doc, not just the displayed window.
    return _itemsRef(uid)
        .orderBy('createdAt', descending: true)
        .limit(_inboxWindowSize)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => UserAlertModel.fromJson(doc.id, doc.data()))
              .toList(),
        );
  }

  @override
  Future<void> markRead(String uid, String alertId) async {
    // Only `read`/`readAt` may change (owner mark-read rule §6). `readAt` uses a
    // server timestamp so it matches the engine's write convention.
    await _itemsRef(uid).doc(alertId).update({
      'read': true,
      'readAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> markAllRead(String uid) async {
    // Same two fields as markRead, applied to every currently-unread doc in
    // one batch — still within the owner mark-read rule §6 (no new field, no
    // new permission, one write per doc exactly as a loop of markRead would
    // produce, just atomic).
    final unread = await _itemsRef(uid).where('read', isEqualTo: false).get();
    if (unread.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in unread.docs) {
      batch.update(doc.reference, {
        'read': true,
        'readAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
}
