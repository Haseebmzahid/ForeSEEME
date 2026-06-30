import 'package:fyp_foreseeme/features/resources/domain/models/nearby_hospitals_result.dart';

/// Read interface for nearby-facility lookups (Google Places).
///
/// Implementations MUST cache (a TTL) and guard live-call volume to control
/// cost, since the key is client-side and each call is billable.
abstract class PlacesRepository {
  /// Hospitals near ([latitude], [longitude]). Served from cache within the TTL;
  /// otherwise a (budget-guarded) live call. Throws on request/quota failure.
  Future<NearbyHospitalsResult> nearbyHospitals({
    required double latitude,
    required double longitude,
  });
}
