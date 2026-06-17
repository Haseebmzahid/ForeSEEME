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

  /// Returns the Firestore document reference for `users/{uid}/profile`.
  DocumentReference<Map<String, dynamic>> _profileDoc(String uid) =>
      _firestore.collection('users').doc(uid).collection('profile').doc('data');

  // ── Public API ─────────────────────────────────────────────────────────────

  @override
  Future<Either<HealthProfileException, HealthProfileModel?>> getProfile(
      String uid) async {
    try {
      final snapshot = await _profileDoc(uid).get();

      if (!snapshot.exists || snapshot.data() == null) {
        return const Right(null);
      }

      final model = HealthProfileModel.fromJson(uid, snapshot.data()!);
      return Right(model);
    } on FirebaseException catch (e) {
      return Left(HealthProfileException(
        e.message ?? 'Failed to fetch health profile',
        e.code,
      ));
    } catch (e) {
      return Left(HealthProfileException(e.toString()));
    }
  }

  @override
  Future<Either<HealthProfileException, void>> saveProfile(
      HealthProfileModel profile) async {
    try {
      await _profileDoc(profile.uid).set(profile.toJson());
      return const Right(null);
    } on FirebaseException catch (e) {
      return Left(HealthProfileException(
        e.message ?? 'Failed to save health profile',
        e.code,
      ));
    } catch (e) {
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

      // Use merge-set so we never wipe fields we didn't touch
      await _profileDoc(uid).set(updates, SetOptions(merge: true));
      return const Right(null);
    } on FirebaseException catch (e) {
      return Left(HealthProfileException(
        e.message ?? 'Failed to update health profile',
        e.code,
      ));
    } catch (e) {
      return Left(HealthProfileException(e.toString()));
    }
  }
}
