/// City centroids for the national risk map, in parity with the backend's
/// `backend/ml/config/cities.yaml` (Sprint 2). Plain lat/lon — no map SDK type,
/// so this stays in the SDK-free domain layer; the map screen converts to its
/// own `LatLng`.
class CityCoordinate {
  final double lat;
  final double lon;

  const CityCoordinate(this.lat, this.lon);
}

/// The five supported cities → centroid. Keys match `kSupportedCities`.
const Map<String, CityCoordinate> kCityCoordinates = {
  'Islamabad': CityCoordinate(33.6844, 73.0479),
  'Rawalpindi': CityCoordinate(33.5651, 73.0169),
  'Lahore': CityCoordinate(31.5497, 74.3436),
  'Karachi': CityCoordinate(24.8607, 67.0011),
  'Peshawar': CityCoordinate(34.0151, 71.5249),
};
