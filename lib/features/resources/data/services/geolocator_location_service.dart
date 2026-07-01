import 'package:geolocator/geolocator.dart';

import 'package:fyp_foreseeme/features/resources/domain/models/location_result.dart';
import 'package:fyp_foreseeme/features/resources/domain/services/location_service.dart';

/// `geolocator`-backed [LocationService]. Translates the permission/service
/// state into a [LocationResult] and never throws for the permission path, so
/// callers can degrade gracefully (e.g. fall back to the user's city).
class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  @override
  Future<LocationResult> currentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const LocationResult.unavailable();
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return const LocationResult.denied();
    }

    final position = await Geolocator.getCurrentPosition();
    return LocationResult.granted(position.latitude, position.longitude);
  }

  @override
  Future<void> openAppSettings() async {
    await Geolocator.openAppSettings();
  }

  @override
  Future<void> openLocationServiceSettings() async {
    await Geolocator.openLocationSettings();
  }
}
