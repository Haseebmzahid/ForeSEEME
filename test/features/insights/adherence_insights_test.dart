import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/insights/domain/models/adherence_insights.dart';
import 'package:fyp_foreseeme/features/insights/domain/services/adherence_insights_use_case.dart';
import 'package:fyp_foreseeme/features/insights/presentation/adherence_insights_card.dart';
import 'package:fyp_foreseeme/features/insights/presentation/insights_providers.dart';
import 'package:fyp_foreseeme/features/medication/domain/enums/medication_enums.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_log_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/repositories/adherence_log_repository.dart';

final _today = DateTime(2026, 6, 30);
DateTime _day(int ago) => _today.subtract(Duration(days: ago));

AdherenceLogModel _log({
  required DateTime date,
  required AdherenceStatus status,
  String time = '08:00',
  String med = 'm1',
}) => AdherenceLogModel(
  id: '$med-${date.toIso8601String()}-$time-${status.name}',
  medicationId: med,
  uid: 'u1',
  scheduledTime: time,
  date: date,
  selectedDate: date,
  status: status,
);

AdherenceInsights _analyze(List<AdherenceLogModel> logs) =>
    AdherenceInsightsUseCase.analyze(logs, today: _today);

/// Minimal fake used to exercise the use case's I/O path (read-only).
class FakeAdherenceLogRepository implements AdherenceLogRepository {
  FakeAdherenceLogRepository(this._logs);
  final List<AdherenceLogModel> _logs;

  @override
  Stream<List<AdherenceLogModel>> getLogsForDateRange(
    String uid,
    DateTime startDate,
    DateTime endDate,
  ) => Stream.value(_logs);

  @override
  Stream<List<AdherenceLogModel>> getLogsForDate(String uid, DateTime date) =>
      Stream.value(_logs);

  @override
  Future<void> logDose(AdherenceLogModel log) async {}

  @override
  Future<void> updateLogStatus(
    String uid,
    String logId,
    AdherenceStatus status,
  ) async {}
}

void main() {
  group('AdherenceInsightsUseCase.analyze — streaks', () {
    test('no logs → empty insights', () {
      final insights = _analyze(const []);
      expect(insights, AdherenceInsights.empty());
      expect(insights.hasData, isFalse);
    });

    test('three consecutive all-taken days → streak 3, perfect', () {
      final insights = _analyze([
        _log(date: _day(0), status: AdherenceStatus.taken),
        _log(date: _day(1), status: AdherenceStatus.taken),
        _log(date: _day(2), status: AdherenceStatus.taken),
      ]);
      expect(insights.currentStreakDays, 3);
      expect(insights.longestStreakDays, 3);
      expect(insights.takenCount, 3);
      expect(insights.missedCount, 0);
      expect(insights.isPerfect, isTrue);
      expect(insights.focusBucket, isNull);
    });

    test('a miss mid-window breaks the streak', () {
      final insights = _analyze([
        _log(date: _day(2), status: AdherenceStatus.taken),
        _log(date: _day(1), status: AdherenceStatus.missed),
        _log(date: _day(0), status: AdherenceStatus.taken),
      ]);
      expect(insights.currentStreakDays, 1); // only the latest day
      expect(insights.longestStreakDays, 1);
      expect(insights.missedCount, 1);
    });

    test('current streak is 0 when the latest logged day was missed', () {
      final insights = _analyze([
        _log(date: _day(1), status: AdherenceStatus.taken),
        _log(date: _day(0), status: AdherenceStatus.missed),
      ]);
      expect(insights.currentStreakDays, 0);
      expect(insights.longestStreakDays, 1);
    });

    test('a calendar gap breaks consecutiveness', () {
      final insights = _analyze([
        _log(date: _day(2), status: AdherenceStatus.taken),
        // _day(1) has no logs at all
        _log(date: _day(0), status: AdherenceStatus.taken),
      ]);
      expect(insights.currentStreakDays, 1);
      expect(insights.longestStreakDays, 1);
    });

    test('a day with both taken and missed is not on-track', () {
      final insights = _analyze([
        _log(date: _day(0), status: AdherenceStatus.taken, time: '08:00'),
        _log(date: _day(0), status: AdherenceStatus.missed, time: '20:00'),
      ]);
      expect(insights.currentStreakDays, 0);
      expect(insights.longestStreakDays, 0);
    });
  });

  group('AdherenceInsightsUseCase.analyze — time-of-day', () {
    test('picks the strongest and a distinct focus bucket', () {
      final insights = _analyze([
        _log(date: _day(0), status: AdherenceStatus.taken, time: '07:00'),
        _log(date: _day(1), status: AdherenceStatus.taken, time: '08:00'),
        _log(date: _day(2), status: AdherenceStatus.taken, time: '09:00'),
        _log(date: _day(0), status: AdherenceStatus.taken, time: '20:00'),
        _log(date: _day(1), status: AdherenceStatus.missed, time: '21:00'),
        _log(date: _day(2), status: AdherenceStatus.missed, time: '22:00'),
      ]);
      expect(insights.strongestBucket, TimeOfDayBucket.morning);
      expect(insights.focusBucket, TimeOfDayBucket.evening);
    });

    test('focus is suppressed when it would equal the strongest', () {
      // A single bucket with one taken + one missed: strongest == would-be focus.
      final insights = _analyze([
        _log(date: _day(0), status: AdherenceStatus.taken, time: '08:00'),
        _log(date: _day(1), status: AdherenceStatus.missed, time: '09:00'),
      ]);
      expect(insights.strongestBucket, TimeOfDayBucket.morning);
      expect(insights.focusBucket, isNull);
    });

    test('strongest tie-breaks on the larger sample', () {
      final insights = _analyze([
        // morning 2/2 taken (rate 1.0)
        _log(date: _day(0), status: AdherenceStatus.taken, time: '08:00'),
        _log(date: _day(1), status: AdherenceStatus.taken, time: '08:30'),
        // afternoon 3/3 taken (rate 1.0, more doses)
        _log(date: _day(0), status: AdherenceStatus.taken, time: '13:00'),
        _log(date: _day(1), status: AdherenceStatus.taken, time: '14:00'),
        _log(date: _day(2), status: AdherenceStatus.taken, time: '15:00'),
      ]);
      expect(insights.strongestBucket, TimeOfDayBucket.afternoon);
      expect(insights.focusBucket, isNull); // nothing missed
    });

    test('unparseable scheduled time is ignored for buckets', () {
      final insights = _analyze([
        _log(date: _day(0), status: AdherenceStatus.taken, time: 'not-a-time'),
      ]);
      expect(insights.takenCount, 1); // still counted overall
      expect(insights.strongestBucket, isNull); // but not bucketed
    });
  });

  group('supportive copy — tone checklist (no shaming, no scoring)', () {
    const banned = [
      'fail',
      'failure',
      'bad',
      'poor',
      'worst',
      'shame',
      'lazy',
      'guilt',
      'disappoint',
      'wrong',
      'must',
      'should',
      '%',
    ];

    final samples = <AdherenceInsights>[
      AdherenceInsights.empty(),
      _analyze([
        _log(date: _day(0), status: AdherenceStatus.taken),
        _log(date: _day(1), status: AdherenceStatus.taken),
      ]),
      _analyze([
        _log(date: _day(0), status: AdherenceStatus.taken, time: '08:00'),
        _log(date: _day(1), status: AdherenceStatus.missed, time: '20:00'),
        _log(date: _day(2), status: AdherenceStatus.taken, time: '08:00'),
      ]),
      _analyze([_log(date: _day(0), status: AdherenceStatus.missed)]),
    ];

    test('headline and message never contain shaming or scoring language', () {
      for (final s in samples) {
        final copy = '${s.headline} ${s.supportiveMessage}'.toLowerCase();
        for (final word in banned) {
          expect(copy.contains(word), isFalse, reason: '"$word" in: $copy');
        }
      }
    });

    test('perfect adherence is celebrated', () {
      final perfect = _analyze([
        _log(date: _day(0), status: AdherenceStatus.taken),
        _log(date: _day(1), status: AdherenceStatus.taken),
      ]);
      expect(perfect.isPerfect, isTrue);
      expect(perfect.headline.toLowerCase(), contains('consistency'));
    });

    test('a nudge is gentle (offers help, never commands)', () {
      final insights = _analyze([
        _log(date: _day(0), status: AdherenceStatus.taken, time: '08:00'),
        _log(date: _day(1), status: AdherenceStatus.missed, time: '20:00'),
        _log(date: _day(2), status: AdherenceStatus.taken, time: '08:00'),
      ]);
      expect(insights.focusBucket, TimeOfDayBucket.evening);
      expect(insights.supportiveMessage, contains('could help'));
    });

    test('empty state invites logging without pressure', () {
      expect(
        AdherenceInsights.empty().supportiveMessage.toLowerCase(),
        contains('gentle'),
      );
    });
  });

  group('AdherenceInsightsUseCase.compute (I/O, read-only)', () {
    test('empty uid short-circuits to empty', () async {
      final useCase = AdherenceInsightsUseCase(
        adherenceLogRepository: FakeAdherenceLogRepository(const []),
      );
      expect(await useCase.compute(''), AdherenceInsights.empty());
    });

    test('delegates to analyze over the fetched window', () async {
      final useCase = AdherenceInsightsUseCase(
        adherenceLogRepository: FakeAdherenceLogRepository([
          _log(date: _day(0), status: AdherenceStatus.taken),
          _log(date: _day(1), status: AdherenceStatus.taken),
        ]),
      );
      final insights = await useCase.compute('u1', now: _today);
      expect(insights.currentStreakDays, 2);
      expect(insights.takenCount, 2);
    });
  });

  group('AdherenceInsightsCard', () {
    Widget wrap(AdherenceInsights insights) => ProviderScope(
      overrides: [adherenceInsightsProvider.overrideWith((ref) => insights)],
      child: const MaterialApp(home: Scaffold(body: AdherenceInsightsCard())),
    );

    testWidgets('renders headline, message and stat chips with data', (
      tester,
    ) async {
      const insights = AdherenceInsights(
        currentStreakDays: 5,
        longestStreakDays: 7,
        takenCount: 20,
        missedCount: 2,
        strongestBucket: TimeOfDayBucket.morning,
        focusBucket: TimeOfDayBucket.evening,
      );

      await tester.pumpWidget(wrap(insights));
      await tester.pumpAndSettle();

      expect(find.text("You're on a 5-day streak"), findsOneWidget);
      expect(find.text('Current streak'), findsOneWidget);
      expect(find.text('5 days'), findsOneWidget);
      expect(find.text('Best streak'), findsOneWidget);
      expect(find.text('Most consistent'), findsOneWidget);
      expect(find.text('Morning'), findsOneWidget);
      expect(
        find.textContaining('extra support in the evening'),
        findsOneWidget,
      );
    });

    testWidgets('empty state shows a kind invitation and no chips', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(AdherenceInsights.empty()));
      await tester.pumpAndSettle();

      expect(find.text('Your adherence insights'), findsOneWidget);
      expect(find.textContaining('Log a few doses'), findsOneWidget);
      expect(find.text('Current streak'), findsNothing);
    });
  });
}
