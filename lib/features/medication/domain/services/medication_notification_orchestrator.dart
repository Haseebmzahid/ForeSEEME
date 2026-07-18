import 'package:fyp_foreseeme/core/services/local_notification_service.dart';
import 'package:fyp_foreseeme/features/medication/domain/enums/medication_enums.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_journey_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_log_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_stats_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/medication_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/services/dose_state_engine.dart';
import 'package:fyp_foreseeme/features/medication/domain/services/medication_coaching_service.dart';
import 'package:fyp_foreseeme/features/medication/domain/services/notification_scheduler.dart';

/// Decides *what* to schedule and cancel across the whole notification
/// pipeline (Sprint UX-M2.5, Phases 3/4/8) and executes it through the
/// injected [NotificationScheduler] — fully testable with a fake, no plugin
/// dependency. Content comes from [coaching]; this class only owns timing
/// and lifecycle decisions.
///
/// Design note on reliability vs. freshness: the **primary** reminder stays
/// a daily-*repeating* OS alarm (guaranteed to fire even if the app is never
/// reopened, survives reboot) whose content/time is opportunistically
/// upgraded each time [refresh] runs. The **escalation** stages
/// (motivational, recovery) are one-off, *today only* — they depend on
/// today's specific pending/complete state, so scheduling them indefinitely
/// in advance would go stale; they're refreshed the same way, cheaply, from
/// every trigger point (app open, check-in, medication edit).
class MedicationNotificationOrchestrator {
  final NotificationScheduler scheduler;
  final MedicationCoachingService coaching;

  const MedicationNotificationOrchestrator({
    required this.scheduler,
    this.coaching = const MedicationCoachingService(),
  });

  static const Duration motivationalDelay = Duration(minutes: 20);
  static const Duration recoveryDelay = Duration(minutes: 45);

  /// Refreshes every medication-coaching notification for the current
  /// state. Idempotent and safe to call often (app open, after a check-in,
  /// after add/edit/archive) — each call fully re-derives what should be
  /// scheduled vs. cancelled from scratch.
  Future<void> refresh({
    required List<MedicationModel> medications,
    required List<AdherenceStatsModel> stats,
    required List<AdherenceLogModel> logs,
    required AdherenceJourneyModel journey,
    required DateTime now,
  }) async {
    final activeMedications = medications.where((m) => m.isActive).toList();
    final today = DateTime(now.year, now.month, now.day);
    final missionComplete = journey.todaysMission.state == MissionState.allComplete;

    final logsByMedAndTime = <String, Map<String, AdherenceLogModel>>{};
    for (final log in logs) {
      final date = DateTime(log.date.year, log.date.month, log.date.day);
      if (date != today) continue;
      (logsByMedAndTime[log.medicationId] ??= {})[log.scheduledTime] = log;
    }

    for (final medication in activeMedications) {
      final streak = _streakFor(stats, medication.id);

      for (var slot = 0; slot < medication.reminderTimes.length; slot++) {
        final reminderTime = medication.reminderTimes[slot];

        // Phase 3: personalise the primary reminder's time when the data
        // supports it — still a daily-repeating alarm, just re-tuned.
        final recommendation = coaching.analyzeTimingRecommendation(
          medication: medication,
          reminderTime: reminderTime,
          logs: logs,
          now: now,
        );
        final effectiveReminderTime =
            recommendation?.recommendedTime ?? reminderTime;

        final actionContent = coaching.buildActionContent(
          medication: medication,
          reminderTime: reminderTime,
          mission: journey.todaysMission,
          streakForMedication: streak,
          now: now,
        );
        await scheduler.scheduleDaily(
          notificationId: LocalNotificationService.generateMedicationNotificationId(
            medication.id,
            slot,
          ),
          content: actionContent,
          time: _timeToday(effectiveReminderTime, now),
        );

        final motivationalId = LocalNotificationService.generateCoachingNotificationId(
          'motivational_${medication.id}_$slot',
        );
        final recoveryId = LocalNotificationService.generateCoachingNotificationId(
          'recovery_${medication.id}_$slot',
        );

        final log = logsByMedAndTime[medication.id]?[reminderTime];
        final doseState = DoseStateEngine.determineDoseState(
          selectedDate: today,
          reminderTime: reminderTime,
          status: log?.status ?? AdherenceStatus.pending,
          confirmedAt: log?.confirmedAt,
          now: now,
        );
        final stillPendingToday =
            doseState.effectiveStatus == AdherenceStatus.pending;

        if (!stillPendingToday || missionComplete) {
          // Taken, missed, or the whole day's mission is already complete:
          // nothing left to escalate about today (Phase 8 — never spam a
          // completed dose).
          await scheduler.cancel(motivationalId);
          await scheduler.cancel(recoveryId);
          continue;
        }

        final baseTime = _timeToday(reminderTime, now);
        await scheduler.scheduleOnce(
          notificationId: motivationalId,
          content: coaching.buildMotivationalContent(
            medication: medication,
            reminderTime: reminderTime,
            now: now,
          ),
          time: baseTime.add(motivationalDelay),
        );
        await scheduler.scheduleOnce(
          notificationId: recoveryId,
          content: coaching.buildRecoveryContent(
            medication: medication,
            reminderTime: reminderTime,
            now: now,
          ),
          time: baseTime.add(recoveryDelay),
        );
      }
    }
  }

  /// Cancels every escalation-stage notification for [medication] — called
  /// when it's archived (an inactive medication's [refresh] pass already
  /// skips it, but any *already-scheduled* one-offs from before the archive
  /// must still be torn down explicitly).
  Future<void> cancelEscalationFor(MedicationModel medication) async {
    for (var slot = 0; slot < medication.reminderTimes.length; slot++) {
      await scheduler.cancel(
        LocalNotificationService.generateCoachingNotificationId(
          'motivational_${medication.id}_$slot',
        ),
      );
      await scheduler.cancel(
        LocalNotificationService.generateCoachingNotificationId(
          'recovery_${medication.id}_$slot',
        ),
      );
    }
  }

  int _streakFor(List<AdherenceStatsModel> stats, String medicationId) {
    for (final stat in stats) {
      if (stat.medicationId == medicationId) return stat.currentStreak;
    }
    return 0;
  }

  DateTime _timeToday(String hhmm, DateTime now) {
    final parts = hhmm.split(':');
    final hour = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
    final minute = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
    return DateTime(now.year, now.month, now.day, hour, minute);
  }
}
