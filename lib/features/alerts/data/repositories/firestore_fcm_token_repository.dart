import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:fyp_foreseeme/features/alerts/domain/repositories/fcm_token_repository.dart';

/// Writes the FCM token onto the user's own `users/{uid}` document.
///
/// Uses `set(..., merge: true)` so it never clobbers other user fields (profile
/// lives in a subcollection; `notificationPreferences` is added in Prompt 8).
/// The Firestore rule allows a user to write only their own document.
class FirestoreFcmTokenRepository implements FcmTokenRepository {
  final FirebaseFirestore _firestore;

  FirestoreFcmTokenRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  @override
  Future<void> saveToken(String uid, String token) async {
    await _firestore.collection('users').doc(uid).set({
      'fcmToken': token,
      'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
