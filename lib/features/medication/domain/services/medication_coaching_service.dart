import 'package:fyp_foreseeme/features/medication/domain/enums/medication_enums.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_journey_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_log_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/medication_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/notification_content.dart';
import 'package:fyp_foreseeme/features/medication/domain/services/time_of_day_analysis.dart';

/// The behavioral-coaching "brain" (Sprint UX-M2.5): turns already-computed
/// adherence data into the five notification categories' content, plus the
/// one genuinely new piece of analysis — adaptive reminder timing.
///
/// Deterministic and rule-based throughout (no AI/ML, per the spec). Reuses
/// [AdherenceJourneyModel] output (hero/level/reflection/mission/streaks) as
/// input rather than recomputing it — this service only adds notification
/// *wording* and the timing-recommendation algorithm. Always supportive:
/// no template here uses shaming language ("failed", "poor", "bad",
/// "non-compliant").
class MedicationCoachingService {
  const MedicationCoachingService();

  // ── Adaptive timing (Phase 3 — the flagship feature) ──────────────────────

  static const int minSampleSize = 5;
  static const int minShiftMinutes = 15;
  static const int maxShiftMinutes = 60;
  static const int trailingWindowDays = 21;

  /// A deterministic, explainable suggestion to shift [medication]'s
  /// [reminderTime] earlier, based on the average clock-time the user has
  /// actually confirmed taking that exact dose over the trailing 21 days.
  /// Returns null when there isn't enough signal ([minSampleSize]+ taken
  /// doses with a recorded confirmation time) or the pattern doesn't
  /// meaningfully differ from the current reminder (< [minShiftMinutes]).
  /// Never applied automatically — see `TimingRecommendation`.
  TimingRecommendation? analyzeTimingRecommendation({
    required MedicationModel medication,
    required String reminderTime,
    required List<AdherenceLogModel> logs,
    required DateTime now,
  }) {
    final scheduledMinutes = _minutesOf(reminderTime);
    if (scheduledMinutes == null) return null;

    final today = _dateOnly(now);
    final windowStart = today.subtract(const Duration(days: trailingWindowDays));

    final samples = <int>[];
    for (final log in logs) {
      if (log.medicationId != medication.id) continue;
      if (log.scheduledTime != reminderTime) continue;
      if (log.status != AdherenceStatus.taken) continue;
      final confirmedAt = log.confirmedAt;
      if (confirmedAt == null) continue;
      final date = _dateOnly(log.date);
      if (date.isBefore(windowStart) || date.isAfter(today)) continue;
      samples.add(confirmedAt.hour * 60 + confirmedAt.minute);
    }

    if (samples.length < minSampleSize) return null;

    final averageMinutes =
        samples.reduce((a, b) => a + b) / samples.length;
    final earlierBy = scheduledMinutes - averageMinutes;
    if (earlierBy < minShiftMinutes) return null;

    final cappedShift = earlierBy.clamp(minShiftMinutes, maxShiftMinutes).round();
    final recommendedMinutes =
        (scheduledMinutes - cappedShift).clamp(0, 23 * 60 + 59);
    final roundedMinutes = ((recommendedMinutes / 5).round() * 5).clamp(0, 23 * 60 + 59);

    return TimingRecommendation(
      medicationId: medication.id,
      medicationName: medication.name,
      currentReminderTime: reminderTime,
      recommendedTime: _formatHHmm(roundedMinutes),
      minutesEarlier: cappedShift,
    );
  }

  // ── Action notifications (Phase 2.1) ──────────────────────────────────────

  /// The primary reminder for [medication] at [reminderTime]. Sourced from
  /// [mission] when this dose is the one currently identified as "today's
  /// mission" (Phase 5 — the mission becomes the notification, not a
  /// separately-worded duplicate); otherwise a time-of-day/streak template.
  NotificationContent buildActionContent({
    required MedicationModel medication,
    required String reminderTime,
    required TodaysMission mission,
    required int streakForMedication,
    required DateTime now,
  }) {
    final isTheMission = mission.state == MissionState.pending &&
        mission.medicationName == medication.name &&
        mission.rawDeadlineTime == reminderTime;

    if (isTheMission && mission.pendingDosesToday == 1) {
      return NotificationContent(
        category: NotificationCategory.action,
        title: 'Only one medication remains today.',
        body: "Complete today's mission before ${_formatTime(reminderTime)}.",
        payload: NotificationCategory.action.name,
      );
    }

    final hour = timeOfDayHourOf(reminderTime) ?? now.hour;
    if (hour < 12) {
      return NotificationContent(
        category: NotificationCategory.action,
        title: 'Good morning!',
        body: streakForMedication > 0
            ? 'Taking today\'s medication keeps your $streakForMedication-day streak alive.'
            : "Taking today's medication starts building a healthy streak.",
        payload: NotificationCategory.action.name,
      );
    }
    if (hour >= 17) {
      return const NotificationContent(
        category: NotificationCategory.action,
        title: 'Good evening.',
        body: "Protect your progress by taking today's medication.",
        payload: 'action',
      );
    }
    return NotificationContent(
      category: NotificationCategory.action,
      title: 'Time for ${medication.name}.',
      body: 'Keep your healthy habits going.',
      payload: NotificationCategory.action.name,
    );
  }

  // ── Recovery notifications (Phase 2.2) ────────────────────────────────────

  static const List<(String title, String body)> _recoveryVariants = [
    (
      'Still pending',
      "We noticed today's medication is still pending. If you've already "
          "taken it, mark it complete. Otherwise, there's still time.",
    ),
    (
      'Keep going',
      "Missing one dose doesn't erase your progress. Tomorrow is another "
          'opportunity.',
    ),
    ("Let's get back on track", "Let's get back on track today."),
  ];

  /// A gentle follow-up for a dose still pending after its reminder window.
  /// Deterministically rotates through supportive phrasings (by medication +
  /// slot + date) so daily nudges don't read as an identical, robotic
  /// repeat — never a random/unstable choice.
  NotificationContent buildRecoveryContent({
    required MedicationModel medication,
    required String reminderTime,
    required DateTime now,
  }) {
    final key = '${medication.id}_${reminderTime}_${_dateOnly(now)}';
    final variant = _recoveryVariants[key.hashCode.abs() % _recoveryVariants.length];
    return NotificationContent(
      category: NotificationCategory.recovery,
      title: variant.$1,
      body: variant.$2,
      payload: NotificationCategory.recovery.name,
    );
  }

  // ── Escalation's middle stage (Phase 4) ───────────────────────────────────

  static const List<(String title, String body)> _motivationalVariants = [
    ('Still time', "A quick dose now keeps today's progress on track."),
    ('Quick nudge', 'Your streak is counting on this next dose.'),
    ("You've got this", 'A small step now, a healthier you today.'),
  ];

  /// The escalation timeline's middle stage (~20 minutes after the primary
  /// reminder, before the Recovery stage) — a different voice again, so
  /// three reminders in a row never read as the same message repeated.
  NotificationContent buildMotivationalContent({
    required MedicationModel medication,
    required String reminderTime,
    required DateTime now,
  }) {
    final key = 'motivational_${medication.id}_${reminderTime}_${_dateOnly(now)}';
    final variant =
        _motivationalVariants[key.hashCode.abs() % _motivationalVariants.length];
    return NotificationContent(
      category: NotificationCategory.action,
      title: variant.$1,
      body: variant.$2,
      payload: NotificationCategory.action.name,
    );
  }

  // ── Celebration notifications (Phase 2.3) ─────────────────────────────────
  //
  // Major milestones only — both callers below wrap content that's already
  // been through a "is this worth celebrating" gate (`MilestoneDetector` for
  // achievements/levels, `MissionState.allComplete` for a finished day), so
  // this layer never invents its own celebration triggers.

  /// Wraps an already-detected [Milestone] (from `MilestoneDetector`) as a
  /// notification — zero new detection logic.
  NotificationContent buildCelebrationContent(Milestone milestone) {
    return NotificationContent(
      category: NotificationCategory.celebration,
      title: '${milestone.emoji} ${milestone.title}',
      body: milestone.message,
      payload: NotificationCategory.celebration.name,
    );
  }

  /// Wraps an already-computed "Mission Complete" [TodaysMission].
  NotificationContent buildMissionCompleteContent(TodaysMission mission) {
    return NotificationContent(
      category: NotificationCategory.celebration,
      title: '🎉 ${mission.title}',
      body: mission.message,
      payload: NotificationCategory.celebration.name,
    );
  }

  // ── Reflection notifications (Phase 2.4) ──────────────────────────────────

  /// The Sunday-evening weekly summary — a direct format of the already
  /// computed [WeeklyReflection] (Sprint UX-M2.2), never a request for
  /// action.
  NotificationContent buildReflectionContent(WeeklyReflection reflection) {
    final parts = <String>[
      '${reflection.adherencePercent}% adherence',
      'longest streak ${reflection.longestStreak} days',
      if (reflection.bestDay != null) 'best day ${reflection.bestDay}',
    ];
    return NotificationContent(
      category: NotificationCategory.reflection,
      title: 'This Week',
      body: '${parts.join(', ')}. Keep building healthy habits.',
      payload: NotificationCategory.reflection.name,
    );
  }

  // ── Coaching notifications (Phase 2.5 — the signature feature) ───────────

  /// The single most relevant coaching observation right now, or null when
  /// nothing meaningfully actionable stands out (never sends a notification
  /// just to say something — respects Phase 8's "never spam").
  NotificationContent? buildCoachingContent({
    required WeeklyReflection reflection,
    required TimeOfDayBreakdown timeBuckets,
    TimingRecommendation? timingRecommendation,
  }) {
    if (timingRecommendation != null) {
      final recommendedTime = _formatTime(timingRecommendation.recommendedTime);
      return NotificationContent(
        category: NotificationCategory.coaching,
        title: 'A gentle suggestion',
        body:
            'You usually take your ${timingRecommendation.medicationName} '
            'around $recommendedTime. Would you like ForeSeeMe to adjust '
            'future reminders?',
        payload: NotificationCategory.coaching.name,
      );
    }

    if (reflection.needsAttention == 'Evening medications') {
      return const NotificationContent(
        category: NotificationCategory.coaching,
        title: "We've noticed a pattern",
        body:
            'Evening medications are more difficult to complete. Would you '
            'like reminders 20 minutes earlier?',
        payload: 'coaching',
      );
    }

    final morning = timeBuckets.morningRate;
    final evening = timeBuckets.eveningRate;
    if (morning != null &&
        evening != null &&
        morning >= 0.9 &&
        evening < 0.9 &&
        evening >= 0.7) {
      return const NotificationContent(
        category: NotificationCategory.coaching,
        title: 'Morning adherence is excellent.',
        body: "Let's improve evening consistency.",
        payload: 'coaching',
      );
    }

    return null;
  }

  // ── Shared formatting/date helpers ────────────────────────────────────────

  int? _minutesOf(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return hour * 60 + minute;
  }

  String _formatHHmm(int minutesSinceMidnight) {
    final hour = (minutesSinceMidnight ~/ 60).clamp(0, 23);
    final minute = minutesSinceMidnight % 60;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  String _formatTime(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return hhmm;
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = parts[1];
    final suffix = hour >= 12 ? 'PM' : 'AM';
    final readHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$readHour:$minute $suffix';
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}
