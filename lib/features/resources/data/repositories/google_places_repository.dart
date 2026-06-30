import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import 'package:fyp_foreseeme/features/resources/domain/exceptions/places_exception.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/hospital.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/nearby_hospitals_result.dart';
import 'package:fyp_foreseeme/features/resources/domain/repositories/places_repository.dart';

/// Google Places (New) implementation with **TTL caching** and a **per-session
/// live-call quota guard** — both required because the key is client-side and
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

    // Fresh cache hit — no API call (cost guard).
    if (cached != null && now.difference(cached.fetchedAt) < ttl) {
      return NearbyHospitalsResult(
        hospitals: cached.hospitals,
        fetchedAt: cached.fetchedAt,
        servedFromCache: true,
      );
    }

    // Live-call budget spent: serve a stale entry if we have one, else fail.
    if (_liveCalls >= maxLiveCalls) {
      if (cached != null) {
        return NearbyHospitalsResult(
          hospitals: cached.hospitals,
          fetchedAt: cached.fetchedAt,
          servedFromCache: true,
        );
      }
      throw const PlacesQuotaExceededException();
    }

    final hospitals = await _fetch(latitude, longitude);
    _liveCalls++;
    _cache[key] = _CacheEntry(hospitals, now);
    return NearbyHospitalsResult(
      hospitals: hospitals,
      fetchedAt: now,
      servedFromCache: false,
    );
  }

  Future<List<Hospital>> _fetch(double latitude, double longitude) async {
    final response = await _client.post(
      _endpoint,
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': _apiKey,
        'X-Goog-FieldMask':
            'places.id,places.displayName,places.formattedAddress,'
            'places.location,places.nationalPhoneNumber',
      },
      body: jsonEncode({
        'includedTypes': ['hospital'],
        'maxResultCount': 12,
        'rankPreference': 'DISTANCE',
        'locationRestriction': {
          'circle': {
            'center': {'latitude': latitude, 'longitude': longitude},
            'radius': searchRadiusMeters,
          },
        },
      }),
    );

    if (response.statusCode != 200) {
      throw PlacesRequestException(response.statusCode, response.body);
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final places = (decoded['places'] as List<dynamic>?) ?? const [];

    final hospitals = <Hospital>[];
    for (final raw in places) {
      final p = raw as Map<String, dynamic>;
      final loc = p['location'] as Map<String, dynamic>?;
      if (loc == null) continue;
      final hLat = (loc['latitude'] as num).toDouble();
      final hLon = (loc['longitude'] as num).toDouble();
      hospitals.add(
        Hospital(
          id: (p['id'] as String?) ?? '${p['displayName']?['text']}',
          name:
              (p['displayName'] as Map<String, dynamic>?)?['text'] as String? ??
              'Unknown facility',
          address: (p['formattedAddress'] as String?) ?? '',
          latitude: hLat,
          longitude: hLon,
          phoneNumber: p['nationalPhoneNumber'] as String?,
          distanceKm: _haversineKm(latitude, longitude, hLat, hLon),
        ),
      );
    }

    hospitals.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return hospitals;
  }

  String _cacheKey(double lat, double lon) =>
      '${lat.toStringAsFixed(2)},${lon.toStringAsFixed(2)}';
}

class _CacheEntry {
  final List<Hospital> hospitals;
  final DateTime fetchedAt;

  const _CacheEntry(this.hospitals, this.fetchedAt);
}

/// Great-circle distance in kilometres.
double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const earthRadiusKm = 6371.0;
  double toRad(double d) => d * math.pi / 180.0;
  final dLat = toRad(lat2 - lat1);
  final dLon = toRad(lon2 - lon1);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(toRad(lat1)) *
          math.cos(toRad(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}
