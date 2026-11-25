import 'dart:math' as math;

enum FacilityKind {
  hospital('Hospital'),
  clinic('Clinic'),
  other('Healthcare facility');

  const FacilityKind(this.label);

  final String label;
}

/// A nearby medical facility returned by the Places lookup.
class Hospital {
  final String id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final FacilityKind kind;

  /// Dialable phone number, when Places provides one.
  final String? phoneNumber;

  /// Straight-line distance from the search origin, in kilometres.
  final double distanceKm;

  /// Average user rating (0â€“5), when Places provides one.
  final double? rating;

  /// Number of user ratings behind [rating], when available.
  final int? userRatingCount;

  /// Whether the facility is open now, when Places provides opening hours.
  final bool? openNow;

  const Hospital({
    required this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.distanceKm,
    this.phoneNumber,
    this.rating,
    this.userRatingCount,
    this.openNow,
    this.kind = FacilityKind.hospital,
  });

  static final _dialable = RegExp(r'^\+?[0-9(). -]+$');
  static final _digit = RegExp(r'[0-9]');

  bool get hasPhone {
    final number = phoneNumber?.trim();
    return number != null &&
        _dialable.hasMatch(number) &&
        _digit.allMatches(number).length >= 3;
  }

  Hospital measuredFrom(double latitude, double longitude) => Hospital(
    id: id,
    name: name,
    address: address,
    latitude: this.latitude,
    longitude: this.longitude,
    distanceKm: distanceBetweenKm(
      latitude,
      longitude,
      this.latitude,
      this.longitude,
    ),
    phoneNumber: phoneNumber,
    rating: rating,
    userRatingCount: userRatingCount,
    openNow: openNow,
    kind: kind,
  );
  bool get hasRating => rating != null;
}

/// Great-circle distance in kilometres.
double distanceBetweenKm(
  double lat1,
  double lon1,
  double lat2,
  double lon2,
) {
  const earthRadiusKm = 6371.0;
  double toRad(double d) => d * math.pi / 180.0;
  final dLat = toRad(lat2 - lat1);
  final dLon = toRad(lon2 - lon1);
  final haversine =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(toRad(lat1)) *
          math.cos(toRad(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  final a = haversine.clamp(0.0, 1.0);
  return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}
