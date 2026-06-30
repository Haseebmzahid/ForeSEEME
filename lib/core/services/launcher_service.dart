import 'package:url_launcher/url_launcher.dart';

/// Thin abstraction over external launching (dialer, browser).
///
/// Keeps `url_launcher` out of the presentation layer (GOLDEN_RULES #1): widgets
/// watch a provider of this interface and never import the plugin, and tests can
/// substitute a fake to assert the exact intent (e.g. the `tel:` target).
abstract class LauncherService {
  /// Opens the phone dialer pre-filled with [number] (a `tel:` intent).
  Future<bool> dialPhone(String number);

  /// Opens [url] in an external application (browser).
  Future<bool> openExternalUrl(String url);
}

/// Production [LauncherService] backed by `url_launcher`.
class UrlLauncherService implements LauncherService {
  const UrlLauncherService();

  @override
  Future<bool> dialPhone(String number) {
    return launchUrl(Uri(scheme: 'tel', path: number));
  }

  @override
  Future<bool> openExternalUrl(String url) {
    return launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}
