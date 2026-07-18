import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fyp_foreseeme/features/medication/data/repositories/firestore_adherence_log_repository.dart';
import 'package:fyp_foreseeme/features/medication/data/repositories/firestore_medication_repository.dart';
import 'package:fyp_foreseeme/features/medication/domain/enums/medication_enums.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_journey_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_log_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_stats_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/daily_status.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/medication_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/services/adherence_analytics_service.dart';
import 'package:fyp_foreseeme/features/medication/domain/services/adherence_journey_service.dart';
import 'package:fyp_foreseeme/features/medication/domain/services/milestone_detector.dart';
import 'package:fyp_foreseeme/features/medication/presentation/milestone_celebration_provider.dart';

// ── Fixture helpers ──────────────────────────────────────────────────────────

final _today = DateTime(2026, 6, 30); // Tuesday

DateTime _daysAgo(int n) => _today.subtract(Duration(days: n));

AdherenceStatsModel _stat({
  String medicationId = 'm1',
  String name = 'Ventolin',
  double weeklyRate = 0.9,
  double previousWeeklyRate = 0.8,
  int currentStreak = 4,
  int longestStreak = 4,
  List<DailyStatus> last30DaysLog = const [],
  int last7DaysTakenCount = 6,
  int last7DaysSkippedCount = 1,
}) => AdherenceStatsModel(
  medicationId: medicationId,
  medicationName: name,
  dosage: '2 puffs',
  weeklyRate: weeklyRate,
  previousWeeklyRate: previousWeeklyRate,
  currentStreak: currentStreak,
  longestStreak: longestStreak,
  last30DaysLog: last30DaysLog,
  last7DaysTakenCount: last7DaysTakenCount,
  last7DaysSkippedCount: last7DaysSkippedCount,
);

AdherenceStatsModel _overall({
  double weeklyRate = 0.9,
  double previousWeeklyRate = 0.8,
  int last7DaysTakenCount = 6,
  int last7DaysSkippedCount = 1,
}) => AdherenceStatsModel(
  medicationId: 'overall',
  medicationName: 'Overall',
  dosage: '',
  weeklyRate: weeklyRate,
  previousWeeklyRate: previousWeeklyRate,
  currentStreak: 0,
  longestStreak: 0,
  last30DaysLog: const [],
  last7DaysTakenCount: last7DaysTakenCount,
  last7DaysSkippedCount: last7DaysSkippedCount,
);

AdherenceLogModel _log({
  required DateTime date,
  required AdherenceStatus status,
  String time = '08:00',
  String medicationId = 'm1',
}) => AdherenceLogModel(
  id: '$medicationId-${date.toIso8601String()}-$time',
  medicationId: medicationId,
  uid: 'u1',
  scheduledTime: time,
  date: date,
  selectedDate: date,
  status: status,
);

MedicationModel _medication({
  String id = 'm1',
  String uid = 'u1',
  bool isActive = true,
  List<String> reminderTimes = const ['09:00', '21:00'],
}) => MedicationModel(
  id: id,
  uid: uid,
  name: 'Ventolin',
  dosage: '2 puffs',
  type: MedicationType.pill,
  frequency: MedicationFrequency.twiceDaily,
  reminderTimes: reminderTimes,
  isActive: isActive,
  createdAt: DateTime(2026, 1, 1),
);

const _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

void main() {
  // ── AdherenceAnalyticsService.previousWeeklyRate ──────────────────────────
  group('AdherenceAnalyticsService — previousWeeklyRate', () {
    test(
      'computes the prior-week dose-level rate from the same 30-day fetch',
      () async {
        final firestore = FakeFirebaseFirestore();
        final medRepo = FirestoreMedicationRepository(firestore: firestore);
        final logRepo = FirestoreAdherenceLogRepository(firestore: firestore);
        final service = AdherenceAnalyticsService(
          adherenceLogRepository: logRepo,
          medicationRepository: medRepo,
        );

        final saved = await medRepo.addMedication(
          MedicationModel(
            id: '',
            uid: 'u1',
            name: 'Ventolin',
            dosage: '2 puffs',
            type: MedicationType.pill,
            frequency: MedicationFrequency.onceDaily,
            reminderTimes: const ['08:00'],
            isActive: true,
            createdAt: DateTime.now().subtract(const Duration(days: 29)),
          ),
        );

        final today = DateTime.now();
        DateTime dateOnly(DateTime v) => DateTime(v.year, v.month, v.day);

        // This week (days 0-6 ago): every dose taken → 100%.
        for (var i = 0; i < 7; i++) {
          final date = dateOnly(today.subtract(Duration(days: i)));
          await logRepo.logDose(
            AdherenceLogModel(
              id: 'this-$i',
              medicationId: saved.id,
              uid: 'u1',
              scheduledTime: '08:00',
              date: date,
              selectedDate: date,
              status: AdherenceStatus.taken,
            ),
          );
        }
        // Previous week (days 7-13 ago): every dose missed → 0%.
        for (var i = 7; i < 14; i++) {
          final date = dateOnly(today.subtract(Duration(days: i)));
          await logRepo.logDose(
            AdherenceLogModel(
              id: 'prev-$i',
              medicationId: saved.id,
              uid: 'u1',
              scheduledTime: '08:00',
              date: date,
              selectedDate: date,
              status: AdherenceStatus.missed,
            ),
          );
        }

        final stats = await service.computeStats('u1');
        final medStat = stats.firstWhere((s) => s.medicationId == saved.id);

        expect(medStat.weeklyRate, closeTo(1.0, 0.001));
        expect(medStat.previousWeeklyRate, closeTo(0.0, 0.001));

        final overall = stats.firstWhere((s) => s.medicationId == 'overall');
        expect(overall.weeklyRate, closeTo(1.0, 0.001));
        expect(overall.previousWeeklyRate, closeTo(0.0, 0.001));
      },
    );
  });

  // ── AdherenceJourneyService ────────────────────────────────────────────────
  group('AdherenceJourneyService — hero story (Feature 1, never shames)', () {
    const service = AdherenceJourneyService();

    test('no data yet → a welcoming, not a poor-performance, message', () {
      final journey = service.buildJourney(stats: const [], logs: const [], medications: const [], now: _today);
      expect(journey.hero.tone, HeroTone.poor);
      expect(journey.hero.message, contains('start'));
    });

    test('>=90% → excellent tone with the percent in the message', () {
      final stats = [_overall(weeklyRate: 0.96), _stat(weeklyRate: 0.96)];
      final journey = service.buildJourney(stats: stats, logs: [_log(date: _today, status: AdherenceStatus.taken)], medications: const [], now: _today);
      expect(journey.hero.tone, HeroTone.excellent);
      expect(journey.hero.message, contains('96%'));
    });

    test('70-89% → average, supportive tone', () {
      final stats = [_overall(weeklyRate: 0.75), _stat(weeklyRate: 0.75)];
      final journey = service.buildJourney(stats: stats, logs: [_log(date: _today, status: AdherenceStatus.taken)], medications: const [], now: _today);
      expect(journey.hero.tone, HeroTone.average);
    });

    test('<70% → poor tone but still encouraging, never shaming', () {
      final stats = [_overall(weeklyRate: 0.4), _stat(weeklyRate: 0.4)];
      final journey = service.buildJourney(stats: stats, logs: [_log(date: _today, status: AdherenceStatus.taken)], medications: const [], now: _today);
      expect(journey.hero.tone, HeroTone.poor);
      expect(journey.hero.headline, 'Every day is a new opportunity.');
      // Explicitly not shaming language.
      expect(journey.hero.message.toLowerCase(), isNot(contains('fail')));
      expect(journey.hero.message.toLowerCase(), isNot(contains('bad')));
    });
  });

  group('AdherenceJourneyService — levels (Feature 2)', () {
    const service = AdherenceJourneyService();

    test('level thresholds map percent to the right tier', () {
      final cases = {
        0: MedicationLevel.beginner,
        39: MedicationLevel.beginner,
        40: MedicationLevel.buildingHabits,
        59: MedicationLevel.buildingHabits,
        60: MedicationLevel.consistent,
        79: MedicationLevel.consistent,
        80: MedicationLevel.healthyRoutine,
        94: MedicationLevel.healthyRoutine,
        95: MedicationLevel.asthmaChampion,
        100: MedicationLevel.asthmaChampion,
      };

      for (final entry in cases.entries) {
        final rate = entry.key / 100;
        final stats = [_overall(weeklyRate: rate), _stat(weeklyRate: rate)];
        final journey = service.buildJourney(stats: stats, logs: const [], medications: const [], now: _today);
        expect(journey.level, entry.value, reason: '${entry.key}% should be ${entry.value}');
      }
    });

    test('percentToNextLevel counts up to the next band; 0 at the top level', () {
      final stats = [_overall(weeklyRate: 0.85), _stat(weeklyRate: 0.85)];
      final journey = service.buildJourney(stats: stats, logs: const [], medications: const [], now: _today);
      expect(journey.level, MedicationLevel.healthyRoutine);
      expect(journey.percentToNextLevel, 10); // 95 - 85

      final maxed = service.buildJourney(
        stats: [_overall(weeklyRate: 1.0), _stat(weeklyRate: 1.0)],
        logs: const [],
        medications: const [],
        now: _today,
      );
      expect(maxed.level, MedicationLevel.asthmaChampion);
      expect(maxed.percentToNextLevel, 0);
    });
  });

  group('AdherenceJourneyService — achievements (Feature 3)', () {
    const service = AdherenceJourneyService();

    test('first_checkin unlocks only once any log exists', () {
      final noLogs = service.buildJourney(
        stats: [_overall(), _stat()],
        logs: const [],
        medications: const [],
        now: _today,
      );
      expect(_achievement(noLogs, 'first_checkin').unlocked, isFalse);

      final withLog = service.buildJourney(
        stats: [_overall(), _stat()],
        logs: [_log(date: _today, status: AdherenceStatus.taken)],
        medications: const [],
        now: _today,
      );
      expect(_achievement(withLog, 'first_checkin').unlocked, isTrue);
    });

    test('perfect_week unlocks at 100% weekly rate', () {
      final journey = service.buildJourney(
        stats: [_overall(weeklyRate: 1.0), _stat(weeklyRate: 1.0)],
        logs: const [],
        medications: const [],
        now: _today,
      );
      expect(_achievement(journey, 'perfect_week').unlocked, isTrue);

      final notYet = service.buildJourney(
        stats: [_overall(weeklyRate: 0.99), _stat(weeklyRate: 0.99)],
        logs: const [],
        medications: const [],
        now: _today,
      );
      expect(_achievement(notYet, 'perfect_week').unlocked, isFalse);
    });

    test('streak_3 / streak_7 unlock from the longest streak ever, not the current one', () {
      final threeDay = service.buildJourney(
        stats: [_overall(), _stat(currentStreak: 0, longestStreak: 3)],
        logs: const [],
        medications: const [],
        now: _today,
      );
      expect(_achievement(threeDay, 'streak_3').unlocked, isTrue);
      expect(_achievement(threeDay, 'streak_7').unlocked, isFalse);

      final sevenDay = service.buildJourney(
        stats: [_overall(), _stat(currentStreak: 0, longestStreak: 7)],
        logs: const [],
        medications: const [],
        now: _today,
      );
      expect(_achievement(sevenDay, 'streak_3').unlocked, isTrue);
      expect(_achievement(sevenDay, 'streak_7').unlocked, isTrue);
    });

    test('improved_20 unlocks on a >=20 point week-over-week jump', () {
      final journey = service.buildJourney(
        stats: [_overall(weeklyRate: 0.9, previousWeeklyRate: 0.65)],
        logs: const [],
        medications: const [],
        now: _today,
      );
      expect(_achievement(journey, 'improved_20').unlocked, isTrue);

      final notEnough = service.buildJourney(
        stats: [_overall(weeklyRate: 0.9, previousWeeklyRate: 0.75)],
        logs: const [],
        medications: const [],
        now: _today,
      );
      expect(_achievement(notEnough, 'improved_20').unlocked, isFalse);
    });

    test('morning_perfect unlocks only with morning doses and zero missed', () {
      final noMorningData = service.buildJourney(
        stats: [_overall(), _stat()],
        logs: const [],
        medications: const [],
        now: _today,
      );
      expect(_achievement(noMorningData, 'morning_perfect').unlocked, isFalse);

      final allTaken = service.buildJourney(
        stats: [_overall(), _stat()],
        logs: [
          _log(date: _today, status: AdherenceStatus.taken, time: '08:00'),
          _log(date: _daysAgo(1), status: AdherenceStatus.taken, time: '08:00'),
        ],
        medications: const [],
        now: _today,
      );
      expect(_achievement(allTaken, 'morning_perfect').unlocked, isTrue);

      final oneMissed = service.buildJourney(
        stats: [_overall(), _stat()],
        logs: [
          _log(date: _today, status: AdherenceStatus.taken, time: '08:00'),
          _log(date: _daysAgo(1), status: AdherenceStatus.missed, time: '08:00'),
        ],
        medications: const [],
        now: _today,
      );
      expect(_achievement(oneMissed, 'morning_perfect').unlocked, isFalse);
    });
  });

  group('AdherenceJourneyService — weekly reflection (Feature 4)', () {
    const service = AdherenceJourneyService();

    test('comparedToLastWeek is the signed percentage-point delta', () {
      final journey = service.buildJourney(
        stats: [_overall(weeklyRate: 0.91, previousWeeklyRate: 0.83)],
        logs: const [],
        medications: const [],
        now: _today,
      );
      expect(journey.reflection.adherencePercent, 91);
      expect(journey.reflection.comparedToLastWeek, 8);
    });

    test('missedDoses passes through the overall last-7-day skipped count', () {
      final journey = service.buildJourney(
        stats: [_overall(last7DaysSkippedCount: 2)],
        logs: const [],
        medications: const [],
        now: _today,
      );
      expect(journey.reflection.missedDoses, 2);
    });

    test('bestDay names the weekday with the highest taken ratio this week', () {
      // Wednesday (2 days ago from _today) is a perfect day; the rest are misses.
      final wednesday = _daysAgo(2);
      final log = <DailyStatus>[
        for (var i = 0; i < 7; i++)
          DailyStatus(
            date: _daysAgo(i),
            status: i == 2 ? DailyAdherenceStatus.taken : DailyAdherenceStatus.skipped,
          ),
      ];
      final journey = service.buildJourney(
        stats: [_overall(), _stat(last30DaysLog: log)],
        logs: const [],
        medications: const [],
        now: _today,
      );
      expect(journey.reflection.bestDay, _weekdayNames[wednesday.weekday - 1]);
    });

    test('bestDay is null when nothing was ever taken', () {
      final log = <DailyStatus>[
        for (var i = 0; i < 7; i++)
          DailyStatus(date: _daysAgo(i), status: DailyAdherenceStatus.skipped),
      ];
      final journey = service.buildJourney(
        stats: [_overall(), _stat(last30DaysLog: log)],
        logs: const [],
        medications: const [],
        now: _today,
      );
      expect(journey.reflection.bestDay, isNull);
    });

    test('needsAttention names evening medications when evening lags morning', () {
      final logs = <AdherenceLogModel>[
        // Morning: perfect.
        for (var i = 0; i < 5; i++)
          _log(date: _daysAgo(i), status: AdherenceStatus.taken, time: '08:00'),
        // Evening: mostly missed.
        for (var i = 0; i < 5; i++)
          _log(
            date: _daysAgo(i),
            status: i < 4 ? AdherenceStatus.missed : AdherenceStatus.taken,
            time: '20:00',
          ),
      ];
      final journey = service.buildJourney(
        stats: [_overall(), _stat()],
        logs: logs,
        medications: const [],
        now: _today,
      );
      expect(journey.reflection.needsAttention, 'Evening medications');
    });

    test('needsAttention is null with no lagging bucket', () {
      final journey = service.buildJourney(
        stats: [_overall(), _stat()],
        logs: const [],
        medications: const [],
        now: _today,
      );
      expect(journey.reflection.needsAttention, isNull);
    });
  });

  group('AdherenceJourneyService — insight cards (Feature 5, deterministic)', () {
    const service = AdherenceJourneyService();

    test('streak >=5 surfaces the consistency insight', () {
      final journey = service.buildJourney(
        stats: [_overall(), _stat(currentStreak: 6)],
        logs: const [],
        medications: const [],
        now: _today,
      );
      expect(journey.insights.any((i) => i.title == 'Excellent consistency'), isTrue);
      expect(journey.insights.first.message, contains('6 days'));
    });

    test('a strong week-over-week jump surfaces a trending-upward card', () {
      final journey = service.buildJourney(
        stats: [_overall(weeklyRate: 0.9, previousWeeklyRate: 0.7), _stat(currentStreak: 0)],
        logs: const [],
        medications: const [],
        now: _today,
      );
      expect(journey.insights.any((i) => i.message.contains('improved by 20%')), isTrue);
    });

    test('a decline is framed supportively, never as blame', () {
      final journey = service.buildJourney(
        stats: [_overall(weeklyRate: 0.6, previousWeeklyRate: 0.8), _stat(currentStreak: 0)],
        logs: const [],
        medications: const [],
        now: _today,
      );
      final nudge = journey.insights.firstWhere((i) => i.title == 'A gentle nudge');
      expect(nudge.message.toLowerCase(), isNot(contains('fail')));
    });

    test('nothing to report → a single generic encouragement, never empty', () {
      final journey = service.buildJourney(stats: const [], logs: const [], medications: const [], now: _today);
      expect(journey.insights, isNotEmpty);
      expect(journey.insights.length, lessThanOrEqualTo(3));
    });

    test('at most 3 insight cards even when everything triggers at once', () {
      final logs = <AdherenceLogModel>[
        for (var i = 0; i < 6; i++)
          _log(date: _daysAgo(i), status: AdherenceStatus.taken, time: '08:00'),
        for (var i = 0; i < 6; i++)
          _log(date: _daysAgo(i), status: AdherenceStatus.missed, time: '20:00'),
      ];
      final journey = service.buildJourney(
        stats: [_overall(weeklyRate: 0.9, previousWeeklyRate: 0.6), _stat(currentStreak: 6)],
        logs: logs,
        medications: const [],
        now: _today,
      );
      expect(journey.insights.length, 3);
    });
  });

  group('AdherenceJourneyService — medication performance tiers (Feature 6)', () {
    const service = AdherenceJourneyService();

    test('percent → tier mapping', () {
      final journey = service.buildJourney(
        stats: [
          _overall(),
          _stat(medicationId: 'a', name: 'Excellent Med', weeklyRate: 0.95),
          _stat(medicationId: 'b', name: 'Good Med', weeklyRate: 0.75),
          _stat(medicationId: 'c', name: 'Needs Attention Med', weeklyRate: 0.5),
        ],
        logs: const [],
        medications: const [],
        now: _today,
      );
      final byId = {for (final p in journey.medicationPerformance) p.medicationId: p};
      expect(byId['a']!.tier, PerformanceTier.excellent);
      expect(byId['b']!.tier, PerformanceTier.good);
      expect(byId['c']!.tier, PerformanceTier.needsAttention);
    });
  });

  group('AdherenceJourneyService.nextReminderFor (Feature 9)', () {
    test('null for an archived medication', () {
      final result = AdherenceJourneyService.nextReminderFor(
        _medication(isActive: false),
        DateTime(2026, 6, 30, 10, 0),
      );
      expect(result, isNull);
    });

    test('null when there are no reminder times', () {
      final result = AdherenceJourneyService.nextReminderFor(
        _medication(reminderTimes: const []),
        DateTime(2026, 6, 30, 10, 0),
      );
      expect(result, isNull);
    });

    test('picks the nearest upcoming reminder today', () {
      final now = DateTime(2026, 6, 30, 10, 0); // 10 AM
      final result = AdherenceJourneyService.nextReminderFor(
        _medication(reminderTimes: const ['09:00', '21:00']),
        now,
      );
      expect(result!.label, 'Today');
      expect(result.rawTime, '21:00');
    });

    test('falls back to the earliest reminder tomorrow once today is done', () {
      final now = DateTime(2026, 6, 30, 22, 0); // 10 PM, after both reminders
      final result = AdherenceJourneyService.nextReminderFor(
        _medication(reminderTimes: const ['09:00', '21:00']),
        now,
      );
      expect(result!.label, 'Tomorrow');
      expect(result.rawTime, '09:00');
    });
  });

  // ── MilestoneDetector (Feature 7) ─────────────────────────────────────────
  group('MilestoneDetector', () {
    const service = AdherenceJourneyService();

    AdherenceJourneyModel journeyAt(double rate, {int streak = 0}) {
      return service.buildJourney(
        stats: [_overall(weeklyRate: rate), _stat(weeklyRate: rate, longestStreak: streak)],
        logs: const [],
        medications: const [],
        now: _today,
      );
    }

    test('a level-up is detected and takes priority', () {
      const previous = MilestoneRecord.initial(); // level index 0 (beginner)
      final journey = journeyAt(0.65); // consistent → index 2
      final milestone = MilestoneDetector.detect(previous: previous, journey: journey);
      expect(milestone!.type, MilestoneType.levelUp);
      expect(milestone.isMajor, isTrue);
    });

    test('a first perfect week is detected once level is already reached', () {
      final previous = const MilestoneRecord.initial().copyWith(
        highestLevelIndex: MedicationLevel.values.indexOf(MedicationLevel.asthmaChampion),
      );
      final journey = journeyAt(1.0);
      final milestone = MilestoneDetector.detect(previous: previous, journey: journey);
      expect(milestone!.type, MilestoneType.perfectWeek);
      expect(milestone.isMajor, isTrue);
    });

    test('a perfect week already celebrated does not fire again', () {
      final previous = MilestoneRecord(
        highestLevelIndex: MedicationLevel.values.indexOf(MedicationLevel.asthmaChampion),
        longestStreakEver: 0,
        highestAdherencePercentEver: 100,
        perfectWeekCelebrated: true,
      );
      final journey = journeyAt(1.0);
      expect(MilestoneDetector.detect(previous: previous, journey: journey), isNull);
    });

    test('a new streak record is a minor milestone', () {
      final previous = MilestoneRecord(
        highestLevelIndex: MedicationLevel.values.indexOf(MedicationLevel.asthmaChampion),
        longestStreakEver: 3,
        highestAdherencePercentEver: 100,
        perfectWeekCelebrated: true,
      );
      final journey = journeyAt(1.0, streak: 5);
      final milestone = MilestoneDetector.detect(previous: previous, journey: journey);
      expect(milestone!.type, MilestoneType.newStreakRecord);
      expect(milestone.isMajor, isFalse);
    });

    test('no milestone when nothing improved', () {
      final previous = MilestoneRecord(
        highestLevelIndex: MedicationLevel.values.indexOf(MedicationLevel.asthmaChampion),
        longestStreakEver: 10,
        highestAdherencePercentEver: 100,
        perfectWeekCelebrated: true,
      );
      final journey = journeyAt(0.5, streak: 2);
      expect(MilestoneDetector.detect(previous: previous, journey: journey), isNull);
    });

    test('updateRecord rolls every field forward regardless of which milestone fired', () {
      const previous = MilestoneRecord.initial();
      final journey = journeyAt(1.0, streak: 4); // level-up AND perfect week AND streak record all true
      final updated = MilestoneDetector.updateRecord(previous, journey);

      expect(updated.highestLevelIndex, MedicationLevel.values.indexOf(MedicationLevel.asthmaChampion));
      expect(updated.longestStreakEver, 4);
      expect(updated.highestAdherencePercentEver, 100);
      expect(updated.perfectWeekCelebrated, isTrue);
    });
  });

  // ── milestoneCelebrationProvider (SharedPreferences-backed) ───────────────
  group('milestoneCelebrationProvider', () {
    const service = AdherenceJourneyService();

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    test('checkJourney surfaces a milestone once and persists it', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [milestoneStoreProvider.overrideWithValue(MilestoneStore(prefs))],
      );
      addTearDown(container.dispose);

      final journey = service.buildJourney(
        stats: [_overall(weeklyRate: 0.65), _stat(weeklyRate: 0.65)],
        logs: const [],
        medications: const [],
        now: _today,
      );

      await container.read(milestoneCelebrationProvider.notifier).checkJourney(journey);
      expect(container.read(milestoneCelebrationProvider)?.type, MilestoneType.levelUp);

      // A second, identical check (same level) shouldn't re-fire.
      container.read(milestoneCelebrationProvider.notifier).dismiss();
      await container.read(milestoneCelebrationProvider.notifier).checkJourney(journey);
      expect(container.read(milestoneCelebrationProvider), isNull);
    });
  });

  // ── Weekly Journey Timeline (Sprint UX-M2.3) ──────────────────────────────
  group('AdherenceJourneyService — weekly journey timeline', () {
    const service = AdherenceJourneyService();

    DayJourneyCard todayCard(List<AdherenceLogModel> logs, {DateTime? now}) {
      final journey = service.buildJourney(
        stats: const [],
        logs: logs,
        medications: [_medication()],
        now: now ?? _today,
      );
      return journey.weeklyTimeline.last; // last entry is always "today"
    }

    test('always returns exactly 7 days, oldest first ending today', () {
      final journey = service.buildJourney(
        stats: const [],
        logs: const [],
        medications: [_medication()],
        now: _today,
      );
      expect(journey.weeklyTimeline, hasLength(7));
      expect(journey.weeklyTimeline.last.date, _today);
      expect(journey.weeklyTimeline.last.isToday, isTrue);
      expect(journey.weeklyTimeline.first.isToday, isFalse);
      expect(journey.weeklyTimeline.first.date, _daysAgo(6));
    });

    test('perfectDay 🌳 — every scheduled dose taken', () {
      final card = todayCard([
        _log(date: _today, time: '09:00', status: AdherenceStatus.taken),
        _log(date: _today, time: '21:00', status: AdherenceStatus.taken),
      ]);
      expect(card.status, DayJourneyStatus.perfectDay);
      expect(card.morning, DoseCompletionState.taken);
      expect(card.evening, DoseCompletionState.taken);
      expect(card.completedDoses, 2);
      expect(card.totalDoses, 2);
      expect(card.adherencePercent, 100);
      expect(card.supportingMessage, contains('Great work'));
    });

    test('greatProgress 🌿 — one taken, one resolved missed', () {
      final card = todayCard([
        _log(date: _today, time: '09:00', status: AdherenceStatus.taken),
        _log(date: _today, time: '21:00', status: AdherenceStatus.missed),
      ]);
      expect(card.status, DayJourneyStatus.greatProgress);
      expect(card.morning, DoseCompletionState.taken);
      expect(card.evening, DoseCompletionState.missed);
      // Uses the spec's exact supportive phrasing for a missed evening dose.
      expect(
        card.supportingMessage,
        'You missed your evening medication. Tomorrow is another opportunity.',
      );
    });

    test('buildingHabit 🌱 — today, morning taken, evening still pending', () {
      final card = todayCard([
        _log(date: _today, time: '09:00', status: AdherenceStatus.taken),
      ]);
      expect(card.status, DayJourneyStatus.buildingHabit);
      expect(card.morning, DoseCompletionState.taken);
      expect(card.evening, DoseCompletionState.pending);
    });

    test('today ⭐ — nothing resolved yet', () {
      final card = todayCard(const []);
      expect(card.status, DayJourneyStatus.today);
      expect(card.morning, DoseCompletionState.pending);
      expect(card.evening, DoseCompletionState.pending);
      expect(card.completedDoses, 0);
    });

    test('needsAttention 🥀 — today, nothing taken, but something already missed', () {
      final card = todayCard([
        _log(date: _today, time: '09:00', status: AdherenceStatus.missed),
      ]);
      expect(card.status, DayJourneyStatus.needsAttention);
      expect(card.morning, DoseCompletionState.missed);
      expect(card.evening, DoseCompletionState.pending);
      expect(card.supportingMessage, isNot(contains('fail')));
    });

    test('missed ⚠ — a past day that closed with nothing taken', () {
      final journey = service.buildJourney(
        stats: const [],
        logs: const [], // unlogged + past ⇒ auto-missed
        medications: [_medication()],
        now: _today,
      );
      // 3 days ago is in the past relative to _today and has no logs.
      final pastCard = journey.weeklyTimeline.firstWhere(
        (d) => d.date == _daysAgo(3),
      );
      expect(pastCard.status, DayJourneyStatus.missed);
      expect(pastCard.morning, DoseCompletionState.missed);
      expect(pastCard.evening, DoseCompletionState.missed);
      expect(pastCard.completedDoses, 0);
      expect(pastCard.missedDoses, 2);
    });

    test('a day before the medication existed has no doses scheduled', () {
      final recentMed = _medication(); // overridden below via copy pattern
      final medication = MedicationModel(
        id: recentMed.id,
        uid: recentMed.uid,
        name: recentMed.name,
        dosage: recentMed.dosage,
        type: recentMed.type,
        frequency: recentMed.frequency,
        reminderTimes: recentMed.reminderTimes,
        isActive: true,
        createdAt: _daysAgo(2),
      );
      final journey = service.buildJourney(
        stats: const [],
        logs: const [],
        medications: [medication],
        now: _today,
      );
      final oldestCard = journey.weeklyTimeline.first; // 6 days ago
      expect(oldestCard.totalDoses, 0);
      expect(oldestCard.supportingMessage, 'No medications scheduled this day.');
    });
  });

  // ── Today's Mission ────────────────────────────────────────────────────────
  group('AdherenceJourneyService — today\'s mission', () {
    const service = AdherenceJourneyService();

    TodaysMission missionFor(
      List<AdherenceLogModel> logs, {
      DateTime? now,
      List<MedicationModel>? medications,
      List<AdherenceStatsModel>? stats,
    }) {
      final journey = service.buildJourney(
        stats: stats ?? const [],
        logs: logs,
        medications: medications ?? [_medication()],
        now: now ?? DateTime(2026, 6, 30, 10, 0),
      );
      return journey.todaysMission;
    }

    test('noMedications when there are no active medications', () {
      final mission = missionFor(const [], medications: const []);
      expect(mission.state, MissionState.noMedications);
    });

    test('pending picks the earliest still-open dose today', () {
      final mission = missionFor(const []); // nothing logged yet, 10am
      expect(mission.state, MissionState.pending);
      expect(mission.medicationName, 'Ventolin');
      expect(mission.rawDeadlineTime, '09:00'); // earliest pending dose
    });

    test('reward copy reflects the current streak', () {
      final withStreak = missionFor(
        const [],
        stats: [_overall(), _stat(currentStreak: 5)],
      );
      expect(withStreak.message, contains('5-day streak'));

      final noStreak = missionFor(
        const [],
        stats: [_overall(), _stat(currentStreak: 0)],
      );
      expect(noStreak.message, contains("start today's streak"));
      expect(noStreak.message, isNot(contains('maintain')));
    });

    test('allComplete once every dose today is taken', () {
      final mission = missionFor([
        _log(date: _today, time: '09:00', status: AdherenceStatus.taken),
        _log(date: _today, time: '21:00', status: AdherenceStatus.taken),
      ]);
      expect(mission.state, MissionState.allComplete);
      expect(mission.title, 'Mission Complete!');
    });

    test('dayOver when nothing is pending but not everything was taken', () {
      final mission = missionFor([
        _log(date: _today, time: '09:00', status: AdherenceStatus.taken),
        _log(date: _today, time: '21:00', status: AdherenceStatus.missed),
      ]);
      expect(mission.state, MissionState.dayOver);
      expect(mission.message.toLowerCase(), isNot(contains('fail')));
    });
  });
}

Achievement _achievement(AdherenceJourneyModel journey, String id) =>
    journey.achievements.firstWhere((a) => a.id == id);
