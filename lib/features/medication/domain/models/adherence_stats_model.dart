import 'daily_status.dart';

class AdherenceStatsModel {
  final String medicationId;
  final String medicationName;
  final String dosage;
  final double weeklyRate;

  /// The same dose-level rate computed for the 7 days immediately before the
  /// current week (days 8-14 ago). Powers week-over-week storytelling
  /// (Sprint UX-M2.2) without any extra Firestore fetch — it's derived from
  /// the same 30-day window [last30DaysLog] already covers.
  final double previousWeeklyRate;
  final int currentStreak;
  final int longestStreak;
  final List<DailyStatus> last30DaysLog;
  final int last7DaysTakenCount;
  final int last7DaysSkippedCount;

  const AdherenceStatsModel({
    required this.medicationId,
    required this.medicationName,
    required this.dosage,
    required this.weeklyRate,
    this.previousWeeklyRate = 0.0,
    required this.currentStreak,
    required this.longestStreak,
    required this.last30DaysLog,
    required this.last7DaysTakenCount,
    required this.last7DaysSkippedCount,
  });

  AdherenceStatsModel copyWith({
    String? medicationId,
    String? medicationName,
    String? dosage,
    double? weeklyRate,
    double? previousWeeklyRate,
    int? currentStreak,
    int? longestStreak,
    List<DailyStatus>? last30DaysLog,
    int? last7DaysTakenCount,
    int? last7DaysSkippedCount,
  }) {
    return AdherenceStatsModel(
      medicationId: medicationId ?? this.medicationId,
      medicationName: medicationName ?? this.medicationName,
      dosage: dosage ?? this.dosage,
      weeklyRate: weeklyRate ?? this.weeklyRate,
      previousWeeklyRate: previousWeeklyRate ?? this.previousWeeklyRate,
      currentStreak: currentStreak ?? this.currentStreak,
      longestStreak: longestStreak ?? this.longestStreak,
      last30DaysLog: last30DaysLog ?? this.last30DaysLog,
      last7DaysTakenCount: last7DaysTakenCount ?? this.last7DaysTakenCount,
      last7DaysSkippedCount:
          last7DaysSkippedCount ?? this.last7DaysSkippedCount,
    );
  }

  @override
  String toString() {
    return 'AdherenceStatsModel('
        'medicationId: $medicationId, '
        'medicationName: $medicationName, '
        'weeklyRate: $weeklyRate, '
        'previousWeeklyRate: $previousWeeklyRate, '
        'currentStreak: $currentStreak, '
        'longestStreak: $longestStreak'
        ')';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AdherenceStatsModel &&
            other.medicationId == medicationId &&
            other.medicationName == medicationName &&
            other.dosage == dosage &&
            other.weeklyRate == weeklyRate &&
            other.previousWeeklyRate == previousWeeklyRate &&
            other.currentStreak == currentStreak &&
            other.longestStreak == longestStreak &&
            other.last30DaysLog == last30DaysLog &&
            other.last7DaysTakenCount == last7DaysTakenCount &&
            other.last7DaysSkippedCount == last7DaysSkippedCount;
  }

  @override
  int get hashCode {
    return Object.hash(
      medicationId,
      medicationName,
      dosage,
      weeklyRate,
      previousWeeklyRate,
      currentStreak,
      longestStreak,
      Object.hashAll(last30DaysLog),
      last7DaysTakenCount,
      last7DaysSkippedCount,
    );
  }
}
