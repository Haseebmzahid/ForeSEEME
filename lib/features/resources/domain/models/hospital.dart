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

  const Hospital({
    required this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.distanceKm,
    this.phoneNumber,
  });
}
