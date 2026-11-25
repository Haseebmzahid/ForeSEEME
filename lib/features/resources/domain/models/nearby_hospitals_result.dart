import 'package:fyp_foreseeme/features/resources/domain/models/hospital.dart';

import 'location_result.dart';

/// Result of a nearby-hospitals lookup, including cache provenance so the UI can
/// show "Cached N min ago".
class NearbyHospitalsResult {
  final List<Hospital> hospitals;

  /// When the underlying live fetch happened (cache timestamp when served from
  /// cache).
  final DateTime fetchedAt;

  /// True when these results came from the cache rather than a fresh API call.
  final bool servedFromCache;

  /// Latest GPS fix. City-only results have no device position.
  final LocationResult? devicePosition;

  const NearbyHospitalsResult({
    required this.hospitals,
    required this.fetchedAt,
    required this.servedFromCache,
    this.devicePosition,
  });
  NearbyHospitalsResult measuredFrom(
    double latitude,
    double longitude, {
    LocationResult? devicePosition,
  }) => NearbyHospitalsResult(
    hospitals: hospitals
        .map((h) => h.measuredFrom(latitude, longitude))
        .toList(),
    fetchedAt: fetchedAt,
    servedFromCache: servedFromCache,
    devicePosition: devicePosition,
  );
}
