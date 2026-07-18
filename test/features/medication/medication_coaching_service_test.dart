import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/medication/domain/enums/medication_enums.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_journey_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_log_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/medication_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/notification_content.dart';
import 'package:fyp_foreseeme/features/medication/domain/services/medication_coaching_service.dart';
import 'package:fyp_foreseeme/features/medication/domain/services/time_of_day_analysis.dart';

// ── Fixtures ─────────────────────────────────────────────────────────────────

const service = MedicationCoachingService();

MedicationModel _medication({
  String id = 'm1',
  String name = 'Ventolin',
  List<String> reminderTimes = const ['09:00', '21:00'],
}) => MedicationModel(
  id: id,
  uid: 'u1',
  name: name,
  dosage: '2 puffs',
  type: MedicationType.pill,
  frequency: MedicationFrequency.twiceDaily,
  reminderTimes: reminderTimes,
  isActive: true,
  createdAt: DateTime(2026, 1, 1),
);

TodaysMission _mission({
  MissionState state = MissionState.pending,
  String? medicationName,
  String? rawDeadlineTime,
  int pendingDosesToday = 2,
}) => TodaysMission(
  state: state,
  title: 'Take your ${medicationName ?? 'Ventolin'}',
  message: 'Reward: maintain your 5-day streak.',
  medicationName: medicationName,
  rawDeadlineTime: rawDeadlineTime,
  currentStreak: 5,
  pendingDosesToday: pendingDosesToday,
);

AdherenceLogModel _log({
  required DateTime date,
  required String time,
  required AdherenceStatus status,
  String medicationId = 'm1',
  DateTime? confirmedAt,
}) => AdherenceLogModel(
  id: '$medicationId-${date.toIso8601String()}-$time',
  medicationId: medicationId,
  uid: 'u1',
  scheduledTime: time,
  date: date,
  selectedDate: date,
  status: status,
  confirmedAt: confirmedAt,
);

const _weeklyReflection = WeeklyReflection(
  adherencePercent: 91,
  comparedToLastWeek: 8,
  longestStreak: 8,
  missedDoses: 1,
  bestDay: 'Wednesday',
  needsAttention: null,
);

void main() {
  // ── Action notifications (Phase 2.1 / Phase 5) ────────────────────────────
  group('buildActionContent', () {
    test('the last remaining dose today uses the "only one remains" template', () {
      final content = service.buildActionContent(
        medication: _medication(),
        reminderTime: '21:00',
        mission: _mission(
          medicationName: 'Ventolin',
          rawDeadlineTime: '21:00',
          pendingDosesToday: 1,
        ),
        streakForMedication: 5,
        now: DateTime(2026, 6, 30, 8, 0),
      );
      expect(content.category, NotificationCategory.action);
      expect(content.title, contains('Only one medication remains'));
      expect(content.body, contains('9:00 PM'));
    });

    test('a morning slot with an active streak names the streak', () {
      final content = service.buildActionContent(
        medication: _medication(),
        reminderTime: '09:00',
        mission: _mission(pendingDosesToday: 2),
        streakForMedication: 6,
        now: DateTime(2026, 6, 30, 7, 0),
      );
      expect(content.title, 'Good morning!');
      expect(content.body, contains('6-day streak'));
    });

    test('a morning slot with no streak yet is still encouraging, not blank', () {
      final content = service.buildActionContent(
        medication: _medication(),
        reminderTime: '09:00',
        mission: _mission(pendingDosesToday: 2),
        streakForMedication: 0,
        now: DateTime(2026, 6, 30, 7, 0),
      );
      expect(content.body.toLowerCase(), isNot(contains('0-day')));
      expect(content.body, isNotEmpty);
    });

    test('an evening slot protects progress, not just "time to take"', () {
      final content = service.buildActionContent(
        medication: _medication(),
        reminderTime: '21:00',
        mission: _mission(pendingDosesToday: 2),
        streakForMedication: 3,
        now: DateTime(2026, 6, 30, 18, 0),
      );
      expect(content.title, 'Good evening.');
      expect(content.body, contains('Protect your progress'));
    });

    test('never the bare "Time to take medication" wording', () {
      for (final now in [
        DateTime(2026, 6, 30, 7, 0),
        DateTime(2026, 6, 30, 14, 0),
        DateTime(2026, 6, 30, 20, 0),
      ]) {
        final content = service.buildActionContent(
          medication: _medication(),
          reminderTime: '14:00',
          mission: _mission(pendingDosesToday: 2),
          streakForMedication: 1,
          now: now,
        );
        expect(content.title, isNot('Time to take medication.'));
      }
    });
  });

  // ── Recovery notifications (Phase 2.2 / Phase 4) ──────────────────────────
  group('buildRecoveryContent', () {
    test('is always framed supportively, never as correction', () {
      final content = service.buildRecoveryContent(
        medication: _medication(),
        reminderTime: '09:00',
        now: DateTime(2026, 6, 30),
      );
      expect(content.category, NotificationCategory.recovery);
      for (final banned in ['fail', 'bad', 'poor', 'non-compliant']) {
        expect(content.body.toLowerCase(), isNot(contains(banned)));
        expect(content.title.toLowerCase(), isNot(contains(banned)));
      }
    });

    test('is deterministic — the same medication/slot/day always picks the same variant', () {
      final first = service.buildRecoveryContent(
        medication: _medication(),
        reminderTime: '09:00',
        now: DateTime(2026, 6, 30, 9, 30),
      );
      final second = service.buildRecoveryContent(
        medication: _medication(),
        reminderTime: '09:00',
        now: DateTime(2026, 6, 30, 11, 0), // same day, different time
      );
      expect(first.title, second.title);
      expect(first.body, second.body);
    });

    test('rotates across different days rather than always the same line', () {
      final seenTitles = <String>{};
      for (var day = 1; day <= 10; day++) {
        final content = service.buildRecoveryContent(
          medication: _medication(),
          reminderTime: '09:00',
          now: DateTime(2026, 6, day),
        );
        seenTitles.add(content.title);
      }
      expect(seenTitles.length, greaterThan(1));
    });
  });

  // ── Escalation's middle stage (Phase 4) ───────────────────────────────────
  group('buildMotivationalContent', () {
    test('differs from both the primary action and recovery wording', () {
      final action = service.buildActionContent(
        medication: _medication(),
        reminderTime: '09:00',
        mission: _mission(pendingDosesToday: 2),
        streakForMedication: 3,
        now: DateTime(2026, 6, 30, 7, 0),
      );
      final motivational = service.buildMotivationalContent(
        medication: _medication(),
        reminderTime: '09:00',
        now: DateTime(2026, 6, 30),
      );
      final recovery = service.buildRecoveryContent(
        medication: _medication(),
        reminderTime: '09:00',
        now: DateTime(2026, 6, 30),
      );

      expect(motivational.category, NotificationCategory.action);
      expect(motivational.title, isNot(action.title));
      expect(motivational.title, isNot(recovery.title));
    });
  });

  // ── Celebration notifications (Phase 2.3) ─────────────────────────────────
  group('buildCelebrationContent / buildMissionCompleteContent', () {
    test('wraps an already-detected milestone verbatim (no new detection logic)', () {
      const milestone = Milestone(
        type: MilestoneType.levelUp,
        isMajor: true,
        emoji: '🌳',
        title: 'New Level Unlocked!',
        message: "You've reached Healthy Routine.",
      );
      final content = service.buildCelebrationContent(milestone);
      expect(content.category, NotificationCategory.celebration);
      expect(content.title, contains('New Level Unlocked!'));
      expect(content.body, milestone.message);
    });

    test('wraps an already-computed Mission Complete state', () {
      final mission = _mission(state: MissionState.allComplete, pendingDosesToday: 0);
      final content = service.buildMissionCompleteContent(mission);
      expect(content.category, NotificationCategory.celebration);
      expect(content.body, mission.message);
    });
  });

  // ── Reflection notifications (Phase 2.4) ──────────────────────────────────
  group('buildReflectionContent', () {
    test('summarises the week without asking for action', () {
      final content = service.buildReflectionContent(_weeklyReflection);
      expect(content.category, NotificationCategory.reflection);
      expect(content.title, 'This Week');
      expect(content.body, contains('91%'));
      expect(content.body, contains('8 days'));
      expect(content.body, contains('Wednesday'));
      expect(content.body.toLowerCase(), isNot(contains('please')));
      expect(content.body.toLowerCase(), isNot(contains('complete your')));
    });
  });

  // ── Coaching notifications (Phase 2.5 — signature feature) ────────────────
  group('buildCoachingContent', () {
    test('a timing recommendation takes priority and names the medication', () {
      const recommendation = TimingRecommendation(
        medicationId: 'm1',
        medicationName: 'Ventolin',
        currentReminderTime: '21:00',
        recommendedTime: '20:40',
        minutesEarlier: 20,
      );
      final content = service.buildCoachingContent(
        reflection: _weeklyReflection,
        timeBuckets: const TimeOfDayBreakdown(
          morningTotal: 0,
          morningTaken: 0,
          eveningTotal: 0,
          eveningTaken: 0,
        ),
        timingRecommendation: recommendation,
      );
      expect(content, isNotNull);
      expect(content!.category, NotificationCategory.coaching);
      expect(content.body, contains('Ventolin'));
      expect(content.body, contains('8:40 PM'));
    });

    test('evening-needs-attention surfaces the earlier-reminder offer', () {
      const reflection = WeeklyReflection(
        adherencePercent: 70,
        comparedToLastWeek: 0,
        longestStreak: 2,
        missedDoses: 3,
        bestDay: null,
        needsAttention: 'Evening medications',
      );
      final content = service.buildCoachingContent(
        reflection: reflection,
        timeBuckets: const TimeOfDayBreakdown(
          morningTotal: 5,
          morningTaken: 5,
          eveningTotal: 5,
          eveningTaken: 2,
        ),
      );
      expect(content, isNotNull);
      expect(content!.body, contains('20 minutes earlier'));
    });

    test('excellent morning + good-but-not-great evening gets a gentle observation', () {
      final content = service.buildCoachingContent(
        reflection: _weeklyReflection,
        timeBuckets: const TimeOfDayBreakdown(
          morningTotal: 10,
          morningTaken: 10, // 100%
          eveningTotal: 10,
          eveningTaken: 8, // 80%
        ),
      );
      expect(content, isNotNull);
      expect(content!.title, 'Morning adherence is excellent.');
    });

    test('nothing meaningfully coach-worthy → null (never spam)', () {
      final content = service.buildCoachingContent(
        reflection: _weeklyReflection,
        timeBuckets: const TimeOfDayBreakdown(
          morningTotal: 5,
          morningTaken: 5,
          eveningTotal: 5,
          eveningTaken: 5,
        ),
      );
      expect(content, isNull);
    });
  });

  // ── Adaptive timing (Phase 3 — flagship) ───────────────────────────────────
  group('analyzeTimingRecommendation', () {
    test('too few samples → no recommendation', () {
      final logs = [
        for (var i = 0; i < 3; i++)
          _log(
            date: DateTime(2026, 6, 30).subtract(Duration(days: i)),
            time: '21:00',
            status: AdherenceStatus.taken,
            confirmedAt: DateTime(2026, 6, 30 - i, 20, 40),
          ),
      ];
      final result = service.analyzeTimingRecommendation(
        medication: _medication(),
        reminderTime: '21:00',
        logs: logs,
        now: DateTime(2026, 6, 30),
      );
      expect(result, isNull);
    });

    test('a consistent ~20-minute-earlier pattern recommends shifting earlier', () {
      final logs = [
        for (var i = 0; i < 7; i++)
          _log(
            date: DateTime(2026, 6, 30).subtract(Duration(days: i)),
            time: '21:00',
            status: AdherenceStatus.taken,
            confirmedAt: DateTime(2026, 6, 30 - i, 20, 40),
          ),
      ];
      final result = service.analyzeTimingRecommendation(
        medication: _medication(),
        reminderTime: '21:00',
        logs: logs,
        now: DateTime(2026, 6, 30),
      );
      expect(result, isNotNull);
      expect(result!.recommendedTime, '20:40');
      expect(result.minutesEarlier, 20);
      expect(result.medicationName, 'Ventolin');
    });

    test('taking it on time (or later) never recommends an earlier time', () {
      final logs = [
        for (var i = 0; i < 7; i++)
          _log(
            date: DateTime(2026, 6, 30).subtract(Duration(days: i)),
            time: '21:00',
            status: AdherenceStatus.taken,
            confirmedAt: DateTime(2026, 6, 30 - i, 21, 5),
          ),
      ];
      final result = service.analyzeTimingRecommendation(
        medication: _medication(),
        reminderTime: '21:00',
        logs: logs,
        now: DateTime(2026, 6, 30),
      );
      expect(result, isNull);
    });

    test('the recommended shift never exceeds the cap, even for extreme patterns', () {
      final logs = [
        for (var i = 0; i < 7; i++)
          _log(
            date: DateTime(2026, 6, 30).subtract(Duration(days: i)),
            time: '21:00',
            status: AdherenceStatus.taken,
            confirmedAt: DateTime(2026, 6, 30 - i, 18, 0), // 3 hours earlier
          ),
      ];
      final result = service.analyzeTimingRecommendation(
        medication: _medication(),
        reminderTime: '21:00',
        logs: logs,
        now: DateTime(2026, 6, 30),
      );
      expect(result, isNotNull);
      expect(result!.minutesEarlier, MedicationCoachingService.maxShiftMinutes);
    });

    test('logs for a different medication or a different slot are ignored', () {
      final logs = [
        for (var i = 0; i < 7; i++) ...[
          _log(
            date: DateTime(2026, 6, 30).subtract(Duration(days: i)),
            time: '21:00',
            status: AdherenceStatus.taken,
            medicationId: 'other-med',
            confirmedAt: DateTime(2026, 6, 30 - i, 20, 0),
          ),
          _log(
            date: DateTime(2026, 6, 30).subtract(Duration(days: i)),
            time: '09:00', // different slot on the right medication
            status: AdherenceStatus.taken,
            confirmedAt: DateTime(2026, 6, 30 - i, 8, 0),
          ),
        ],
      ];
      final result = service.analyzeTimingRecommendation(
        medication: _medication(),
        reminderTime: '21:00',
        logs: logs,
        now: DateTime(2026, 6, 30),
      );
      expect(result, isNull);
    });

    test('pending or missed doses are not counted as timing samples', () {
      final logs = [
        for (var i = 0; i < 7; i++)
          _log(
            date: DateTime(2026, 6, 30).subtract(Duration(days: i)),
            time: '21:00',
            status: AdherenceStatus.missed,
          ),
      ];
      final result = service.analyzeTimingRecommendation(
        medication: _medication(),
        reminderTime: '21:00',
        logs: logs,
        now: DateTime(2026, 6, 30),
      );
      expect(result, isNull);
    });
  });
}
