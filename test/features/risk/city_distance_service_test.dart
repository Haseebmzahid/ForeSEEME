import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/risk/domain/constants/city_coordinates.dart';
import 'package:fyp_foreseeme/features/risk/domain/services/city_distance_service.dart';

void main() {
  group('haversineDistanceKm', () {
    test('a city to itself is zero', () {
      final lahore = kCityCoordinates['Lahore']!;
      expect(haversineDistanceKm(lahore, lahore), 0);
    });

    test('is symmetric', () {
      final lahore = kCityCoordinates['Lahore']!;
      final karachi = kCityCoordinates['Karachi']!;
      final ab = haversineDistanceKm(lahore, karachi);
      final ba = haversineDistanceKm(karachi, lahore);
      expect(ab, closeTo(ba, 0.0001));
    });

    test('Islamabad-Rawalpindi (twin cities) is a short real distance', () {
      final islamabad = kCityCoordinates['Islamabad']!;
      final rawalpindi = kCityCoordinates['Rawalpindi']!;
      final km = haversineDistanceKm(islamabad, rawalpindi);
      // Real-world twin-city distance is roughly 10-20km.
      expect(km, greaterThan(0));
      expect(km, lessThan(30));
    });

    test('Lahore-Karachi is a real long distance (roughly 1000+ km)', () {
      final lahore = kCityCoordinates['Lahore']!;
      final karachi = kCityCoordinates['Karachi']!;
      final km = haversineDistanceKm(lahore, karachi);
      expect(km, greaterThan(900));
      expect(km, lessThan(1200));
    });
  });

  group('nearestOtherCity', () {
    test('Islamabad\'s nearest other supported city is Rawalpindi', () {
      expect(nearestOtherCity('Islamabad'), 'Rawalpindi');
    });

    test('Rawalpindi\'s nearest other supported city is Islamabad', () {
      expect(nearestOtherCity('Rawalpindi'), 'Islamabad');
    });

    test('never returns the origin city itself', () {
      for (final city in kCityCoordinates.keys) {
        expect(nearestOtherCity(city), isNot(city));
      }
    });

    test('unsupported city → null', () {
      expect(nearestOtherCity('Multan'), isNull);
    });
  });
}
