import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:fyp_foreseeme/features/auth/domain/models/user_directory_entry.dart';
import 'package:fyp_foreseeme/features/auth/domain/repositories/user_directory_repository.dart';

/// Firestore implementation of [UserDirectoryRepository].
///
/// [_firestore] is resolved lazily (not in the constructor) — mirrors the
/// fix applied to `FirestoreResourceRepository` in Sprint M8.3: this
/// repository's write methods are invoked from [AuthNotifier]/
/// [HealthProfileNotifier] as a background side effect on every real sign-up
/// and profile save, including in widget tests that construct those
/// notifiers without ever overriding this provider. An eager
/// `FirebaseFirestore.instance` in the constructor would make those tests
/// depend on Firebase just to build, not just to exercise this path.
class FirestoreUserDirectoryRepository implements UserDirectoryRepository {
  final FirebaseFirestore? _firestoreOverride;

  const FirestoreUserDirectoryRepository({FirebaseFirestore? firestore})
    : _firestoreOverride = firestore;

  FirebaseFirestore get _firestore => _firestoreOverride ?? FirebaseFirestore.instance;

  static const String collectionPath = 'userDirectory';

  @override
  Future<void> register({
    required String uid,
    required String email,
    String? name,
  }) async {
    await _firestore.collection(collectionPath).doc(uid).set({
      'email': email,
      if (name != null && name.isNotEmpty) 'name': name,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'status': 'pending',
    });
  }

  @override
  Future<void> markProfileActive(String uid) async {
    // Merge-set so an edit-mode re-save (which does not call this) or a
    // repeated first-run save never wipes name/email/createdAt.
    await _firestore.collection(collectionPath).doc(uid).set(
      {'status': 'active'},
      SetOptions(merge: true),
    );
  }

  @override
  Future<List<UserDirectoryEntry>> list({int limit = 200}) async {
    final snapshot = await _firestore
        .collection(collectionPath)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snapshot.docs
        .map((doc) => UserDirectoryEntry.fromJson(doc.data(), uid: doc.id))
        .toList();
  }
}
