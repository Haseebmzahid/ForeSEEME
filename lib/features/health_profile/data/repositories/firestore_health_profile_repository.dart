import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fyp_foreseeme/core/utils/either.dart';
import 'package:fyp_foreseeme/features/health_profile/domain/exceptions/health_profile_exception.dart';
import 'package:fyp_foreseeme/features/health_profile/domain/models/health_profile_model.dart';
import 'package:fyp_foreseeme/features/health_profile/domain/repositories/health_profile_repository.dart';

/// Firestore-backed implementation of [HealthProfileRepository].
///
/// Document path: `users/{uid}/profile`  (single sub-document, not a collection)
class FirestoreHealthProfileRepository implements HealthProfileRepository {
  final FirebaseFirestore _firestore;

  FirestoreHealthProfileRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  // ── Internal helpers ───────────────────────────────────────────────────────

  /// Returns the Firestore document reference for `users/{uid}/profile/{uid}`.
  DocumentReference<Map<String, dynamic>> _profileDoc(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('profile')
        .doc(uid);
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  @override
  Future<Either<HealthProfileException, HealthProfileModel?>> getProfile(
    String uid,
  ) async {
    try {
      final docRef = _profileDoc(uid);
      final snapshot = await docRef.get();
      debugPrint(
        'FirestoreHealthProfileRepository: Profile document exists: ${snapshot.exists}',
      );

      if (!snapshot.exists || snapshot.data() == null) {
        return const Right(null);
      }

      final model = HealthProfileModel.fromJson(uid, snapshot.data()!);
      return Right(model);
    } on FirebaseException catch (e) {
      debugPrint(
        'FirestoreHealthProfileRepository: FirebaseException in getProfile: ${e.message} (code: ${e.code})',
      );
      return Left(
        HealthProfileException(
          e.message ?? 'Failed to fetch health profile',
          e.code,
        ),
      );
    } catch (e) {
      debugPrint(
        'FirestoreHealthProfileRepository: Unknown exception in getProfile: $e',
      );
      return Left(HealthProfileException(e.toString()));
    }
  }

  @override
  Future<Either<HealthProfileException, void>> saveProfile(
    HealthProfileModel profile,
  ) async {
    try {
      final docRef = _profileDoc(profile.uid);
      await docRef.set(profile.toJson());
      debugPrint(
        'FirestoreHealthProfileRepository: Successfully saved profile.',
      );
      return const Right(null);
    } on FirebaseException catch (e) {
      debugPrint(
        'FirestoreHealthProfileRepository: FirebaseException in saveProfile: ${e.message} (code: ${e.code})',
      );
      return Left(
        HealthProfileException(
          e.message ?? 'Failed to save health profile',
          e.code,
        ),
      );
    } catch (e) {
      debugPrint(
        'FirestoreHealthProfileRepository: Unknown exception in saveProfile: $e',
      );
      return Left(HealthProfileException(e.toString()));
    }
  }

  @override
  Future<Either<HealthProfileException, void>> updateProfile(
    String uid, {
    String? city,
    List<String>? conditions,
  }) async {
    try {
      final updates = <String, dynamic>{
        'lastUpdated': FieldValue.serverTimestamp(),
      };
      if (city != null) updates['city'] = city;
      if (conditions != null) updates['chronicConditions'] = conditions;

      final docRef = _profileDoc(uid);
      // Use merge-set so we never wipe fields we didn't touch
      await docRef.set(updates, SetOptions(merge: true));
      debugPrint(
        'FirestoreHealthProfileRepository: Successfully updated profile.',
      );
      return const Right(null);
    } on FirebaseException catch (e) {
      debugPrint(
        'FirestoreHealthProfileRepository: FirebaseException in updateProfile: ${e.message} (code: ${e.code})',
      );
      return Left(
        HealthProfileException(
          e.message ?? 'Failed to update health profile',
          e.code,
        ),
      );
    } catch (e) {
      debugPrint(
        'FirestoreHealthProfileRepository: Unknown exception in updateProfile: $e',
      );
      return Left(HealthProfileException(e.toString()));
    }
  }
}
