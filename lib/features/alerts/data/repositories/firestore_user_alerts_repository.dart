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

  /// Per-user inbox items live at `userAlerts/{uid}/items`.
  CollectionReference<Map<String, dynamic>> _itemsRef(String uid) =>
      _firestore.collection('userAlerts').doc(uid).collection('items');

  @override
  Stream<List<UserAlertModel>> watchAlerts(String uid) {
    // Newest first: `createdAt` is a server Timestamp set by the engine, so it
    // sorts chronologically. A real-time snapshot keeps the inbox and its unread
    // badge live without a manual refresh.
    return _itemsRef(uid)
        .orderBy('createdAt', descending: true)
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
    final unread = await _itemsRef(
      uid,
    ).where('read', isEqualTo: false).get();
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
