/// A nearby medical facility returned by the Places lookup.
class Hospital {
  final String id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;

  /// Dialable phone number, when Places provides one.
  final String? phoneNumber;

  /// Straight-line distance from the search origin, in kilometres.
  final double distanceKm;

  /// Average user rating (0–5), when Places provides one.
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
  });

  bool get hasPhone => phoneNumber != null && phoneNumber!.isNotEmpty;
  bool get hasRating => rating != null;
}
