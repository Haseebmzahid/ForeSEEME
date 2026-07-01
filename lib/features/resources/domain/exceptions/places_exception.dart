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

/// Raised when location permission is denied (or device location is off), so we
/// cannot centre the search on the user. Carries the user's [fallbackCity] when
/// one is on file, so the UI can offer a "search near my city" alternative.
class LocationPermissionDeniedException implements Exception {
  /// The user's profile city, or `null` when none is on file.
  final String? fallbackCity;

  /// True when the device's location *services* are off (vs. app permission).
  final bool servicesDisabled;

  const LocationPermissionDeniedException({
    this.fallbackCity,
    this.servicesDisabled = false,
  });

  bool get hasCityFallback => fallbackCity != null && fallbackCity!.isNotEmpty;

  @override
  String toString() =>
      'LocationPermissionDeniedException(servicesDisabled: $servicesDisabled, '
      'fallbackCity: $fallbackCity)';
}

/// Raised when the request fails at the transport layer (offline / DNS / socket)
/// — distinct from an API-level error so the UI can say "you may be offline".
class PlacesNetworkException implements Exception {
  final Object cause;
  const PlacesNetworkException(this.cause);

  @override
  String toString() => 'PlacesNetworkException: $cause';
}
