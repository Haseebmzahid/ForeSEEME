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
  /// `/alerts` (inbox) is added by Prompt 5; `/weekly-report` by Sprint 5
  /// Prompt 8. Listing them here freezes the valid targets.
  static const Set<String> knownRoutes = {
    '/home',
    '/risk-map',
    '/resources',
    '/nearby-hospitals',
    '/alerts',
    '/weekly-report',
  };

  /// The subset of [knownRoutes] that are bottom-nav tabs — branches of the
  /// root `StatefulShellRoute.indexedStack` (see `app_router.dart`), each
  /// pinned to its own `GlobalKey<NavigatorState>` for the lifetime of the
  /// IndexedStack.
  ///
  /// GoRouter's `push()` builds a *new* route for the target location; for a
  /// shell-branch location that collides with the branch's already-reserved
  /// `GlobalKey<NavigatorState>` and Flutter's Navigator throws
  /// `!keyReservation.contains(key)`. Callers must `go()` to a route in this
  /// set (which correctly hands off to the shell's IndexedStack) and reserve
  /// `push()` for the other, ordinarily-stacked routes in [knownRoutes].
  static const Set<String> shellBranchRoutes = {'/home', '/resources'};

  /// Resolves the destination route for a tapped alert [data] payload.
  static String resolve(Map<String, dynamic> data) {
    final deepLink = (data['deepLink'] as String?)?.trim();
    if (deepLink != null && knownRoutes.contains(deepLink)) {
      return deepLink;
    }
    // The weekly digest opens the report even if its deep link is stripped.
    if (data['type'] == 'weekly_report') {
      return '/weekly-report';
    }
    // A risk alert with no/invalid deep link opens the risk view.
    if (data['type'] == 'risk_alert') {
      return '/risk-map';
    }
    return fallbackRoute;
  }
}
