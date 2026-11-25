import 'dart:async';
import 'dart:convert';

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
import 'package:fyp_foreseeme/features/resources/presentation/nearby_care_tracking.dart';
import 'package:fyp_foreseeme/features/resources/presentation/nearby_hospitals_providers.dart';
import 'package:fyp_foreseeme/features/resources/presentation/nearby_hospitals_screen.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/hospital_detail_sheet.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/hospital_list.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/hospitals_map_screen.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/nearby_hospitals_entry.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';

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
  const _FakeLocationService(this.result, {this.fixes});
  final Stream<LocationResult>? fixes;
  @override
  Future<LocationResult> currentLocation() async => result;
  @override
  Stream<LocationResult> watchLocation() => fixes ?? Stream.multi((_) {});
  @override
  Future<void> openAppSettings() async {}
  @override
  Future<void> openLocationServiceSettings() async {}
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
  test('automatic map recentering ignores GPS noise and frequent moves', () {
    const initial = LocationResult.granted(31.5, 74.3);
    const nearby = LocationResult.granted(31.501, 74.3);
    const moved = LocationResult.granted(31.51, 74.3);
    const quiet = Duration(seconds: 8);
    expect(
      nearbyCareCameraTarget(
        previous: initial,
        position: nearby,
        elapsed: quiet,
      ),
      isNull,
    );
    expect(
      nearbyCareCameraTarget(
        previous: initial,
        position: moved,
        elapsed: Duration.zero,
      ),
      isNull,
    );
    final target = nearbyCareCameraTarget(
      previous: initial,
      position: moved,
      elapsed: quiet,
    )!;
    expect(target.latitude, moved.latitude);
    expect(target.longitude, moved.longitude);
  });

  test('call affordance needs a dialable provider number', () {
    expect(_hospital('A', phone: ' unavailable ').hasPhone, isFalse);
    expect(_hospital('B', phone: ' +92 (42) 123-4567 ').hasPhone, isTrue);
  });

  for (final streamError in [false, true]) {
    testWidgets(
      'foreground fixes update distances and stop on ${streamError ? 'stream error' : 'permission loss'}',
      (tester) async {
        var subscriptions = 0;
        var cancellations = 0;
        late MultiStreamController<LocationResult> fixes;
        final stream = Stream<LocationResult>.multi((controller) {
          fixes = controller;
          subscriptions++;
          controller.onCancel = () async {
            cancellations++;
          };
        });
        const initial = LocationResult.granted(31.49, 74.30);
        final result = NearbyHospitalsResult(
          hospitals: [_hospital('Facility').measuredFrom(31.49, 74.30)],
          fetchedAt: DateTime.utc(2026),
          servedFromCache: false,
          devicePosition: initial,
        );
        NearbyHospitalsResult? latest;
        LocationStatus? lost;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              locationServiceProvider.overrideWithValue(
                _FakeLocationService(initial, fixes: stream),
              ),
            ],
            child: MaterialApp(
              home: NearbyCareTracking(
                initial: result,
                builder: (result, loss, _) {
                  latest = result;
                  lost = loss;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );
        await tester.pump();
        expect(subscriptions, 1);
        expect(latest!.devicePosition, same(initial));
        expect(latest!.hospitals.single.distanceKm, greaterThan(1));

        fixes.addSync(const LocationResult.granted(31.50, 74.30));
        await tester.pump();
        expect(latest!.hospitals.single.distanceKm, closeTo(0, 0.01));

        final navigator = tester.state<NavigatorState>(
          find.byType(Navigator),
        );
        unawaited(
          navigator.push(
            MaterialPageRoute<void>(builder: (_) => const Scaffold()),
          ),
        );
        await tester.pumpAndSettle();
        expect(cancellations, 1);
        navigator.pop();
        await tester.pumpAndSettle();
        await tester.pump();
        expect(subscriptions, 2);

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.paused,
        );
        await tester.pump();
        expect(cancellations, 2);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(subscriptions, 3);
        if (streamError) {
          fixes.addErrorSync(StateError('GPS fixture'));
        } else {
          fixes.addSync(const LocationResult.denied());
        }
        await tester.pump();
        expect(
          lost,
          streamError ? LocationStatus.noFix : LocationStatus.denied,
        );
        expect(cancellations, 3);

        // Recreate the route and dispose with an active subscription.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              locationServiceProvider.overrideWithValue(
                _FakeLocationService(initial, fixes: stream),
              ),
            ],
            child: MaterialApp(
              home: NearbyCareTracking(
                initial: result,
                builder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(subscriptions, 4);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(cancellations, 4);
      },
    );
  }

  test(
    'map markers represent the filtered facilities and select the tapped record',
    () {
      final facility = _hospital('Directory fixture');
      Hospital? selected;
      final marker = nearbyCareMarkers([
        facility,
      ], (value) => selected = value).single;
      expect(marker.markerId.value, facility.id);
      expect(marker.position.latitude, facility.latitude);
      expect(marker.position.longitude, facility.longitude);
      marker.onTap!();
      expect(selected, same(facility));
    },
  );

  test(
    'one Places request includes hospitals and clinics and deduplicates by id',
    () async {
      var requests = 0;
      final repo = GooglePlacesRepository(
        apiKey: 'fixture',
        client: MockClient((request) async {
          requests++;
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          expect(
            payload['includedTypes'],
            containsAll(['hospital', 'medical_clinic']),
          );
          final mask = request.headers.entries
              .singleWhere(
                (entry) => entry.key.toLowerCase() == 'x-goog-fieldmask',
              )
              .value;
          expect(mask, contains('places.primaryType'));
          return http.Response('''
          {"places":[
            {"id":"hospital","primaryType":"general_hospital","location":{"latitude":31.5,"longitude":74.3}},
            {"id":"clinic","primaryType":"medical_clinic","location":{"latitude":31.51,"longitude":74.3}},
            {"id":"clinic","types":["medical_clinic"],"location":{"latitude":31.51,"longitude":74.3}}
          ]}''', 200);
        }),
      );
      final results = await Future.wait([
        repo.nearbyHospitals(latitude: 31.5, longitude: 74.3),
        repo.nearbyHospitals(latitude: 31.5, longitude: 74.3),
      ]);
      expect(requests, 1);
      expect(results.first.hospitals.map((place) => place.kind), [
        FacilityKind.hospital,
        FacilityKind.clinic,
      ]);
      expect(
        results.last.hospitals.map((facility) => facility.id),
        results.first.hospitals.map((facility) => facility.id),
      );
    },
  );

  test(
    'a provider 429 consumes the attempt budget and surfaces quota exhaustion',
    () async {
      var requests = 0;
      final repo = GooglePlacesRepository(
        apiKey: 'fixture',
        maxLiveCalls: 1,
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 429);
        }),
      );
      for (var i = 0; i < 2; i++) {
        await expectLater(
          repo.nearbyHospitals(latitude: 31.5, longitude: 74.3),
          throwsA(isA<PlacesQuotaExceededException>()),
        );
      }
      expect(requests, 1);
    },
  );

  test(
    'public lookup uses GPS and never reads the profile city on denial',
    () async {
      final repo = _RecordingPlacesRepository();
      for (final result in [
        const LocationResult.granted(31.5, 74.3),
        const LocationResult.denied(),
        const LocationResult.noFix(),
      ]) {
        final container = ProviderContainer(
          overrides: [
            placesApiKeyProvider.overrideWithValue('fixture'),
            placesRepositoryProvider.overrideWithValue(repo),
            locationServiceProvider.overrideWithValue(
              _FakeLocationService(result),
            ),
            userCityProvider.overrideWith(
              (_) => throw StateError('Public profile read'),
            ),
          ],
        );
        final subscription = container.listen(
          publicNearbyHospitalsProvider,
          (_, _) {},
        );
        try {
          final search = container.read(
            publicNearbyHospitalsProvider.future,
          );
          if (result.status == LocationStatus.granted) {
            await search;
            expect(repo.latitude, 31.5);
          } else if (result.status == LocationStatus.denied) {
            await expectLater(
              search,
              throwsA(
                isA<LocationPermissionDeniedException>().having(
                  (error) => error.hasCityFallback,
                  'hasCityFallback',
                  false,
                ),
              ),
            );
          } else {
            await expectLater(
              search,
              throwsA(
                isA<LocationUnavailableException>().having(
                  (error) => error.fallbackCity,
                  'fallbackCity',
                  isNull,
                ),
              ),
            );
          }
        } finally {
          subscription.close();
          container.dispose();
        }
      }
    },
  );

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

      await repo.nearbyHospitals(
        latitude: 10,
        longitude: 10,
      ); // spends budget
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

    test('parses rating, review count and open-now when present', () async {
      const body =
          '{"places":[{"id":"a","displayName":{"text":"Mayo Hospital"},'
          '"formattedAddress":"Lahore","location":{"latitude":31.58,"longitude":74.31},'
          '"rating":4.3,"userRatingCount":210,'
          '"currentOpeningHours":{"openNow":true}}]}';
      final repo = GooglePlacesRepository(
        apiKey: 'k',
        client: client(body),
        now: () => clock,
      );

      final result = await repo.nearbyHospitals(
        latitude: 31.5,
        longitude: 74.3,
      );
      final h = result.hospitals.single;
      expect(h.rating, 4.3);
      expect(h.userRatingCount, 210);
      expect(h.openNow, isTrue);
    });

    test('leaves rating/open-now null when Places omits them', () async {
      final repo = GooglePlacesRepository(
        apiKey: 'k',
        client: client(_placesBody),
        now: () => clock,
      );

      final result = await repo.nearbyHospitals(
        latitude: 31.5,
        longitude: 74.3,
      );
      expect(result.hospitals.first.rating, isNull);
      expect(result.hospitals.first.openNow, isNull);
    });

    test('a transport failure throws PlacesNetworkException', () async {
      final repo = GooglePlacesRepository(
        apiKey: 'k',
        client: MockClient((_) => throw http.ClientException('offline')),
        now: () => clock,
      );

      expect(
        () => repo.nearbyHospitals(latitude: 1, longitude: 1),
        throwsA(isA<PlacesNetworkException>()),
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
              const _FakeLocationService(
                LocationResult.granted(24.86, 67.00),
              ),
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

    test(
      'denied location surfaces a permission-denied state (with city)',
      () async {
        final container = drive(
          ProviderContainer(
            overrides: [
              placesApiKeyProvider.overrideWithValue('k'),
              locationServiceProvider.overrideWithValue(
                const _FakeLocationService(LocationResult.denied()),
              ),
              userCityProvider.overrideWith((ref) => 'Lahore'),
              placesRepositoryProvider.overrideWithValue(
                _RecordingPlacesRepository(),
              ),
            ],
          ),
        );
        await pumpEventQueue(times: 20);

        final state = container.read(nearbyHospitalsProvider);
        expect(state.hasError, isTrue);
        final error = state.error;
        expect(error, isA<LocationPermissionDeniedException>());
        expect(
          (error as LocationPermissionDeniedException).fallbackCity,
          'Lahore',
        );
        expect(error.servicesDisabled, isFalse);
      },
    );

    test(
      'services-off marks servicesDisabled on the permission state',
      () async {
        final container = drive(
          ProviderContainer(
            overrides: [
              placesApiKeyProvider.overrideWithValue('k'),
              locationServiceProvider.overrideWithValue(
                const _FakeLocationService(LocationResult.unavailable()),
              ),
              userCityProvider.overrideWith((ref) => null),
              placesRepositoryProvider.overrideWithValue(
                _RecordingPlacesRepository(),
              ),
            ],
          ),
        );
        await pumpEventQueue(times: 20);

        final error = container.read(nearbyHospitalsProvider).error;
        expect(error, isA<LocationPermissionDeniedException>());
        expect(
          (error as LocationPermissionDeniedException).servicesDisabled,
          isTrue,
        );
        expect(error.hasCityFallback, isFalse);
      },
    );

    test(
      'city fallback (opted-in) searches the profile-city centroid',
      () async {
        final repo = _RecordingPlacesRepository();
        final container = ProviderContainer(
          overrides: [
            placesApiKeyProvider.overrideWithValue('k'),
            locationServiceProvider.overrideWithValue(
              const _FakeLocationService(LocationResult.denied()),
            ),
            userCityProvider.overrideWith((ref) => 'Lahore'),
            placesRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(container.dispose);
        container.read(cityFallbackRequestedProvider.notifier).useCity();

        await container.read(nearbyHospitalsProvider.future);

        expect(
          repo.latitude,
          31.5497,
        ); // Lahore centroid (cities.yaml parity)
        expect(repo.longitude, 74.3436);
      },
    );

    test('empty key surfaces an API error, never a placeholder', () async {
      final container = drive(
        ProviderContainer(
          overrides: [
            placesApiKeyProvider.overrideWithValue(''),
            locationServiceProvider.overrideWithValue(
              const _FakeLocationService(LocationResult.granted(1, 1)),
            ),
            placesRepositoryProvider.overrideWithValue(
              _RecordingPlacesRepository(),
            ),
          ],
        ),
      );
      await pumpEventQueue(times: 20);

      final error = container.read(nearbyHospitalsProvider).error;
      expect(error, isA<PlacesRequestException>());
    });
  });

  group('HospitalList', () {
    testWidgets('renders cards and wires Call / Directions', (tester) async {
      Hospital? called;
      Hospital? directed;

      await tester.pumpWidget(
        MaterialApp(
          // NoSplash avoids the ink_sparkle shader the test binding can't decode
          // on an ink tap (environmental, unrelated to the feature).
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: Scaffold(
            body: HospitalList(
              hospitals: [
                _hospital('Mayo Hospital', phone: '042111', distance: 1.2),
                _hospital(
                  'Services Hospital',
                  phone: '042222',
                  distance: 2.8,
                ),
              ],
              onCall: (h) => called = h,
              onDirections: (h) => directed = h,
              onTap: (_) {},
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

    testWidgets(
      'tapping the card info area opens details without also firing Call',
      (tester) async {
        Hospital? tapped;
        var called = false;

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(splashFactory: NoSplash.splashFactory),
            home: Scaffold(
              body: HospitalList(
                hospitals: [_hospital('Mayo Hospital', phone: '042111')],
                onCall: (_) => called = true,
                onDirections: (_) {},
                onTap: (h) => tapped = h,
              ),
            ),
          ),
        );

        await tester.tap(find.text('Mayo Hospital'));
        expect(tapped?.name, 'Mayo Hospital');
        expect(called, isFalse);

        // Then tapping Call fires only Call, not another onTap.
        tapped = null;
        await tester.tap(find.text('Call'));
        expect(called, isTrue);
        expect(tapped, isNull);
      },
    );

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
              onTap: (_) {},
            ),
          ),
        ),
      );

      await tester.tap(find.text('Call'));
      expect(called, isFalse);
    });

    testWidgets('shows rating and open-now chips when available', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HospitalList(
              hospitals: const [
                Hospital(
                  id: 'a',
                  name: 'Mayo Hospital',
                  address: 'Lahore',
                  latitude: 31.5,
                  longitude: 74.3,
                  distanceKm: 1.2,
                  phoneNumber: '042111',
                  rating: 4.3,
                  userRatingCount: 210,
                  openNow: true,
                ),
              ],
              onCall: (_) {},
              onDirections: (_) {},
              onTap: (_) {},
            ),
          ),
        ),
      );

      expect(find.textContaining('4.3'), findsOneWidget);
      expect(find.text('Open now'), findsOneWidget);
    });
  });

  group('HospitalDetailSheet', () {
    testWidgets('shows name, distance, address, rating and open-now', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HospitalDetailSheet(
              hospital: const Hospital(
                id: 'a',
                name: 'Mayo Hospital',
                address: 'Anarkali, Lahore',
                latitude: 31.58,
                longitude: 74.31,
                distanceKm: 1.2,
                phoneNumber: '042111',
                rating: 4.3,
                userRatingCount: 210,
                openNow: true,
              ),
              onCall: () {},
              onDirections: () {},
            ),
          ),
        ),
      );

      expect(find.text('Mayo Hospital'), findsOneWidget);
      expect(find.text('Anarkali, Lahore'), findsOneWidget);
      expect(find.textContaining('1.2 km'), findsOneWidget);
      expect(find.textContaining('4.3'), findsOneWidget);
      expect(find.text('Open now'), findsOneWidget);
      expect(find.text('042111'), findsOneWidget);
    });

    testWidgets('omits rating, open-now and phone when Places has none', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HospitalDetailSheet(
              hospital: const Hospital(
                id: 'b',
                name: 'Clinic',
                address: '',
                latitude: 31.5,
                longitude: 74.3,
                distanceKm: 3.4,
              ),
              onCall: () {},
              onDirections: () {},
            ),
          ),
        ),
      );

      expect(find.text('Open now'), findsNothing);
      expect(find.text('Closed'), findsNothing);
      expect(find.byIcon(Icons.star_rounded), findsNothing);
      expect(find.byIcon(Icons.call_outlined), findsNothing);
    });

    testWidgets('Call and Directions fire their callbacks', (tester) async {
      var called = false;
      var directed = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: Scaffold(
            body: HospitalDetailSheet(
              hospital: _hospital('Mayo Hospital', phone: '042111'),
              onCall: () => called = true,
              onDirections: () => directed = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Call'));
      expect(called, isTrue);
      await tester.tap(find.text('Directions'));
      expect(directed, isTrue);
    });
  });

  group('NearbyHospitalsEntry', () {
    testWidgets('prominent explains the High-risk surfacing and taps', (
      tester,
    ) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: Scaffold(
            body: NearbyHospitalsEntry(
              prominent: true,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Nearest Care'), findsOneWidget);
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

      expect(find.text('Hospital Directory'), findsOneWidget);
      expect(
        find.text('Surfaced because risk is High in your area'),
        findsNothing,
      );
    });
  });

  group('NearbyHospitalsScreen states (no placeholder)', () {
    const app = MaterialApp(home: NearbyHospitalsScreen());

    testWidgets(
      'permission denied → enable-location + city fallback, no placeholder',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              currentCityRiskProvider.overrideWith((ref) async => null),
              nearbyHospitalsProvider.overrideWith(
                (ref) => Future.error(
                  const LocationPermissionDeniedException(
                    fallbackCity: 'Lahore',
                  ),
                ),
              ),
            ],
            child: app,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Location permission needed'), findsOneWidget);
        expect(find.text('Enable location'), findsOneWidget);
        expect(find.text('Search near Lahore instead'), findsOneWidget);
        // The old placeholder must be gone entirely.
        expect(find.textContaining('not configured'), findsNothing);
        expect(find.textContaining('Coming Soon'), findsNothing);
      },
    );

    testWidgets('empty results → no-hospitals state', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentCityRiskProvider.overrideWith((ref) async => null),
            nearbyHospitalsProvider.overrideWith(
              (ref) async => NearbyHospitalsResult(
                hospitals: const [],
                fetchedAt: DateTime.utc(2026, 6, 30),
                servedFromCache: false,
              ),
            ),
          ],
          child: app,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No hospitals found nearby'), findsOneWidget);
    });

    testWidgets('network error → offline copy with retry', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentCityRiskProvider.overrideWith((ref) async => null),
            nearbyHospitalsProvider.overrideWith(
              (ref) => Future.error(const PlacesNetworkException('offline')),
            ),
          ],
          child: app,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No Internet Connection'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('success → list + View on map', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentCityRiskProvider.overrideWith((ref) async => null),
            nearbyHospitalsProvider.overrideWith(
              (ref) async => NearbyHospitalsResult(
                hospitals: [_hospital('Mayo Hospital', phone: '042111')],
                fetchedAt: DateTime.utc(2026, 6, 30),
                servedFromCache: false,
              ),
            ),
          ],
          child: app,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mayo Hospital'), findsOneWidget);
      expect(find.text('View on map'), findsOneWidget);
    });

    testWidgets('search filters the real fetched list, never fabricates', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentCityRiskProvider.overrideWith((ref) async => null),
            nearbyHospitalsProvider.overrideWith(
              (ref) async => NearbyHospitalsResult(
                hospitals: [
                  _hospital('Mayo Hospital', phone: '042111'),
                  _hospital('Services Hospital', phone: '042222'),
                ],
                fetchedAt: DateTime.utc(2026, 6, 30),
                servedFromCache: false,
              ),
            ),
          ],
          child: app,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mayo Hospital'), findsOneWidget);
      expect(find.text('Services Hospital'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'services');
      await tester.pumpAndSettle();

      expect(find.text('Mayo Hospital'), findsNothing);
      expect(find.text('Services Hospital'), findsOneWidget);
    });

    testWidgets(
      'distance and rating controls sort and filter locally, then reset',
      (tester) async {
        var loads = 0;
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(800, 1200);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              currentCityRiskProvider.overrideWith((_) async => null),
              nearbyHospitalsProvider.overrideWith((_) async {
                loads++;
                return NearbyHospitalsResult(
                  hospitals: [
                    const Hospital(
                      id: 'far',
                      name: 'Rated Clinic',
                      address: 'Jail Road',
                      latitude: 31.5,
                      longitude: 74.3,
                      distanceKm: 6,
                      rating: 4.8,
                      kind: FacilityKind.clinic,
                    ),
                    _hospital('Closest Hospital'),
                  ],
                  fetchedAt: DateTime.utc(2026),
                  servedFromCache: false,
                );
              }),
            ],
            child: app,
          ),
        );
        await tester.pumpAndSettle();
        double top(String name) => tester.getTopLeft(find.text(name)).dy;
        expect(top('Closest Hospital'), lessThan(top('Rated Clinic')));
        expect(find.text('Clinic'), findsOneWidget);
        await tester.tap(find.text('Highest rated first'));
        await tester.pumpAndSettle();
        expect(top('Rated Clinic'), lessThan(top('Closest Hospital')));
        await tester.tap(find.text('Within 5 km'));
        await tester.pumpAndSettle();
        expect(find.text('Rated Clinic'), findsNothing);
        await tester.tap(find.text('Reset filters'));
        await tester.pumpAndSettle();
        expect(top('Closest Hospital'), lessThan(top('Rated Clinic')));
        await tester.enterText(find.byType(TextField), 'Jail Road');
        await tester.pumpAndSettle();
        expect(find.text('Rated Clinic'), findsOneWidget);
        expect(find.text('Closest Hospital'), findsNothing);
        expect(loads, 1);
      },
    );

    testWidgets(
      'a search with no matches shows the filtered-empty state, distinct '
      'from true-empty, with a clear-filters action',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              currentCityRiskProvider.overrideWith((ref) async => null),
              nearbyHospitalsProvider.overrideWith(
                (ref) async => NearbyHospitalsResult(
                  hospitals: [_hospital('Mayo Hospital', phone: '042111')],
                  fetchedAt: DateTime.utc(2026, 6, 30),
                  servedFromCache: false,
                ),
              ),
            ],
            child: app,
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'no such clinic');
        await tester.pumpAndSettle();

        expect(find.text('No hospitals match your search'), findsOneWidget);
        expect(find.text('No hospitals found nearby'), findsNothing);

        await tester.tap(find.text('Clear filters'));
        await tester.pumpAndSettle();

        expect(find.text('Mayo Hospital'), findsOneWidget);
      },
    );

    testWidgets(
      'Open-now filter only appears when Places actually reported it, and '
      'filters correctly when used',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              currentCityRiskProvider.overrideWith((ref) async => null),
              nearbyHospitalsProvider.overrideWith(
                (ref) async => NearbyHospitalsResult(
                  hospitals: const [
                    Hospital(
                      id: 'a',
                      name: 'Open Clinic',
                      address: '',
                      latitude: 31.5,
                      longitude: 74.3,
                      distanceKm: 1.0,
                      openNow: true,
                    ),
                    Hospital(
                      id: 'b',
                      name: 'Closed Clinic',
                      address: '',
                      latitude: 31.5,
                      longitude: 74.3,
                      distanceKm: 2.0,
                      openNow: false,
                    ),
                  ],
                  fetchedAt: DateTime.utc(2026, 6, 30),
                  servedFromCache: false,
                ),
              ),
            ],
            child: app,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('Open now'),
          findsWidgets,
        ); // filter chip + card chip
        await tester.tap(find.text('Open now').first);
        await tester.pumpAndSettle();

        expect(find.text('Open Clinic'), findsOneWidget);
        expect(find.text('Closed Clinic'), findsNothing);
      },
    );

    testWidgets(
      'the Open-now filter is absent when no result carries opening-hours '
      'data (never a filter over data that does not exist)',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              currentCityRiskProvider.overrideWith((ref) async => null),
              nearbyHospitalsProvider.overrideWith(
                (ref) async => NearbyHospitalsResult(
                  hospitals: [_hospital('Mayo Hospital', phone: '042111')],
                  fetchedAt: DateTime.utc(2026, 6, 30),
                  servedFromCache: false,
                ),
              ),
            ],
            child: app,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Open now'), findsNothing);
      },
    );

    testWidgets('tapping a hospital card opens its detail sheet', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentCityRiskProvider.overrideWith((ref) async => null),
            nearbyHospitalsProvider.overrideWith(
              (ref) async => NearbyHospitalsResult(
                hospitals: [_hospital('Mayo Hospital', phone: '042111')],
                fetchedAt: DateTime.utc(2026, 6, 30),
                servedFromCache: false,
              ),
            ),
          ],
          child: app,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mayo Hospital'));
      await tester.pumpAndSettle();

      expect(find.byType(HospitalDetailSheet), findsOneWidget);
    });
  });
}
