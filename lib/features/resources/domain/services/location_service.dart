import 'package:fyp_foreseeme/features/resources/domain/models/location_result.dart';

/// Abstraction over device location (keeps `geolocator` out of domain/presentation).
abstract class LocationService {
  /// Requests permission as needed and returns the current location, or a
  /// denied/unavailable result — never throws for the permission path.
  Future<LocationResult> currentLocation();

  /// Opens the OS app-settings screen so the user can grant location permission.
  Future<void> openAppSettings();

  /// Opens the OS location-services screen so the user can turn location on.
  Future<void> openLocationServiceSettings();
}
