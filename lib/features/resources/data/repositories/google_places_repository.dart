import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:fyp_foreseeme/features/resources/domain/exceptions/places_exception.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/hospital.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/nearby_hospitals_result.dart';
import 'package:fyp_foreseeme/features/resources/domain/repositories/places_repository.dart';

/// Google Places (New) implementation with **TTL caching** and a **per-session
/// live-call quota guard** â€” both required because the key is client-side and
/// every call is billable.
///
/// Cache key rounds the origin to ~1 km, so small GPS jitter still hits the
/// cache. Within [ttl] a repeated lookup makes **no** API call. Once the live
/// budget ([maxLiveCalls]) is spent, a stale cache entry is served if present,
/// else [PlacesQuotaExceededException] is thrown. The `http.Client` and clock
/// are injectable for offline tests.
class GooglePlacesRepository implements PlacesRepository {
  GooglePlacesRepository({
    required String apiKey,
    http.Client? client,
    DateTime Function()? now,
    this.ttl = const Duration(minutes: 15),
    this.maxLiveCalls = 50,
    this.searchRadiusMeters = 8000,
  }) : _apiKey = apiKey,
       _client = client ?? http.Client(),
       _now = now ?? DateTime.now;

  static final Uri _endpoint = Uri.parse(
    'https://places.googleapis.com/v1/places:searchNearby',
  );

  final String _apiKey;
  final http.Client _client;
  final DateTime Function() _now;
  final Duration ttl;
  final int maxLiveCalls;
  final double searchRadiusMeters;

  final Map<String, _CacheEntry> _cache = {};
  final Map<String, Future<NearbyHospitalsResult>> _inFlight = {};
  int _liveCalls = 0;

  @override
  Future<NearbyHospitalsResult> nearbyHospitals({
    required double latitude,
    required double longitude,
  }) async {
    if (_apiKey.isEmpty) throw const PlacesNotConfiguredException();

    final key = _cacheKey(latitude, longitude);
    final cached = _cache[key];
    final now = _now();

    // Fresh cache hit â€” no API call (cost guard).
    if (cached != null && now.difference(cached.fetchedAt) < ttl) {
      return NearbyHospitalsResult(
        hospitals: cached.hospitals
            .map((h) => h.measuredFrom(latitude, longitude))
            .toList(),
        fetchedAt: cached.fetchedAt,
        servedFromCache: true,
      );
    }

    final active = _inFlight[key];
    if (active != null) {
      final result = await active;
      return result.measuredFrom(latitude, longitude);
    }

    // Live-call budget spent: serve a stale entry if we have one, else fail.
    if (_liveCalls >= maxLiveCalls) {
      if (cached != null) {
        return NearbyHospitalsResult(
          hospitals: cached.hospitals
              .map((h) => h.measuredFrom(latitude, longitude))
              .toList(),
          fetchedAt: cached.fetchedAt,
          servedFromCache: true,
        );
      }
      throw const PlacesQuotaExceededException();
    }

    _liveCalls++;
    final request = _fetch(latitude, longitude).then((facilities) {
      final fetchedAt = _now();
      _cache[key] = _CacheEntry(facilities, fetchedAt);
      return NearbyHospitalsResult(
        hospitals: facilities,
        fetchedAt: fetchedAt,
        servedFromCache: false,
      );
    });
    _inFlight[key] = request;
    try {
      return await request;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<List<Hospital>> _fetch(double latitude, double longitude) async {
    final http.Response response;
    try {
      final request = http.Request('POST', _endpoint)
        ..followRedirects = false
        ..headers.addAll({
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': _apiKey,
          'X-Goog-FieldMask':
              'places.id,places.types,places.primaryType,places.displayName,places.formattedAddress,'
              'places.location,places.nationalPhoneNumber,places.rating,'
              'places.userRatingCount,places.currentOpeningHours.openNow',
        })
        ..body = jsonEncode({
          'includedTypes': [
            'hospital',
            'general_hospital',
            'medical_clinic',
          ],
          'maxResultCount': 12,
          'rankPreference': 'DISTANCE',
          'locationRestriction': {
            'circle': {
              'center': {'latitude': latitude, 'longitude': longitude},
              'radius': searchRadiusMeters,
            },
          },
        });
      response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 12));
    } on http.ClientException catch (e) {
      throw PlacesNetworkException(e); // offline / DNS / connection reset
    } on Exception catch (e) {
      // SocketException et al. are not typed by `http`; treat as network.
      throw PlacesNetworkException(e);
    }

    if (response.statusCode == 429) {
      throw const PlacesQuotaExceededException();
    }
    if (response.statusCode != 200) {
      throw PlacesRequestException(
        response.statusCode,
        'Places request failed',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final places = (decoded['places'] as List<dynamic>?) ?? const [];

    final hospitals = <Hospital>[];
    final seen = <String>{};
    for (final raw in places) {
      final p = raw as Map<String, dynamic>;
      final loc = p['location'] as Map<String, dynamic>?;
      final id = p['id'] as String?;
      final lat = loc?['latitude'];
      final lon = loc?['longitude'];
      if (id == null ||
          id.isEmpty ||
          lat is! num ||
          lon is! num ||
          !seen.add(id)) {
        continue;
      }
      final hLat = lat.toDouble();
      final hLon = lon.toDouble();
      final hours = p['currentOpeningHours'] as Map<String, dynamic>?;
      hospitals.add(
        Hospital(
          id: id,
          kind: _facilityKind(p),
          name:
              (p['displayName'] as Map<String, dynamic>?)?['text']
                  as String? ??
              'Unknown facility',
          address: (p['formattedAddress'] as String?) ?? '',
          latitude: hLat,
          longitude: hLon,
          phoneNumber: p['nationalPhoneNumber'] as String?,
          rating: (p['rating'] as num?)?.toDouble(),
          userRatingCount: (p['userRatingCount'] as num?)?.toInt(),
          openNow: hours?['openNow'] as bool?,
          distanceKm: distanceBetweenKm(latitude, longitude, hLat, hLon),
        ),
      );
    }

    hospitals.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return hospitals;
  }

  String _cacheKey(double lat, double lon) =>
      '${lat.toStringAsFixed(2)},${lon.toStringAsFixed(2)}';

  FacilityKind _facilityKind(Map<String, dynamic> place) {
    final primary = place['primaryType'];
    if (primary == 'medical_clinic') return FacilityKind.clinic;
    if (primary == 'hospital' || primary == 'general_hospital') {
      return FacilityKind.hospital;
    }
    final types = (place['types'] as List<dynamic>?) ?? const [];
    if (types.contains('hospital') || types.contains('general_hospital')) {
      return FacilityKind.hospital;
    }
    return types.contains('medical_clinic')
        ? FacilityKind.clinic
        : FacilityKind.other;
  }
}

class _CacheEntry {
  final List<Hospital> hospitals;
  final DateTime fetchedAt;

  const _CacheEntry(this.hospitals, this.fetchedAt);
}
