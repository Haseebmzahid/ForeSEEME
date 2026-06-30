/// Pure mapping from an alert payload to an in-app route (Sprint 4, Prompt 4).
///
/// No Firebase, no navigation, no side effects — just `data → path`, so it is
/// fully unit-testable. The engine attaches a `deepLink` (from the cited
/// recommendation); this validates it against known routes and falls back
/// safely, so a tap never lands on an undefined screen.
class AlertDeepLinkRouter {
  AlertDeepLinkRouter._();

  /// Safe destination when the payload has no usable deep link.
  static const String fallbackRoute = '/home';

  /// Routes a tapped alert may open (kept in sync with the GoRouter).
  /// `/alerts` (inbox) is added by Prompt 5; listing it here freezes the target.
  static const Set<String> knownRoutes = {
    '/home',
    '/risk-map',
    '/resources',
    '/nearby-hospitals',
    '/alerts',
  };

  /// Resolves the destination route for a tapped alert [data] payload.
  static String resolve(Map<String, dynamic> data) {
    final deepLink = (data['deepLink'] as String?)?.trim();
    if (deepLink != null && knownRoutes.contains(deepLink)) {
      return deepLink;
    }
    // A risk alert with no/invalid deep link opens the risk view.
    if (data['type'] == 'risk_alert') {
      return '/risk-map';
    }
    return fallbackRoute;
  }
}
