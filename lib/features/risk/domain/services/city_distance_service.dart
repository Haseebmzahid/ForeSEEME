// Pure-Dart great-circle distance between the app's fixed city centroids.
//
// Framework-free (`dart:math` only — no Flutter, no location SDK), mirroring
// `aqi_band.dart` / `risk_trend_service.dart`. This is a real geometric
// calculation over [kCityCoordinates] — never a fabricated "nearby region";
// with only 5 supported cities, "nearby" always means the closest OTHER
// supported city by true distance.

import 'dart:math';

import 'package:fyp_foreseeme/features/risk/domain/constants/city_coordinates.dart';

const double _earthRadiusKm = 6371.0;

double _toRadians(double degrees) => degrees * pi / 180;

/// Great-circle (Haversine) distance between two city centroids, in km.
double haversineDistanceKm(CityCoordinate a, CityCoordinate b) {
  final dLat = _toRadians(b.lat - a.lat);
  final dLon = _toRadians(b.lon - a.lon);
  final lat1 = _toRadians(a.lat);
  final lat2 = _toRadians(b.lat);

  final h =
      sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2);
  final c = 2 * atan2(sqrt(h), sqrt(1 - h));
  return _earthRadiusKm * c;
}

/// The closest OTHER supported city to [from], by real distance — or `null`
/// when [from] isn't a supported city or it's the only one on record.
String? nearestOtherCity(String from) {
  final origin = kCityCoordinates[from];
  if (origin == null) return null;

  String? best;
  var bestDistance = double.infinity;
  for (final entry in kCityCoordinates.entries) {
    if (entry.key == from) continue;
    final distance = haversineDistanceKm(origin, entry.value);
    if (distance < bestDistance) {
      bestDistance = distance;
      best = entry.key;
    }
  }
  return best;
}
