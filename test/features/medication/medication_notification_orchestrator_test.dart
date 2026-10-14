import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/core/services/local_notification_service.dart';
import 'package:fyp_foreseeme/features/medication/domain/enums/medication_enums.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_journey_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_log_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_stats_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/medication_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/notification_content.dart';
import 'package:fyp_foreseeme/features/medication/domain/services/medication_notification_orchestrator.dart';
import 'package:fyp_foreseeme/features/medication/domain/services/notification_scheduler.dart';

// ── Fake scheduler (records calls, no platform channel) ────────────────────

class ScheduledEntry {
  final NotificationContent content;
  final DateTime time;
  const ScheduledEntry(this.content, this.time);
}

class FakeNotificationScheduler implements NotificationScheduler {
  final Map<int, ScheduledEntry> daily = {};
  final Map<int, ScheduledEntry> once = {};
  final List<int> shown = [];
  final Set<int> cancelled = {};

  @override
  Future<void> scheduleDaily({
    required int notificationId,
    required NotificationContent content,
    required DateTime time,
  }) async {
    daily[notificationId] = ScheduledEntry(content, time);
    cancelled.remove(notificationId);
  }

  @override
  Future<void> scheduleOnce({
    required int notificationId,
    required NotificationContent content,
    required DateTime time,
  }) async {
    once[notificationId] = ScheduledEntry(content, time);
    cancelled.remove(notificationId);
  }

  @override
  Future<void> showNow({
    required int notificationId,
    required NotificationContent content,
  }) async {
    shown.add(notificationId);
  }

  @override
  Future<void> cancel(int notificationId) async {
    cancelled.add(notificationId);
    once.remove(notificationId);
  }
}

// ── Fixtures ─────────────────────────────────────────────────────────────────

MedicationModel _medication({
  String id = 'm1',
  bool isActive = true,
  List<String> reminderTimes = const ['09:00', '21:00'],
}) => MedicationModel(
  id: id,
  uid: 'u1',
  name: 'Ventolin',
  dosage: '2 puffs',
  type: MedicationType.pill,
  frequency: MedicationFrequency.twiceDaily,
  reminderTimes: reminderTimes,
  isActive: isActive,
  createdAt: DateTime(2026, 1, 1),
);

AdherenceStatsModel _stat({String medicationId = 'm1', int currentStreak = 4}) =>
    AdherenceStatsModel(
      medicationId: medicationId,
      medicationName: 'Ventolin',
      dosage: '2 puffs',
      weeklyRate: 0.9,
      currentStreak: currentStreak,
      longestStreak: currentStreak,
      last30DaysLog: const [],
      last7DaysTakenCount: 6,
      last7DaysSkippedCount: 1,
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

const _emptyHero = HeroStory(
  tone: HeroTone.average,
  emoji: '🌿',
  headline: 'x',
  message: 'x',
);
const _emptyReflection = WeeklyReflection(
  adherencePercent: 80,
  comparedToLastWeek: 0,
  longestStreak: 4,
  missedDoses: 1,
  bestDay: null,
  needsAttention: null,
);

AdherenceJourneyModel _journey({
  TodaysMission? mission,
}) => AdherenceJourneyModel(
  hero: _emptyHero,
  level: MedicationLevel.consistent,
  levelProgress: 0.5,
  percentToNextLevel: 10,
  achievements: const [],
  reflection: _emptyReflection,
  insights: const [],
  medicationPerformance: const [],
  todaysMission:
      mission ??
      const TodaysMission(
        state: MissionState.pending,
        title: 'Take your Ventolin',
        message: 'Reward: maintain your 4-day streak.',
        medicationName: 'Ventolin',
        rawDeadlineTime: '09:00',
        currentStreak: 4,
        pendingDosesToday: 2,
      ),
  weeklyTimeline: const [],
  longestStreakEver: 4,
);

void main() {
  final now = DateTime(2026, 6, 30, 8, 0);

  int primaryId(String medId, int slot) =>
      LocalNotificationService.generateMedicationNotificationId(medId, slot);
  int motivationalId(String medId, int slot) =>
      LocalNotificationService.generateCoachingNotificationId('motivational_${medId}_$slot');
  int recoveryId(String medId, int slot) =>
      LocalNotificationService.generateCoachingNotificationId('recovery_${medId}_$slot');

  group('MedicationNotificationOrchestrator.refresh', () {
    test('schedules the primary daily reminder for every active medication slot', () async {
      final scheduler = FakeNotificationScheduler();
      final orchestrator = MedicationNotificationOrchestrator(scheduler: scheduler);

      await orchestrator.refresh(
        medications: [_medication()],
        stats: [_stat()],
        logs: const [],
        journey: _journey(),
        now: now,
      );

      expect(scheduler.daily.containsKey(primaryId('m1', 0)), isTrue);
      expect(scheduler.daily.containsKey(primaryId('m1', 1)), isTrue);
      expect(scheduler.daily[primaryId('m1', 0)]!.content.category, NotificationCategory.action);
    });

    test('skips archived (inactive) medications entirely', () async {
      final scheduler = FakeNotificationScheduler();
      final orchestrator = MedicationNotificationOrchestrator(scheduler: scheduler);

      await orchestrator.refresh(
        medications: [_medication(isActive: false)],
        stats: [_stat()],
        logs: const [],
        journey: _journey(),
        now: now,
      );

      expect(scheduler.daily, isEmpty);
      expect(scheduler.once, isEmpty);
    });

    test('a still-pending dose today gets motivational + recovery one-offs', () async {
      final scheduler = FakeNotificationScheduler();
      final orchestrator = MedicationNotificationOrchestrator(scheduler: scheduler);

      await orchestrator.refresh(
        medications: [_medication(reminderTimes: const ['09:00'])],
        stats: [_stat()],
        logs: const [], // nothing logged → still pending
        journey: _journey(),
        now: now,
      );

      final motId = motivationalId('m1', 0);
      final recId = recoveryId('m1', 0);
      expect(scheduler.once.containsKey(motId), isTrue);
      expect(scheduler.once.containsKey(recId), isTrue);
      expect(
        scheduler.once[motId]!.time,
        DateTime(2026, 6, 30, 9, 0).add(MedicationNotificationOrchestrator.motivationalDelay),
      );
      expect(
        scheduler.once[recId]!.time,
        DateTime(2026, 6, 30, 9, 0).add(MedicationNotificationOrchestrator.recoveryDelay),
      );
    });

    test('a dose already taken today has its escalation cancelled, not scheduled', () async {
      final scheduler = FakeNotificationScheduler();
      final orchestrator = MedicationNotificationOrchestrator(scheduler: scheduler);

      await orchestrator.refresh(
        medications: [_medication(reminderTimes: const ['09:00'])],
        stats: [_stat()],
        logs: [
          _log(date: DateTime(2026, 6, 30), time: '09:00', status: AdherenceStatus.taken),
        ],
        journey: _journey(),
        now: now,
      );

      expect(scheduler.once, isEmpty);
      expect(scheduler.cancelled, containsAll([motivationalId('m1', 0), recoveryId('m1', 0)]));
    });

    test('mission already complete cancels every escalation, even for a med with no log', () async {
      final scheduler = FakeNotificationScheduler();
      final orchestrator = MedicationNotificationOrchestrator(scheduler: scheduler);

      await orchestrator.refresh(
        medications: [_medication(reminderTimes: const ['09:00'])],
        stats: [_stat()],
        logs: const [],
        journey: _journey(
          mission: const TodaysMission(
            state: MissionState.allComplete,
            title: 'Mission Complete!',
            message: 'Great job! See you tomorrow.',
            medicationName: null,
            rawDeadlineTime: null,
            currentStreak: 4,
          ),
        ),
        now: now,
      );

      expect(scheduler.once, isEmpty);
      expect(scheduler.cancelled, containsAll([motivationalId('m1', 0), recoveryId('m1', 0)]));
      // The primary reminder itself is untouched — it's tomorrow's alarm too.
      expect(scheduler.daily.containsKey(primaryId('m1', 0)), isTrue);
    });

    test('an earlier-taken pattern does not automatically alter the requested time', () async {
      final scheduler = FakeNotificationScheduler();
      final orchestrator = MedicationNotificationOrchestrator(scheduler: scheduler);
      final logs = [
        for (var i = 1; i <= 7; i++)
          _log(
            date: DateTime(2026, 6, 30).subtract(Duration(days: i)),
            time: '21:00',
            status: AdherenceStatus.taken,
            confirmedAt: DateTime(2026, 6, 30 - i, 20, 40),
          ),
      ];

      await orchestrator.refresh(
        medications: [_medication(reminderTimes: const ['21:00'])],
        stats: [_stat()],
        logs: logs,
        journey: _journey(),
        now: now,
      );

      expect(scheduler.daily[primaryId('m1', 0)]!.time.hour, 21);
      expect(scheduler.daily[primaryId('m1', 0)]!.time.minute, 0);
    });
  });

  group('MedicationNotificationOrchestrator.cancelEscalationFor', () {
    test('cancels every slot\'s motivational and recovery IDs', () async {
      final scheduler = FakeNotificationScheduler();
      final orchestrator = MedicationNotificationOrchestrator(scheduler: scheduler);

      await orchestrator.cancelEscalationFor(
        _medication(reminderTimes: const ['09:00', '21:00']),
      );

      expect(
        scheduler.cancelled,
        containsAll([
          motivationalId('m1', 0),
          recoveryId('m1', 0),
          motivationalId('m1', 1),
          recoveryId('m1', 1),
        ]),
      );
    });
  });
}
