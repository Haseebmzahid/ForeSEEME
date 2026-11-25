/// Outcome of a device-location request.
enum LocationStatus { granted, denied, unavailable, noFix }

/// A location lookup result. [latitude]/[longitude] are only set when
/// [status] is [LocationStatus.granted].
class LocationResult {
  final LocationStatus status;
  final double? latitude;
  final double? longitude;

  const LocationResult._(this.status, [this.latitude, this.longitude]);

  const LocationResult.granted(double latitude, double longitude)
    : this._(LocationStatus.granted, latitude, longitude);

  const LocationResult.denied() : this._(LocationStatus.denied);

  const LocationResult.unavailable() : this._(LocationStatus.unavailable);

  const LocationResult.noFix() : this._(LocationStatus.noFix);

  bool get hasValidFix =>
      status == LocationStatus.granted &&
      latitude != null &&
      longitude != null &&
      latitude!.isFinite &&
      longitude!.isFinite &&
      latitude!.abs() <= 90 &&
      longitude!.abs() <= 180;
}
