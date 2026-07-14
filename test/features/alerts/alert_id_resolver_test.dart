import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/alerts/presentation/services/alert_id_resolver.dart';

void main() {
  group('AlertIdResolver.resolve', () {
    test('reconstructs the backend dispatch_key format', () {
      final id = AlertIdResolver.resolve(
        {
          'type': 'risk_alert',
          'riskEstimateId': 'Lahore_2026-06-30',
          'category': 'respiratory',
          'city': 'Lahore',
        },
        uid: 'u1',
      );

      expect(id, 'u1__Lahore_2026-06-30__respiratory');
    });

    test('missing riskEstimateId returns null', () {
      final id = AlertIdResolver.resolve(
        {'type': 'risk_alert', 'category': 'respiratory'},
        uid: 'u1',
      );

      expect(id, isNull);
    });

    test('missing category returns null', () {
      final id = AlertIdResolver.resolve(
        {'type': 'risk_alert', 'riskEstimateId': 'Lahore_2026-06-30'},
        uid: 'u1',
      );

      expect(id, isNull);
    });

    test('empty-string fields return null, not an empty-component id', () {
      final id = AlertIdResolver.resolve(
        {'riskEstimateId': '', 'category': 'respiratory'},
        uid: 'u1',
      );

      expect(id, isNull);
    });

    test('unrelated payload (e.g. weekly_report) returns null', () {
      final id = AlertIdResolver.resolve(
        {'type': 'weekly_report'},
        uid: 'u1',
      );

      expect(id, isNull);
    });
  });
}
