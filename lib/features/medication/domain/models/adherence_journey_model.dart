/// Storytelling layer over [AdherenceStatsModel] (Sprint UX-M2.2): turns raw
/// adherence numbers into an encouraging narrative — hero message, a level
/// progression, achievement badges, a weekly reflection, and insight cards.
///
/// Pure data classes only. All computation lives in `AdherenceJourneyService`
/// (domain/services) — no Flutter imports here.
library;

// ── Hero story (Feature 1) ──────────────────────────────────────────────────

enum HeroTone { excellent, average, poor }

class HeroStory {
  final HeroTone tone;
  final String emoji;
  final String headline;
  final String message;

  const HeroStory({
    required this.tone,
    required this.emoji,
    required this.headline,
    required this.message,
  });
}

// ── Medication journey levels (Feature 2) ───────────────────────────────────

enum MedicationLevel { beginner, buildingHabits, consistent, healthyRoutine, asthmaChampion }

extension MedicationLevelX on MedicationLevel {
  String get emoji => switch (this) {
    MedicationLevel.beginner => '🌱',
    MedicationLevel.buildingHabits => '🌿',
    MedicationLevel.consistent => '🍃',
    MedicationLevel.healthyRoutine => '🌳',
    MedicationLevel.asthmaChampion => '🏆',
  };

  String get label => switch (this) {
    MedicationLevel.beginner => 'Beginner',
    MedicationLevel.buildingHabits => 'Building Habits',
    MedicationLevel.consistent => 'Consistent',
    MedicationLevel.healthyRoutine => 'Healthy Routine',
    MedicationLevel.asthmaChampion => 'Asthma Champion',
  };

  /// Inclusive lower bound of this level's weekly-adherence percent band.
  int get minPercent => switch (this) {
    MedicationLevel.beginner => 0,
    MedicationLevel.buildingHabits => 40,
    MedicationLevel.consistent => 60,
    MedicationLevel.healthyRoutine => 80,
    MedicationLevel.asthmaChampion => 95,
  };

  /// Inclusive upper bound of this level's weekly-adherence percent band.
  int get maxPercent => switch (this) {
    MedicationLevel.beginner => 39,
    MedicationLevel.buildingHabits => 59,
    MedicationLevel.consistent => 79,
    MedicationLevel.healthyRoutine => 94,
    MedicationLevel.asthmaChampion => 100,
  };

  MedicationLevel? get next => switch (this) {
    MedicationLevel.beginner => MedicationLevel.buildingHabits,
    MedicationLevel.buildingHabits => MedicationLevel.consistent,
    MedicationLevel.consistent => MedicationLevel.healthyRoutine,
    MedicationLevel.healthyRoutine => MedicationLevel.asthmaChampion,
    MedicationLevel.asthmaChampion => null,
  };

  /// Resolves the level whose [minPercent]-[maxPercent] band contains
  /// [percent] (0-100). Falls back to [MedicationLevel.asthmaChampion] for
  /// values above every band (shouldn't happen once percent is clamped).
  static MedicationLevel forPercent(int percent) {
    for (final level in MedicationLevel.values) {
      if (percent >= level.minPercent && percent <= level.maxPercent) {
        return level;
      }
    }
    return MedicationLevel.asthmaChampion;
  }
}

// ── Achievements (Feature 3) ────────────────────────────────────────────────

class Achievement {
  final String id;
  final String emoji;
  final String title;
  final String description;
  final bool unlocked;

  const Achievement({
    required this.id,
    required this.emoji,
    required this.title,
    required this.description,
    required this.unlocked,
  });

  Achievement copyWith({bool? unlocked}) => Achievement(
    id: id,
    emoji: emoji,
    title: title,
    description: description,
    unlocked: unlocked ?? this.unlocked,
  );
}

// ── Weekly reflection (Feature 4) ───────────────────────────────────────────

class WeeklyReflection {
  final int adherencePercent;

  /// Signed percentage-point delta vs. the previous 7 days.
  final int comparedToLastWeek;
  final int longestStreak;
  final int missedDoses;

  /// Weekday name of the best-performing day this week, or null with too
  /// little data to judge.
  final String? bestDay;

  /// A gentle, non-shaming pointer to what needs attention, or null when
  /// nothing stands out.
  final String? needsAttention;

  const WeeklyReflection({
    required this.adherencePercent,
    required this.comparedToLastWeek,
    required this.longestStreak,
    required this.missedDoses,
    required this.bestDay,
    required this.needsAttention,
  });
}

// ── Smart insight cards (Feature 5) ─────────────────────────────────────────

class InsightCard {
  final String emoji;
  final String title;
  final String message;

  const InsightCard({
    required this.emoji,
    required this.title,
    required this.message,
  });
}

// ── Medication performance (Feature 6) ──────────────────────────────────────

enum PerformanceTier { excellent, good, needsAttention }

extension PerformanceTierX on PerformanceTier {
  String get label => switch (this) {
    PerformanceTier.excellent => 'Excellent',
    PerformanceTier.good => 'Good',
    PerformanceTier.needsAttention => 'Needs Attention',
  };

  static PerformanceTier forPercent(int percent) {
    if (percent >= 90) return PerformanceTier.excellent;
    if (percent >= 70) return PerformanceTier.good;
    return PerformanceTier.needsAttention;
  }
}

class MedicationPerformance {
  final String medicationId;
  final String name;
  final int percent;
  final PerformanceTier tier;

  const MedicationPerformance({
    required this.medicationId,
    required this.name,
    required this.percent,
    required this.tier,
  });
}

// ── Milestone celebration (Feature 7) ───────────────────────────────────────

enum MilestoneType { levelUp, perfectWeek, newStreakRecord, highestAdherence }

class Milestone {
  final MilestoneType type;

  /// Major milestones (level-up, a first perfect week) earn confetti; minor
  /// ones (a new streak/adherence record) get a subtle banner only.
  final bool isMajor;
  final String emoji;
  final String title;
  final String message;

  const Milestone({
    required this.type,
    required this.isMajor,
    required this.emoji,
    required this.title,
    required this.message,
  });
}

/// The highest values ever celebrated, persisted locally (SharedPreferences)
/// so a milestone fires exactly once. See `MilestoneStore`.
class MilestoneRecord {
  final int highestLevelIndex;
  final int longestStreakEver;
  final int highestAdherencePercentEver;
  final bool perfectWeekCelebrated;

  const MilestoneRecord({
    required this.highestLevelIndex,
    required this.longestStreakEver,
    required this.highestAdherencePercentEver,
    required this.perfectWeekCelebrated,
  });

  const MilestoneRecord.initial()
    : highestLevelIndex = 0,
      longestStreakEver = 0,
      highestAdherencePercentEver = 0,
      perfectWeekCelebrated = false;

  MilestoneRecord copyWith({
    int? highestLevelIndex,
    int? longestStreakEver,
    int? highestAdherencePercentEver,
    bool? perfectWeekCelebrated,
  }) {
    return MilestoneRecord(
      highestLevelIndex: highestLevelIndex ?? this.highestLevelIndex,
      longestStreakEver: longestStreakEver ?? this.longestStreakEver,
      highestAdherencePercentEver:
          highestAdherencePercentEver ?? this.highestAdherencePercentEver,
      perfectWeekCelebrated:
          perfectWeekCelebrated ?? this.perfectWeekCelebrated,
    );
  }
}

// ── Weekly Journey Timeline (Sprint UX-M2.3 — replaces the 7-Day Overview
// bar chart with seven interactive day "chapters") ─────────────────────────

/// A single dose slot's resolved state for a day-card row (Morning/Evening).
enum DoseCompletionState { taken, missed, pending, none }

/// A day's overall "personality" — six mutually exclusive, healthcare-toned
/// states. See `AdherenceJourneyService._dayStatus` for the exact rules:
/// perfectDay (100%), greatProgress (mixed but real progress), buildingHabit
/// (today, on track, nothing missed yet), today (too early to judge),
/// needsAttention (today, nothing taken yet but time remains), missed (a
/// past day that closed at 0%, framed as history rather than failure).
enum DayJourneyStatus {
  perfectDay,
  greatProgress,
  buildingHabit,
  needsAttention,
  missed,
  today,
}

extension DayJourneyStatusX on DayJourneyStatus {
  String get emoji => switch (this) {
    DayJourneyStatus.perfectDay => '🌳',
    DayJourneyStatus.greatProgress => '🌿',
    DayJourneyStatus.buildingHabit => '🌱',
    DayJourneyStatus.needsAttention => '🥀',
    DayJourneyStatus.missed => '⚠️',
    DayJourneyStatus.today => '⭐',
  };

  String get label => switch (this) {
    DayJourneyStatus.perfectDay => 'Perfect Day',
    DayJourneyStatus.greatProgress => 'Great Progress',
    DayJourneyStatus.buildingHabit => 'Building Habit',
    DayJourneyStatus.needsAttention => 'Needs Attention',
    DayJourneyStatus.missed => 'Missed',
    DayJourneyStatus.today => 'Today',
  };
}

/// One chapter of the week — a single day's medication story.
class DayJourneyCard {
  final DateTime date;
  final String weekdayLabel;
  final bool isToday;
  final DayJourneyStatus status;
  final DoseCompletionState morning;
  final DoseCompletionState evening;
  final int completedDoses;
  final int totalDoses;
  final int missedDoses;
  final int adherencePercent;
  final String supportingMessage;

  const DayJourneyCard({
    required this.date,
    required this.weekdayLabel,
    required this.isToday,
    required this.status,
    required this.morning,
    required this.evening,
    required this.completedDoses,
    required this.totalDoses,
    required this.missedDoses,
    required this.adherencePercent,
    required this.supportingMessage,
  });
}

// ── Today's Mission ──────────────────────────────────────────────────────

enum MissionState { pending, allComplete, dayOver, noMedications }

/// The single, current, actionable next step — reusing `DoseStateEngine` so
/// this never contradicts what the Daily Check-In screen already considers
/// "pending" for the same dose.
class TodaysMission {
  final MissionState state;
  final String title;
  final String message;
  final String? medicationName;

  /// "HH:mm" — formatted for display the same way `reminderTimes` is
  /// formatted everywhere else in the app.
  final String? rawDeadlineTime;
  final int currentStreak;

  const TodaysMission({
    required this.state,
    required this.title,
    required this.message,
    required this.medicationName,
    required this.rawDeadlineTime,
    required this.currentStreak,
  });
}

// ── The full journey (screen root model) ────────────────────────────────────

class AdherenceJourneyModel {
  final HeroStory hero;
  final MedicationLevel level;

  /// Progress toward [level.next], 0.0-1.0. 1.0 (maxed) at the top level.
  final double levelProgress;

  /// Percentage points remaining to the next level, 0 at the top level.
  final int percentToNextLevel;
  final List<Achievement> achievements;
  final WeeklyReflection reflection;
  final List<InsightCard> insights;
  final List<MedicationPerformance> medicationPerformance;
  final TodaysMission todaysMission;

  /// The past 7 days (oldest first, ending today) — the Weekly Journey
  /// Timeline's source of truth.
  final List<DayJourneyCard> weeklyTimeline;

  /// Longest streak across all medications — the input to milestone
  /// detection (kept on the model so the caller doesn't recompute it).
  final int longestStreakEver;

  const AdherenceJourneyModel({
    required this.hero,
    required this.level,
    required this.levelProgress,
    required this.percentToNextLevel,
    required this.achievements,
    required this.reflection,
    required this.insights,
    required this.todaysMission,
    required this.weeklyTimeline,
    required this.medicationPerformance,
    required this.longestStreakEver,
  });
}
