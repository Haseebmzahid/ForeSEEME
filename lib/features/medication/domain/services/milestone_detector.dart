import 'package:fyp_foreseeme/features/medication/domain/models/adherence_journey_model.dart';

/// Detects at most one celebration-worthy milestone per journey computation
/// (Feature 7), by diffing against the highest values ever recorded.
/// Pure — persistence lives in `MilestoneStore` (presentation layer).
class MilestoneDetector {
  const MilestoneDetector._();

  /// Priority order when several trigger at once: a level-up is the most
  /// significant story beat, then a first perfect week, then quieter
  /// personal-record moments.
  static Milestone? detect({
    required MilestoneRecord previous,
    required AdherenceJourneyModel journey,
  }) {
    final levelIndex = MedicationLevel.values.indexOf(journey.level);

    if (levelIndex > previous.highestLevelIndex) {
      return Milestone(
        type: MilestoneType.levelUp,
        isMajor: true,
        emoji: journey.level.emoji,
        title: 'New Level Unlocked!',
        message: "You've reached ${journey.level.label}.",
      );
    }

    if (journey.reflection.adherencePercent >= 100 &&
        !previous.perfectWeekCelebrated) {
      return const Milestone(
        type: MilestoneType.perfectWeek,
        isMajor: true,
        emoji: '⭐',
        title: 'Perfect Week!',
        message: "You didn't miss a single dose this week.",
      );
    }

    if (journey.longestStreakEver > previous.longestStreakEver &&
        journey.longestStreakEver > 0) {
      return Milestone(
        type: MilestoneType.newStreakRecord,
        isMajor: false,
        emoji: '🔥',
        title: 'New Streak Record',
        message: '${journey.longestStreakEver} days and counting.',
      );
    }

    if (journey.reflection.adherencePercent >
            previous.highestAdherencePercentEver &&
        journey.reflection.adherencePercent > 0) {
      return Milestone(
        type: MilestoneType.highestAdherence,
        isMajor: false,
        emoji: '📈',
        title: 'Highest Adherence Yet',
        message:
            '${journey.reflection.adherencePercent}% this week — your best so far.',
      );
    }

    return null;
  }

  /// Rolls every "ever" field forward to reflect [journey], regardless of
  /// which single milestone [detect] surfaced — so nothing re-celebrates.
  static MilestoneRecord updateRecord(
    MilestoneRecord previous,
    AdherenceJourneyModel journey,
  ) {
    final levelIndex = MedicationLevel.values.indexOf(journey.level);
    return previous.copyWith(
      highestLevelIndex: levelIndex > previous.highestLevelIndex
          ? levelIndex
          : previous.highestLevelIndex,
      longestStreakEver: journey.longestStreakEver > previous.longestStreakEver
          ? journey.longestStreakEver
          : previous.longestStreakEver,
      highestAdherencePercentEver:
          journey.reflection.adherencePercent >
              previous.highestAdherencePercentEver
          ? journey.reflection.adherencePercent
          : previous.highestAdherencePercentEver,
      perfectWeekCelebrated:
          previous.perfectWeekCelebrated ||
          journey.reflection.adherencePercent >= 100,
    );
  }
}
