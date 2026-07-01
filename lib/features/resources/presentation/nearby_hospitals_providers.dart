import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/resources/data/repositories/google_places_repository.dart';
import 'package:fyp_foreseeme/features/resources/data/services/geolocator_location_service.dart';
import 'package:fyp_foreseeme/features/resources/domain/exceptions/places_exception.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/location_result.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/nearby_hospitals_result.dart';
import 'package:fyp_foreseeme/features/resources/domain/repositories/places_repository.dart';
import 'package:fyp_foreseeme/features/resources/domain/services/location_service.dart';
import 'package:fyp_foreseeme/features/risk/domain/constants/city_coordinates.dart';

/// Maps/Places API key. Resolved once at startup (dart-define → native manifest,
/// see `resolveMapsApiKey`) and injected via `overrideWithValue` in `main`. The
/// default here is the compile-time define so tests/tools still work.
final placesApiKeyProvider = Provider<String>((ref) {
  return const String.fromEnvironment('MAPS_API_KEY');
});

/// Concrete [PlacesRepository] (cached + quota-guarded). Overridable in tests.
final placesRepositoryProvider = Provider<PlacesRepository>((ref) {
  return GooglePlacesRepository(apiKey: ref.watch(placesApiKeyProvider));
});

/// Device location service. Overridable in tests.
final locationServiceProvider = Provider<LocationService>((ref) {
  return const GeolocatorLocationService();
});

/// When true, the search is centred on the user's profile city instead of the
/// device location — set when the user chooses "search near my city" after a
/// permission denial. Reset on a full retry so device location is tried again.
class CityFallbackNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void useCity() => state = true;
  void reset() => state = false;
}

final cityFallbackRequestedProvider =
    NotifierProvider<CityFallbackNotifier, bool>(CityFallbackNotifier.new);

/// Nearby hospitals for the user's current location.
///
/// Surfaces each failure as a distinct, real runtime condition:
/// * [LocationPermissionDeniedException] — location denied / services off
///   (carrying the profile city so the UI can offer a fallback);
/// * [LocationUnavailableException] — no location and no city to fall back to;
/// * [PlacesNetworkException] — offline / transport failure;
/// * [PlacesRequestException] / [PlacesQuotaExceededException] — API errors.
/// There is **no** "not configured" state: the key is resolved at startup, and an
/// empty key degrades to a normal error, not a placeholder screen.
final nearbyHospitalsProvider = FutureProvider<NearbyHospitalsResult>((
  ref,
) async {
  if (ref.watch(placesApiKeyProvider).isEmpty) {
    // Misconfiguration is treated as a plain API error (retryable), never a
    // "coming soon"/"not configured" placeholder.
    throw const PlacesRequestException(401, 'Missing Maps/Places API key');
  }

  final (latitude, longitude) = await _resolveOrigin(ref);

  return ref
      .watch(placesRepositoryProvider)
      .nearbyHospitals(latitude: latitude, longitude: longitude);
});

/// Resolves the search origin from the device location, or the profile-city
/// centroid when the user has explicitly requested the city fallback.
Future<(double, double)> _resolveOrigin(Ref ref) async {
  if (ref.watch(cityFallbackRequestedProvider)) {
    return _cityOrigin(ref);
  }

  final location = await ref.watch(locationServiceProvider).currentLocation();
  if (location.status == LocationStatus.granted) {
    return (location.latitude!, location.longitude!);
  }

  // Denied or services-off: surface a permission state, carrying the city so the
  // UI can offer "search near my city".
  final city = await ref.watch(userCityProvider.future);
  throw LocationPermissionDeniedException(
    fallbackCity: city,
    servicesDisabled: location.status == LocationStatus.unavailable,
  );
}

Future<(double, double)> _cityOrigin(Ref ref) async {
  final city = await ref.watch(userCityProvider.future);
  final coord = city != null ? kCityCoordinates[city] : null;
  if (coord == null) throw const LocationUnavailableException();
  return (coord.lat, coord.lon);
}
