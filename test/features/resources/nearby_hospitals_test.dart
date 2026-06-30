import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/resources/data/repositories/google_places_repository.dart';
import 'package:fyp_foreseeme/features/resources/domain/exceptions/places_exception.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/hospital.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/location_result.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/nearby_hospitals_result.dart';
import 'package:fyp_foreseeme/features/resources/domain/repositories/places_repository.dart';
import 'package:fyp_foreseeme/features/resources/domain/services/location_service.dart';
import 'package:fyp_foreseeme/features/resources/presentation/nearby_hospitals_providers.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/hospital_list.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/nearby_hospitals_entry.dart';

const _placesBody = '''
{"places":[
  {"id":"a","displayName":{"text":"Mayo Hospital"},
   "formattedAddress":"Anarkali, Lahore","location":{"latitude":31.58,"longitude":74.31},
   "nationalPhoneNumber":"042111"},
  {"id":"b","displayName":{"text":"Services Hospital"},
   "formattedAddress":"Jail Road, Lahore","location":{"latitude":31.52,"longitude":74.34}}
]}''';

Hospital _hospital(String name, {String? phone, double distance = 1.2}) =>
    Hospital(
      id: name,
      name: name,
      address: '$name Road',
      latitude: 31.5,
      longitude: 74.3,
      distanceKm: distance,
      phoneNumber: phone,
    );

class _FakeLocationService implements LocationService {
  final LocationResult result;
  const _FakeLocationService(this.result);
  @override
  Future<LocationResult> currentLocation() async => result;
}

class _RecordingPlacesRepository implements PlacesRepository {
  double? latitude;
  double? longitude;

  @override
  Future<NearbyHospitalsResult> nearbyHospitals({
    required double latitude,
    required double longitude,
  }) async {
    this.latitude = latitude;
    this.longitude = longitude;
    return NearbyHospitalsResult(
      hospitals: [_hospital('Mayo Hospital', phone: '042111')],
      fetchedAt: DateTime.utc(2026, 6, 30),
      servedFromCache: false,
    );
  }
}

void main() {
  group('GooglePlacesRepository caching & quota', () {
    late DateTime clock;
    late int calls;

    setUp(() {
      clock = DateTime.utc(2026, 6, 30, 12, 0);
      calls = 0;
    });

    http.Client client(String body, {int status = 200}) =>
        MockClient((_) async {
          calls++;
          return http.Response(body, status);
        });

    test('cache miss fetches, parses and sorts by distance', () async {
      final repo = GooglePlacesRepository(
        apiKey: 'k',
        client: client(_placesBody),
        now: () => clock,
      );

      final result = await repo.nearbyHospitals(
        latitude: 31.5497,
        longitude: 74.3436,
      );

      expect(calls, 1);
      expect(result.servedFromCache, isFalse);
      expect(result.hospitals.length, 2);
      expect(
        result.hospitals.first.distanceKm,
        lessThanOrEqualTo(result.hospitals.last.distanceKm),
      );
    });

    test('cache hit within TTL makes no second call', () async {
      final repo = GooglePlacesRepository(
        apiKey: 'k',
        client: client(_placesBody),
        now: () => clock,
        ttl: const Duration(minutes: 15),
      );

      await repo.nearbyHospitals(latitude: 31.5497, longitude: 74.3436);
      final second = await repo.nearbyHospitals(
        latitude: 31.5497,
        longitude: 74.3436,
      );

      expect(calls, 1); // no duplicate live call
      expect(second.servedFromCache, isTrue);
    });

    test('cache expires after TTL', () async {
      final repo = GooglePlacesRepository(
        apiKey: 'k',
        client: client(_placesBody),
        now: () => clock,
        ttl: const Duration(minutes: 15),
      );

      await repo.nearbyHospitals(latitude: 31.5497, longitude: 74.3436);
      clock = clock.add(const Duration(minutes: 16));
      await repo.nearbyHospitals(latitude: 31.5497, longitude: 74.3436);

      expect(calls, 2);
    });

    test('non-200 throws PlacesRequestException', () async {
      final repo = GooglePlacesRepository(
        apiKey: 'k',
        client: client('{"error":"denied"}', status: 403),
        now: () => clock,
      );

      expect(
        () => repo.nearbyHospitals(latitude: 1, longitude: 1),
        throwsA(isA<PlacesRequestException>()),
      );
    });

    test('quota guard: spent budget + no cache -> throws', () async {
      final repo = GooglePlacesRepository(
        apiKey: 'k',
        client: client(_placesBody),
        now: () => clock,
        maxLiveCalls: 1,
      );

      await repo.nearbyHospitals(latitude: 10, longitude: 10); // spends budget
      expect(
        () => repo.nearbyHospitals(latitude: 50, longitude: 50),
        throwsA(isA<PlacesQuotaExceededException>()),
      );
    });

    test('empty key throws PlacesNotConfiguredException', () async {
      final repo = GooglePlacesRepository(apiKey: '', client: client(''));
      expect(
        () => repo.nearbyHospitals(latitude: 1, longitude: 1),
        throwsA(isA<PlacesNotConfiguredException>()),
      );
    });
  });

  group('nearbyHospitalsProvider location resolution', () {
    ProviderContainer drive(ProviderContainer container) {
      addTearDown(container.dispose);
      container.listen(
        nearbyHospitalsProvider,
        (_, _) {},
        onError: (_, _) {},
        fireImmediately: true,
      );
      return container;
    }

    test('granted location is used directly', () async {
      final repo = _RecordingPlacesRepository();
      final container = drive(
        ProviderContainer(
          overrides: [
            placesApiKeyProvider.overrideWithValue('k'),
            locationServiceProvider.overrideWithValue(
              const _FakeLocationService(LocationResult.granted(24.86, 67.00)),
            ),
            placesRepositoryProvider.overrideWithValue(repo),
          ],
        ),
      );

      final result = await container.read(nearbyHospitalsProvider.future);

      expect(result.hospitals, isNotEmpty);
      expect(repo.latitude, 24.86);
      expect(repo.longitude, 67.00);
    });

    test('denied location falls back to the user city centroid', () async {
      final repo = _RecordingPlacesRepository();
      final container = drive(
        ProviderContainer(
          overrides: [
            placesApiKeyProvider.overrideWithValue('k'),
            locationServiceProvider.overrideWithValue(
              const _FakeLocationService(LocationResult.denied()),
            ),
            userCityProvider.overrideWith((ref) => 'Lahore'),
            placesRepositoryProvider.overrideWithValue(repo),
          ],
        ),
      );

      await container.read(nearbyHospitalsProvider.future);

      expect(repo.latitude, 31.5497); // Lahore centroid (cities.yaml parity)
      expect(repo.longitude, 74.3436);
    });

    test('denied location + no city -> LocationUnavailableException', () async {
      final container = ProviderContainer(
        overrides: [
          placesApiKeyProvider.overrideWithValue('k'),
          locationServiceProvider.overrideWithValue(
            const _FakeLocationService(LocationResult.denied()),
          ),
          userCityProvider.overrideWith((ref) => null),
          placesRepositoryProvider.overrideWithValue(
            _RecordingPlacesRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.listen(
        nearbyHospitalsProvider,
        (_, _) {},
        onError: (_, _) {},
        fireImmediately: true,
      );
      await pumpEventQueue(times: 20);

      final state = container.read(nearbyHospitalsProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isA<LocationUnavailableException>());
    });
  });

  group('HospitalList', () {
    testWidgets('renders cards and wires Call / Directions', (tester) async {
      Hospital? called;
      Hospital? directed;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HospitalList(
              hospitals: [
                _hospital('Mayo Hospital', phone: '042111', distance: 1.2),
                _hospital('Services Hospital', phone: '042222', distance: 2.8),
              ],
              onCall: (h) => called = h,
              onDirections: (h) => directed = h,
            ),
          ),
        ),
      );

      expect(find.text('Mayo Hospital'), findsOneWidget);
      expect(find.text('Services Hospital'), findsOneWidget);
      expect(find.textContaining('1.2 km'), findsOneWidget);

      await tester.tap(find.text('Call').first);
      expect(called?.name, 'Mayo Hospital');

      await tester.tap(find.text('Directions').first);
      expect(directed?.name, 'Mayo Hospital');
    });

    testWidgets('Call is disabled when the hospital has no phone', (
      tester,
    ) async {
      var called = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HospitalList(
              hospitals: [_hospital('No Phone Clinic', phone: null)],
              onCall: (_) => called = true,
              onDirections: (_) {},
            ),
          ),
        ),
      );

      await tester.tap(find.text('Call'));
      expect(called, isFalse);
    });
  });

  group('NearbyHospitalsEntry', () {
    testWidgets('prominent explains the High-risk surfacing and taps', (
      tester,
    ) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NearbyHospitalsEntry(
              prominent: true,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Nearby hospitals'), findsOneWidget);
      expect(
        find.text('Surfaced because risk is High in your area'),
        findsOneWidget,
      );

      await tester.tap(find.byType(NearbyHospitalsEntry));
      expect(tapped, isTrue);
    });

    testWidgets('teaser omits the High-risk explanation', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NearbyHospitalsEntry(prominent: false, onTap: () {}),
          ),
        ),
      );

      expect(find.text('Nearby hospitals'), findsOneWidget);
      expect(
        find.text('Surfaced because risk is High in your area'),
        findsNothing,
      );
    });
  });
}
