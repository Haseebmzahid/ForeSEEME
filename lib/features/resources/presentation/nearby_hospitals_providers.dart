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

/// Maps/Places API key, injected at build time via
/// `--dart-define=MAPS_API_KEY=...` (kept out of tracked source). Empty when
/// unconfigured, which surfaces as a graceful "not configured" state.
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

/// Nearby hospitals for the user's current location, falling back to their city
/// centroid when device location is denied/unavailable (graceful, still useful).
///
/// Throws [PlacesNotConfiguredException] when no key is set and
/// [LocationUnavailableException] when neither location nor a city is known —
/// both rendered as informative states rather than crashes.
final nearbyHospitalsProvider = FutureProvider<NearbyHospitalsResult>((
  ref,
) async {
  if (ref.watch(placesApiKeyProvider).isEmpty) {
    throw const PlacesNotConfiguredException();
  }

  final location = await ref.watch(locationServiceProvider).currentLocation();

  double latitude;
  double longitude;
  if (location.status == LocationStatus.granted) {
    latitude = location.latitude!;
    longitude = location.longitude!;
  } else {
    final city = await ref.watch(userCityProvider.future);
    final coord = city != null ? kCityCoordinates[city] : null;
    if (coord == null) throw const LocationUnavailableException();
    latitude = coord.lat;
    longitude = coord.lon;
  }

  return ref
      .watch(placesRepositoryProvider)
      .nearbyHospitals(latitude: latitude, longitude: longitude);
});
