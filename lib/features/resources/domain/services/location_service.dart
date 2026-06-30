import 'package:fyp_foreseeme/features/resources/domain/models/location_result.dart';

/// Abstraction over device location (keeps `geolocator` out of domain/presentation).
abstract class LocationService {
  /// Requests permission as needed and returns the current location, or a
  /// denied/unavailable result — never throws for the permission path.
  Future<LocationResult> currentLocation();
}
