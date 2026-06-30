import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/alerts/presentation/services/alert_deep_link_router.dart';

void main() {
  group('AlertDeepLinkRouter.resolve', () {
    test('uses an allow-listed deepLink from the payload', () {
      expect(
        AlertDeepLinkRouter.resolve({
          'type': 'risk_alert',
          'deepLink': '/resources',
        }),
        '/resources',
      );
      expect(
        AlertDeepLinkRouter.resolve({'deepLink': '/nearby-hospitals'}),
        '/nearby-hospitals',
      );
    });

    test('a risk_alert with no/invalid deepLink opens the risk view', () {
      expect(AlertDeepLinkRouter.resolve({'type': 'risk_alert'}), '/risk-map');
      expect(
        AlertDeepLinkRouter.resolve({
          'type': 'risk_alert',
          'deepLink': '/evil',
        }),
        '/risk-map',
      );
    });

    test('falls back to /home for unknown payloads', () {
      expect(AlertDeepLinkRouter.resolve({}), '/home');
      expect(
        AlertDeepLinkRouter.resolve({'deepLink': '/not-a-route'}),
        '/home',
      );
    });

    test('never resolves to a route outside the known set', () {
      final route = AlertDeepLinkRouter.resolve({'deepLink': '/secret-admin'});
      expect(AlertDeepLinkRouter.knownRoutes.contains(route), isTrue);
    });
  });
}
