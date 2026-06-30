import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:fyp_foreseeme/features/alerts/domain/models/notification_preferences.dart';
import 'package:fyp_foreseeme/features/alerts/domain/repositories/notification_preferences_repository.dart';

/// Stores preferences in the `notificationPreferences` field on `users/{uid}`
/// (same document as `fcmToken`), via `set(..., merge: true)`. The Firestore
/// rule allows a user to write only their own document.
class FirestoreNotificationPreferencesRepository
    implements NotificationPreferencesRepository {
  final FirebaseFirestore _firestore;

  FirestoreNotificationPreferencesRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  @override
  Future<NotificationPreferences> load(String uid) async {
    final snapshot = await _firestore.collection('users').doc(uid).get();
    final raw = snapshot.data()?['notificationPreferences'];
    return NotificationPreferences.fromJson(
      raw is Map ? raw.cast<String, dynamic>() : null,
    );
  }

  @override
  Future<void> save(String uid, NotificationPreferences preferences) async {
    await _firestore.collection('users').doc(uid).set({
      'notificationPreferences': preferences.toJson(),
    }, SetOptions(merge: true));
  }
}
