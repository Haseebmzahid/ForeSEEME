import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/alerts/domain/models/alert_filter.dart';
import 'package:fyp_foreseeme/features/alerts/domain/models/user_alert.dart';

UserAlertModel _alert({
  String riskLevel = 'High',
  bool read = false,
}) => UserAlertModel(
  id: 'a1',
  title: 'Title',
  body: 'Body',
  category: 'respiratory',
  city: 'Lahore',
  riskLevel: riskLevel,
  disease: 'Smog',
  recommendation: null,
  deepLink: '',
  riskEstimateId: 'r1',
  createdAt: DateTime(2026, 6, 30),
  read: read,
  readAt: null,
);

void main() {
  group('AlertFilter.matches', () {
    test('all matches everything, read or unread, any risk level', () {
      for (final level in ['Low', 'Medium', 'High']) {
        for (final read in [true, false]) {
          expect(
            AlertFilter.all.matches(_alert(riskLevel: level, read: read)),
            isTrue,
          );
        }
      }
    });

    test('unread matches only unread alerts, regardless of risk level', () {
      expect(AlertFilter.unread.matches(_alert(read: false)), isTrue);
      expect(AlertFilter.unread.matches(_alert(read: true)), isFalse);
    });

    test('low matches only Low risk level', () {
      expect(AlertFilter.low.matches(_alert(riskLevel: 'Low')), isTrue);
      expect(AlertFilter.low.matches(_alert(riskLevel: 'Medium')), isFalse);
      expect(AlertFilter.low.matches(_alert(riskLevel: 'High')), isFalse);
    });

    test('medium matches only Medium risk level', () {
      expect(AlertFilter.medium.matches(_alert(riskLevel: 'Medium')), isTrue);
      expect(AlertFilter.medium.matches(_alert(riskLevel: 'Low')), isFalse);
      expect(AlertFilter.medium.matches(_alert(riskLevel: 'High')), isFalse);
    });

    test('high matches only High risk level', () {
      expect(AlertFilter.high.matches(_alert(riskLevel: 'High')), isTrue);
      expect(AlertFilter.high.matches(_alert(riskLevel: 'Low')), isFalse);
      expect(AlertFilter.high.matches(_alert(riskLevel: 'Medium')), isFalse);
    });

    test('risk-level filters are read-state agnostic', () {
      expect(
        AlertFilter.high.matches(_alert(riskLevel: 'High', read: true)),
        isTrue,
      );
      expect(
        AlertFilter.high.matches(_alert(riskLevel: 'High', read: false)),
        isTrue,
      );
    });
  });

  group('AlertFilter.label', () {
    test('every value has its exact chip label', () {
      expect(AlertFilter.all.label, 'All');
      expect(AlertFilter.unread.label, 'Unread');
      expect(AlertFilter.low.label, 'Low');
      expect(AlertFilter.medium.label, 'Medium');
      expect(AlertFilter.high.label, 'High');
    });
  });
}
