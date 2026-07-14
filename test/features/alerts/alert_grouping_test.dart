import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/alerts/domain/models/user_alert.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/services/alert_grouping.dart';

UserAlertModel _alert({required String id, DateTime? createdAt}) =>
    UserAlertModel(
      id: id,
      title: 'Title $id',
      body: 'Body $id',
      category: 'respiratory',
      city: 'Lahore',
      riskLevel: 'High',
      disease: 'Smog',
      recommendation: null,
      deepLink: '',
      riskEstimateId: 'r1',
      createdAt: createdAt,
      read: false,
      readAt: null,
    );

void main() {
  group('groupAlertsByDate', () {
    final now = DateTime(2026, 6, 30, 9); // "now" is 9am, June 30 2026.

    test('same-day alert groups under "Today"', () {
      final groups = groupAlertsByDate([
        _alert(id: 'a1', createdAt: DateTime(2026, 6, 30, 7)),
      ], now: now);

      expect(groups, hasLength(1));
      expect(groups.single.header, 'Today');
      expect(groups.single.alerts.map((a) => a.id), ['a1']);
    });

    test('previous calendar day groups under "Yesterday"', () {
      final groups = groupAlertsByDate([
        _alert(id: 'a1', createdAt: DateTime(2026, 6, 29, 23, 59)),
      ], now: now);

      expect(groups.single.header, 'Yesterday');
    });

    test('just-after-midnight "today" is not "yesterday"', () {
      final groups = groupAlertsByDate([
        _alert(id: 'a1', createdAt: DateTime(2026, 6, 30, 0, 1)),
      ], now: now);

      expect(groups.single.header, 'Today');
    });

    test('older, same-year date formats without the year', () {
      final groups = groupAlertsByDate([
        _alert(id: 'a1', createdAt: DateTime(2026, 6, 20)),
      ], now: now);

      expect(groups.single.header, 'Jun 20');
    });

    test('older, different-year date formats with the year', () {
      final groups = groupAlertsByDate([
        _alert(id: 'a1', createdAt: DateTime(2025, 12, 25)),
      ], now: now);

      expect(groups.single.header, 'Dec 25, 2025');
    });

    test('groups are contiguous and preserve newest-first order', () {
      final groups = groupAlertsByDate([
        _alert(id: 'today1', createdAt: DateTime(2026, 6, 30, 8)),
        _alert(id: 'today2', createdAt: DateTime(2026, 6, 30, 6)),
        _alert(id: 'yesterday1', createdAt: DateTime(2026, 6, 29, 20)),
        _alert(id: 'older1', createdAt: DateTime(2026, 6, 20)),
      ], now: now);

      expect(groups.map((g) => g.header), ['Today', 'Yesterday', 'Jun 20']);
      expect(groups[0].alerts.map((a) => a.id), ['today1', 'today2']);
      expect(groups[1].alerts.map((a) => a.id), ['yesterday1']);
      expect(groups[2].alerts.map((a) => a.id), ['older1']);
    });

    test(
      'a non-contiguous repeat of the same day starts a new bucket, not '
      'merged with an earlier one (input is assumed newest-first)',
      () {
        final groups = groupAlertsByDate([
          _alert(id: 'a', createdAt: DateTime(2026, 6, 30, 8)),
          _alert(id: 'b', createdAt: DateTime(2026, 6, 29, 20)),
          _alert(id: 'c', createdAt: DateTime(2026, 6, 30, 7)),
        ], now: now);

        expect(groups.map((g) => g.header), ['Today', 'Yesterday', 'Today']);
      },
    );

    test('a null createdAt collects into a trailing "Earlier" bucket', () {
      final groups = groupAlertsByDate([
        _alert(id: 'today1', createdAt: DateTime(2026, 6, 30, 8)),
        _alert(id: 'malformed', createdAt: null),
      ], now: now);

      expect(groups.map((g) => g.header), ['Today', 'Earlier']);
      expect(groups.last.alerts.map((a) => a.id), ['malformed']);
    });

    test('multiple undated alerts collect into a single "Earlier" bucket', () {
      final groups = groupAlertsByDate([
        _alert(id: 'm1', createdAt: null),
        _alert(id: 'm2', createdAt: null),
      ], now: now);

      expect(groups, hasLength(1));
      expect(groups.single.header, 'Earlier');
      expect(groups.single.alerts.map((a) => a.id), ['m1', 'm2']);
    });

    test('empty input returns no groups', () {
      expect(groupAlertsByDate(const [], now: now), isEmpty);
    });
  });
}
