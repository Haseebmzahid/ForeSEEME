import 'package:fyp_foreseeme/core/utils/either.dart';
import 'package:fyp_foreseeme/features/health_profile/domain/exceptions/health_profile_exception.dart';
import 'package:fyp_foreseeme/features/health_profile/domain/models/health_profile_model.dart';

/// Contract for all health-profile persistence operations.
///
/// All methods return [Either<HealthProfileException, T>] so that callers
/// receive typed errors without needing to catch raw Firestore exceptions.
abstract class HealthProfileRepository {
  /// Fetch the profile for [uid], or [Left] if missing / error.
  Future<Either<HealthProfileException, HealthProfileModel?>> getProfile(
      String uid);

  /// Persist a complete [HealthProfileModel], preserving unrelated fields.
  Future<Either<HealthProfileException, void>> saveProfile(
      HealthProfileModel profile);

  /// Partially update the profile for [uid].
  /// Omitted fields are left unchanged in Firestore.
  Future<Either<HealthProfileException, void>> updateProfile(
    String uid, {
    String? city,
    List<String>? conditions,
    List<String>? customConditions,
  });
}
