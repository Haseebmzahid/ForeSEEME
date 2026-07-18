import 'package:fyp_foreseeme/features/medication/domain/enums/medication_enums.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_journey_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_log_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_stats_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/daily_status.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/medication_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/services/dose_state_engine.dart';
import 'package:fyp_foreseeme/features/medication/domain/services/time_of_day_analysis.dart';

/// Turns the already-computed [AdherenceStatsModel] list (+ the raw dose
/// logs backing it) into an [AdherenceJourneyModel] — a supportive narrative
/// rather than a statistics table.
///
/// Deterministic and rule-based by design (Feature 5 explicitly rules out an
/// AI/LLM layer here): every field is a pure function of existing adherence
/// data. No I/O — repositories are fetched one layer up
/// (`adherence_journey_provider.dart`) and passed in, so this stays trivially
/// unit-testable and mirrors `AdherenceAnalyticsService`'s "pure computation"
/// shape without duplicating its streak/weeklyRate math (that's reused
/// as-is from the [AdherenceStatsModel]s it's handed).
class AdherenceJourneyService {
  const AdherenceJourneyService();

  static const List<String> _weekdayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  AdherenceJourneyModel buildJourney({
    required List<AdherenceStatsModel> stats,
    required List<AdherenceLogModel> logs,
    required List<MedicationModel> medications,
    DateTime? now,
  }) {
    final effectiveNow = now ?? DateTime.now();
    final today = _dateOnly(effectiveNow);
    final meds = stats.where((s) => s.medicationId != 'overall').toList();
    final overall = stats.firstWhere(
      (s) => s.medicationId == 'overall',
      orElse: () => const AdherenceStatsModel(
        medicationId: 'overall',
        medicationName: 'Overall',
        dosage: '',
        weeklyRate: 0,
        currentStreak: 0,
        longestStreak: 0,
        last30DaysLog: [],
        last7DaysTakenCount: 0,
        last7DaysSkippedCount: 0,
      ),
    );

    final currentPercent = (overall.weeklyRate.clamp(0.0, 1.0) * 100).round();
    final previousPercent = (overall.previousWeeklyRate.clamp(0.0, 1.0) * 100)
        .round();
    final comparedToLastWeek = currentPercent - previousPercent;
    final hasData =
        meds.isNotEmpty &&
        (overall.last7DaysTakenCount + overall.last7DaysSkippedCount) > 0;

    final longestStreakEver = meds.fold<int>(
      0,
      (max, s) => s.longestStreak > max ? s.longestStreak : max,
    );
    final currentStreakNow = meds.fold<int>(
      0,
      (max, s) => s.currentStreak > max ? s.currentStreak : max,
    );

    final level = MedicationLevelX.forPercent(currentPercent);
    final timeBuckets = computeTimeOfDayBreakdown(
      logs,
      start: today.subtract(const Duration(days: 6)),
      end: today,
    );

    final medicationPerformance = meds.map((s) {
      final percent = (s.weeklyRate.clamp(0.0, 1.0) * 100).round();
      return MedicationPerformance(
        medicationId: s.medicationId,
        name: s.medicationName,
        percent: percent,
        tier: PerformanceTierX.forPercent(percent),
      );
    }).toList();

    return AdherenceJourneyModel(
      hero: _buildHero(
        hasData: hasData,
        percent: currentPercent,
        comparedToLastWeek: comparedToLastWeek,
      ),
      level: level,
      levelProgress: _levelProgress(level, currentPercent),
      percentToNextLevel: level.next == null
          ? 0
          : (level.next!.minPercent - currentPercent).clamp(0, 100),
      achievements: _buildAchievements(
        hasAnyLog: logs.isNotEmpty,
        weeklyRatePercent: currentPercent,
        longestStreakEver: longestStreakEver,
        comparedToLastWeek: comparedToLastWeek,
        timeBuckets: timeBuckets,
      ),
      reflection: WeeklyReflection(
        adherencePercent: currentPercent,
        comparedToLastWeek: comparedToLastWeek,
        longestStreak: longestStreakEver,
        missedDoses: overall.last7DaysSkippedCount,
        bestDay: _bestDay(meds, today),
        needsAttention: _needsAttention(timeBuckets),
      ),
      insights: _buildInsights(
        currentStreak: currentStreakNow,
        comparedToLastWeek: comparedToLastWeek,
        timeBuckets: timeBuckets,
      ),
      medicationPerformance: medicationPerformance,
      todaysMission: _buildTodaysMission(
        medications: medications,
        logs: logs,
        now: effectiveNow,
        currentStreak: currentStreakNow,
      ),
      weeklyTimeline: _buildWeeklyTimeline(
        medications: medications,
        logs: logs,
        today: today,
      ),
      longestStreakEver: longestStreakEver,
    );
  }

  // ── Hero story (Feature 1) — always supportive, never shaming ────────────

  HeroStory _buildHero({
    required bool hasData,
    required int percent,
    required int comparedToLastWeek,
  }) {
    if (!hasData) {
      return const HeroStory(
        tone: HeroTone.poor,
        emoji: '🌱',
        headline: "Let's begin your journey.",
        message:
            'Add a medication and check in daily to start building your story.',
      );
    }
    if (percent >= 90) {
      return HeroStory(
        tone: HeroTone.excellent,
        emoji: '🏆',
        headline: 'Amazing work!',
        message:
            "You've maintained $percent% adherence this week. "
            "You're building healthier habits every day.",
      );
    }
    if (percent >= 70) {
      return HeroStory(
        tone: HeroTone.average,
        emoji: '🌿',
        headline: "You're making progress.",
        message: comparedToLastWeek > 0
            ? 'You improved compared to last week. Keep going.'
            : 'Keep going.',
      );
    }
    return const HeroStory(
      tone: HeroTone.poor,
      emoji: '🌱',
      headline: 'Every day is a new opportunity.',
      message: "Let's improve your adherence this week.",
    );
  }

  // ── Levels (Feature 2) ────────────────────────────────────────────────────

  double _levelProgress(MedicationLevel level, int percent) {
    final span = level.maxPercent - level.minPercent + 1;
    if (span <= 0) return 1.0;
    return ((percent - level.minPercent) / span).clamp(0.0, 1.0);
  }

  // ── Achievements (Feature 3) ──────────────────────────────────────────────

  List<Achievement> _buildAchievements({
    required bool hasAnyLog,
    required int weeklyRatePercent,
    required int longestStreakEver,
    required int comparedToLastWeek,
    required TimeOfDayBreakdown timeBuckets,
  }) {
    return [
      Achievement(
        id: 'first_checkin',
        emoji: '🔥',
        title: 'First Check-In',
        description: 'Log your very first dose',
        unlocked: hasAnyLog,
      ),
      Achievement(
        id: 'perfect_week',
        emoji: '⭐',
        title: 'Perfect Week',
        description: 'Reach 100% adherence in a week',
        unlocked: weeklyRatePercent >= 100,
      ),
      Achievement(
        id: 'streak_3',
        emoji: '🏅',
        title: '3 Day Streak',
        description: 'Take every dose 3 days in a row',
        unlocked: longestStreakEver >= 3,
      ),
      Achievement(
        id: 'streak_7',
        emoji: '🏅',
        title: '7 Day Streak',
        description: 'Take every dose 7 days in a row',
        unlocked: longestStreakEver >= 7,
      ),
      Achievement(
        id: 'morning_perfect',
        emoji: '💚',
        title: 'Never Missed Morning Medication',
        description: 'Zero missed morning doses this week',
        unlocked: timeBuckets.morningTotal > 0 && timeBuckets.morningMissed == 0,
      ),
      Achievement(
        id: 'improved_20',
        emoji: '📈',
        title: 'Improved 20%',
        description: 'Raise your adherence 20 points week-over-week',
        unlocked: comparedToLastWeek >= 20,
      ),
    ];
  }

  // ── Weekly reflection helpers (Feature 4) ─────────────────────────────────

  String? _bestDay(List<AdherenceStatsModel> meds, DateTime today) {
    if (meds.isEmpty) return null;
    final start = today.subtract(const Duration(days: 6));

    String? bestLabel;
    var bestRatio = 0.0;
    var foundAny = false;

    for (var i = 0; i < 7; i++) {
      final date = start.add(Duration(days: i));
      var taken = 0;
      var skipped = 0;
      for (final med in meds) {
        switch (_statusOn(med, date)) {
          case DailyAdherenceStatus.taken:
            taken++;
            break;
          case DailyAdherenceStatus.skipped:
            skipped++;
            break;
          case DailyAdherenceStatus.pending:
          case DailyAdherenceStatus.noSchedule:
          case null:
            break;
        }
      }
      final total = taken + skipped;
      if (total == 0) continue;
      final ratio = taken / total;
      if (!foundAny || ratio > bestRatio) {
        foundAny = true;
        bestRatio = ratio;
        bestLabel = _weekdayNames[date.weekday - 1];
      }
    }

    return (foundAny && bestRatio > 0) ? bestLabel : null;
  }

  DailyAdherenceStatus? _statusOn(AdherenceStatsModel stat, DateTime date) {
    for (final day in stat.last30DaysLog) {
      if (_sameDay(day.date, date)) return day.status;
    }
    return null;
  }

  String? _needsAttention(TimeOfDayBreakdown buckets) {
    final morning = buckets.morningRate;
    final evening = buckets.eveningRate;

    if (evening != null && evening < 0.7 && (morning == null || evening <= morning)) {
      return 'Evening medications';
    }
    if (morning != null && morning < 0.7 && (evening == null || morning < evening)) {
      return 'Morning medications';
    }
    return null;
  }

  // ── Smart insight cards (Feature 5) — deterministic, no AI ───────────────

  List<InsightCard> _buildInsights({
    required int currentStreak,
    required int comparedToLastWeek,
    required TimeOfDayBreakdown timeBuckets,
  }) {
    final insights = <InsightCard>[];

    if (currentStreak >= 5) {
      insights.add(
        InsightCard(
          emoji: '✨',
          title: 'Excellent consistency',
          message: "You haven't missed a medication in $currentStreak days.",
        ),
      );
    }

    final morning = timeBuckets.morningRate;
    final evening = timeBuckets.eveningRate;
    if (morning != null && evening != null && (morning - evening) >= 0.15) {
      insights.add(
        const InsightCard(
          emoji: '🌤️',
          title: 'Morning medications are excellent.',
          message: 'Evening reminders are being missed more frequently.',
        ),
      );
    }

    if (comparedToLastWeek >= 8) {
      insights.add(
        InsightCard(
          emoji: '📈',
          title: 'Trending upward',
          message: 'Your adherence improved by $comparedToLastWeek% this week.',
        ),
      );
    } else if (comparedToLastWeek <= -8) {
      insights.add(
        const InsightCard(
          emoji: '💡',
          title: 'A gentle nudge',
          message: "Adherence dipped a little this week — tomorrow's a fresh start.",
        ),
      );
    }

    if (insights.isEmpty) {
      insights.add(
        const InsightCard(
          emoji: '📋',
          title: 'Keep checking in',
          message: 'Log your doses daily to unlock more personalised insights.',
        ),
      );
    }

    return insights.take(3).toList();
  }

  // ── Time-of-day breakdown (shared by achievements + insights) ────────────
  //
  // Computation lives in `time_of_day_analysis.dart` — `computeTimeOfDayBreakdown`
  // — shared with `MedicationCoachingService` (Sprint UX-M2.5) so the two
  // services agree on exactly one definition of "morning" and "evening".
  //
  // NOTE: `features/insights` already has a similar-shaped time-of-day
  // breakdown (`AdherenceInsightsUseCase.strongestBucket`/`focusBucket`,
  // Sprint 4). Deliberately not reused here: that use case buckets into 3
  // tiers (Morning/Afternoon/Evening) for its own dashboard card, whereas
  // this bucketing mirrors the Morning/Evening split already established by
  // `check_in_screen.dart` within the medication feature, and reusing it
  // would add a medication → insights dependency this feature doesn't
  // otherwise have (insights already depends on medication, not the other
  // way round). Flagged as a candidate for future consolidation rather than
  // introducing a reverse cross-feature dependency for this sprint.

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  // ── Weekly Journey Timeline ────────────────────────────────────────────────
  //
  // Reconstructs each day's scheduled dose instances directly from
  // `medication.reminderTimes`, the same source `check_in_screen.dart`
  // builds its own dose list from. Deliberately not extracted into a shared
  // utility this sprint — that screen's dose-building is tightly coupled to
  // its own UI grouping (time-slot buckets, log-id generation) and is
  // untouched here; this mirrors its *shape*, not its code.

  List<DayJourneyCard> _buildWeeklyTimeline({
    required List<MedicationModel> medications,
    required List<AdherenceLogModel> logs,
    required DateTime today,
  }) {
    final active = medications.where((m) => m.isActive).toList();
    final start = today.subtract(const Duration(days: 6));
    return [
      for (var i = 0; i < 7; i++)
        _buildDayCard(
          date: start.add(Duration(days: i)),
          today: today,
          medications: active,
          logs: logs,
        ),
    ];
  }

  DayJourneyCard _buildDayCard({
    required DateTime date,
    required DateTime today,
    required List<MedicationModel> medications,
    required List<AdherenceLogModel> logs,
  }) {
    final isToday = _sameDay(date, today);
    final isPast = date.isBefore(today);

    final logsByMedAndTime = <String, Map<String, AdherenceLogModel>>{};
    for (final log in logs) {
      if (!_sameDay(_dateOnly(log.date), date)) continue;
      (logsByMedAndTime[log.medicationId] ??= {})[log.scheduledTime] = log;
    }

    var taken = 0;
    var missed = 0;
    var pending = 0;
    var morningHasDose = false;
    var morningHasPending = false;
    var morningHasMissed = false;
    var eveningHasDose = false;
    var eveningHasPending = false;
    var eveningHasMissed = false;

    for (final medication in medications) {
      if (date.isBefore(_dateOnly(medication.createdAt))) continue;

      for (final time in medication.reminderTimes) {
        final log = logsByMedAndTime[medication.id]?[time];
        final AdherenceStatus effective;
        if (log != null) {
          effective = log.status;
        } else if (isPast) {
          // Mirrors AdherenceAnalyticsService._statusForDate: an unlogged
          // dose on a day that's already over reads as missed.
          effective = AdherenceStatus.missed;
        } else {
          effective = AdherenceStatus.pending;
        }

        switch (effective) {
          case AdherenceStatus.taken:
            taken++;
            break;
          case AdherenceStatus.missed:
            missed++;
            break;
          case AdherenceStatus.pending:
            pending++;
            break;
        }

        // Binary Morning/Evening split for this card's two rows — coarser
        // than `_timeOfDayBreakdown`'s 3-tier bucketing on purpose, matching
        // the two-row layout the timeline card actually renders.
        final hour = timeOfDayHourOf(time);
        final isEveningSlot = hour != null && hour >= 17;
        if (isEveningSlot) {
          eveningHasDose = true;
          if (effective == AdherenceStatus.pending) eveningHasPending = true;
          if (effective == AdherenceStatus.missed) eveningHasMissed = true;
        } else {
          morningHasDose = true;
          if (effective == AdherenceStatus.pending) morningHasPending = true;
          if (effective == AdherenceStatus.missed) morningHasMissed = true;
        }
      }
    }

    final total = taken + missed + pending;
    final status = _dayStatus(
      taken: taken,
      missed: missed,
      total: total,
      isToday: isToday,
    );
    final morning = _bucketState(
      hasDose: morningHasDose,
      hasPending: morningHasPending,
      hasMissed: morningHasMissed,
    );
    final evening = _bucketState(
      hasDose: eveningHasDose,
      hasPending: eveningHasPending,
      hasMissed: eveningHasMissed,
    );

    return DayJourneyCard(
      date: date,
      weekdayLabel: _weekdayNames[date.weekday - 1],
      isToday: isToday,
      status: status,
      morning: morning,
      evening: evening,
      completedDoses: taken,
      totalDoses: total,
      missedDoses: missed,
      adherencePercent: total == 0 ? 0 : ((taken / total) * 100).round(),
      supportingMessage: _dayMessage(
        status: status,
        morning: morning,
        evening: evening,
        total: total,
      ),
    );
  }

  DoseCompletionState _bucketState({
    required bool hasDose,
    required bool hasPending,
    required bool hasMissed,
  }) {
    if (!hasDose) return DoseCompletionState.none;
    if (hasPending) return DoseCompletionState.pending;
    if (hasMissed) return DoseCompletionState.missed;
    return DoseCompletionState.taken;
  }

  /// See the `DayJourneyStatus` doc comment for the full rule table.
  DayJourneyStatus _dayStatus({
    required int taken,
    required int missed,
    required int total,
    required bool isToday,
  }) {
    if (total == 0) return DayJourneyStatus.buildingHabit;
    if (taken == total) return DayJourneyStatus.perfectDay;
    if (isToday && taken == 0 && missed == 0) return DayJourneyStatus.today;
    if (taken > 0 && missed == 0) return DayJourneyStatus.buildingHabit;
    if (taken > 0 && missed > 0) return DayJourneyStatus.greatProgress;
    if (isToday) return DayJourneyStatus.needsAttention;
    return DayJourneyStatus.missed;
  }

  String _dayMessage({
    required DayJourneyStatus status,
    required DoseCompletionState morning,
    required DoseCompletionState evening,
    required int total,
  }) {
    if (total == 0) return 'No medications scheduled this day.';
    switch (status) {
      case DayJourneyStatus.perfectDay:
        return 'Great work! You completed every medication today.';
      case DayJourneyStatus.greatProgress:
        if (morning == DoseCompletionState.missed) {
          return 'You missed your morning medication. Tomorrow is another opportunity.';
        }
        if (evening == DoseCompletionState.missed) {
          return 'You missed your evening medication. Tomorrow is another opportunity.';
        }
        return "Good progress today — keep it up.";
      case DayJourneyStatus.buildingHabit:
        return "You're building a great habit. Keep going today!";
      case DayJourneyStatus.today:
        return 'Your day is just getting started.';
      case DayJourneyStatus.needsAttention:
        return "Let's get back on track today — you still have time.";
      case DayJourneyStatus.missed:
        return 'This day is behind you. Tomorrow is a fresh start.';
    }
  }

  // ── Today's Mission ────────────────────────────────────────────────────────
  //
  // Reuses `DoseStateEngine.determineDoseState` (the same state machine the
  // Daily Check-In screen's dose cards use) so the mission's notion of
  // "pending" can never contradict what that screen already shows.

  TodaysMission _buildTodaysMission({
    required List<MedicationModel> medications,
    required List<AdherenceLogModel> logs,
    required DateTime now,
    required int currentStreak,
  }) {
    final today = _dateOnly(now);
    final logsByMedAndTime = <String, Map<String, AdherenceLogModel>>{};
    for (final log in logs) {
      if (!_sameDay(_dateOnly(log.date), today)) continue;
      (logsByMedAndTime[log.medicationId] ??= {})[log.scheduledTime] = log;
    }

    final doses = <_TodayDose>[];
    for (final medication in medications.where((m) => m.isActive)) {
      if (today.isBefore(_dateOnly(medication.createdAt))) continue;

      for (final time in medication.reminderTimes) {
        final log = logsByMedAndTime[medication.id]?[time];
        final doseState = DoseStateEngine.determineDoseState(
          selectedDate: today,
          reminderTime: time,
          status: log?.status ?? AdherenceStatus.pending,
          confirmedAt: log?.confirmedAt,
          now: now,
        );
        doses.add(
          _TodayDose(
            medicationName: medication.name,
            time: time,
            effectiveStatus: doseState.effectiveStatus,
          ),
        );
      }
    }

    if (doses.isEmpty) {
      return const TodaysMission(
        state: MissionState.noMedications,
        title: 'No medications scheduled today',
        message: 'Enjoy your day.',
        medicationName: null,
        rawDeadlineTime: null,
        currentStreak: 0,
      );
    }

    final pendingDoses = doses
        .where((d) => d.effectiveStatus == AdherenceStatus.pending)
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));

    if (pendingDoses.isNotEmpty) {
      final next = pendingDoses.first;
      return TodaysMission(
        state: MissionState.pending,
        title: 'Take your ${next.medicationName}',
        message: currentStreak > 0
            ? 'Reward: maintain your $currentStreak-day streak.'
            : "Reward: start today's streak.",
        medicationName: next.medicationName,
        rawDeadlineTime: next.time,
        currentStreak: currentStreak,
        pendingDosesToday: pendingDoses.length,
      );
    }

    final allTaken = doses.every(
      (d) => d.effectiveStatus == AdherenceStatus.taken,
    );
    if (allTaken) {
      return TodaysMission(
        state: MissionState.allComplete,
        title: 'Mission Complete!',
        message: 'Great job! See you tomorrow.',
        medicationName: null,
        rawDeadlineTime: null,
        currentStreak: currentStreak,
      );
    }

    return TodaysMission(
      state: MissionState.dayOver,
      title: "Today's mission is behind you",
      message: 'Tomorrow is a fresh start.',
      medicationName: null,
      rawDeadlineTime: null,
      currentStreak: currentStreak,
    );
  }

  // ── Feature 9: next reminder for a single medication ──────────────────────

  /// The next upcoming reminder for [medication], today if one remains,
  /// otherwise tomorrow's earliest. Returns null for archived medications or
  /// ones with no reminder times. Raw "HH:mm" is returned (not formatted) —
  /// the caller formats for display, matching every other screen's
  /// convention for `reminderTimes` strings.
  static NextReminder? nextReminderFor(MedicationModel medication, DateTime now) {
    if (!medication.isActive || medication.reminderTimes.isEmpty) return null;

    final today = DoseStateEngine.dateOnly(now);
    DateTime? bestToday;
    String? bestTodayRaw;

    for (final raw in medication.reminderTimes) {
      final scheduled = DoseStateEngine.scheduledDateTime(today, raw);
      if (scheduled.isAfter(now) &&
          (bestToday == null || scheduled.isBefore(bestToday))) {
        bestToday = scheduled;
        bestTodayRaw = raw;
      }
    }
    if (bestTodayRaw != null) {
      return NextReminder(label: 'Today', rawTime: bestTodayRaw);
    }

    final tomorrow = today.add(const Duration(days: 1));
    DateTime? earliest;
    String? earliestRaw;
    for (final raw in medication.reminderTimes) {
      final scheduled = DoseStateEngine.scheduledDateTime(tomorrow, raw);
      if (earliest == null || scheduled.isBefore(earliest)) {
        earliest = scheduled;
        earliestRaw = raw;
      }
    }
    if (earliestRaw == null) return null;
    return NextReminder(label: 'Tomorrow', rawTime: earliestRaw);
  }
}

class NextReminder {
  final String label;

  /// "HH:mm" 24-hour — format for display the same way `reminderTimes` is
  /// formatted everywhere else.
  final String rawTime;

  const NextReminder({required this.label, required this.rawTime});
}

class _TodayDose {
  final String medicationName;
  final String time;
  final AdherenceStatus effectiveStatus;

  const _TodayDose({
    required this.medicationName,
    required this.time,
    required this.effectiveStatus,
  });
}

