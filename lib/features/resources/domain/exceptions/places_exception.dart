/// Raised when no Places/Maps API key is configured (so no live call is made).
class PlacesNotConfiguredException implements Exception {
  const PlacesNotConfiguredException();

  @override
  String toString() => 'PlacesNotConfiguredException: Maps/Places key missing.';
}

/// Raised when the Places API returns a non-success response.
class PlacesRequestException implements Exception {
  final int statusCode;
  final String body;

  const PlacesRequestException(this.statusCode, this.body);

  @override
  String toString() => 'PlacesRequestException($statusCode): $body';
}

/// Raised when the per-session live-call quota guard is exhausted and there is
/// no cached result to fall back to.
class PlacesQuotaExceededException implements Exception {
  const PlacesQuotaExceededException();

  @override
  String toString() => 'PlacesQuotaExceededException: live-call budget spent.';
}

/// Raised when neither device location nor a city fallback is available, so we
/// cannot determine where to search.
class LocationUnavailableException implements Exception {
  const LocationUnavailableException();

  @override
  String toString() =>
      'LocationUnavailableException: no device location or city on file.';
}
