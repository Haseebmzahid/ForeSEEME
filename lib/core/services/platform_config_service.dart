import 'package:flutter/services.dart';

/// Reads build/runtime configuration that lives on the native side.
///
/// Currently exposes the Maps/Places API key that Gradle injects into the
/// Android manifest from `local.properties` — so the Dart Places REST call reuses
/// the **already-configured** key without a separate `--dart-define`. Non-Android
/// platforms (or a missing handler) resolve to an empty string; callers then fall
/// back to a compile-time define.
class PlatformConfigService {
  const PlatformConfigService();

  static const MethodChannel _channel = MethodChannel('fyp_foreseeme/config');

  /// Returns the manifest Maps/Places key, or `''` when unavailable.
  Future<String> mapsApiKey() async {
    try {
      final key = await _channel.invokeMethod<String>('getMapsApiKey');
      return key ?? '';
    } on MissingPluginException {
      return ''; // platform without the native handler (iOS/tests)
    } on PlatformException {
      return '';
    }
  }
}

/// Resolves the effective Maps/Places API key, preferring a compile-time
/// `--dart-define=MAPS_API_KEY=...` and otherwise the native manifest key.
///
/// Call once at startup and inject via `placesApiKeyProvider.overrideWithValue`.
Future<String> resolveMapsApiKey({
  PlatformConfigService config = const PlatformConfigService(),
}) async {
  const fromDefine = String.fromEnvironment('MAPS_API_KEY');
  if (fromDefine.isNotEmpty) return fromDefine;
  return config.mapsApiKey();
}
