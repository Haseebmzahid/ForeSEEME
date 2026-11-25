import 'dart:async';

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
    try {
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

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          timeLimit: Duration(seconds: 15),
        ),
      );
      return LocationResult.granted(position.latitude, position.longitude);
    } on LocationServiceDisabledException {
      return const LocationResult.unavailable();
    } on PermissionDeniedException {
      return const LocationResult.denied();
    } on TimeoutException {
      return const LocationResult.noFix();
    } on PositionUpdateException {
      return const LocationResult.noFix();
    } on UnsupportedError {
      return const LocationResult.noFix();
    }
  }

  @override
  Stream<LocationResult> watchLocation() async* {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        yield const LocationResult.unavailable();
        return;
      }
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        yield const LocationResult.denied();
        return;
      }

      final updates = StreamController<LocationResult>();
      final positions =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              distanceFilter: 50,
            ),
          ).listen(
            (position) => updates.add(
              LocationResult.granted(position.latitude, position.longitude),
            ),
            onError: updates.addError,
            onDone: updates.close,
          );
      // The position stream may stay quiet after permission or service loss.
      var checking = false;
      final timer = Timer.periodic(const Duration(seconds: 15), (_) async {
        if (checking || updates.isClosed) return;
        checking = true;
        try {
          final enabled = await Geolocator.isLocationServiceEnabled();
          final permission = await Geolocator.checkPermission();
          if (updates.isClosed) return;
          if (!enabled) {
            updates.add(const LocationResult.unavailable());
          } else if (permission == LocationPermission.denied ||
              permission == LocationPermission.deniedForever) {
            updates.add(const LocationResult.denied());
          }
        } catch (error, stack) {
          if (!updates.isClosed) updates.addError(error, stack);
        } finally {
          checking = false;
        }
      });
      try {
        yield* updates.stream;
      } finally {
        timer.cancel();
        await positions.cancel();
        unawaited(updates.close());
      }
    } on LocationServiceDisabledException {
      yield const LocationResult.unavailable();
    } on PermissionDeniedException {
      yield const LocationResult.denied();
    }
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
