import 'package:fyp_foreseeme/features/insights/domain/models/adherence_insights.dart';
import 'package:fyp_foreseeme/features/medication/domain/enums/medication_enums.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_log_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/repositories/adherence_log_repository.dart';

/// Read-only adherence intelligence (Sprint 4, Prompt 7).
///
/// Descriptive analytics over the **existing** `adherenceLogs` — it never writes,
/// and it reuses the frozen [AdherenceLogRepository] (Sprint 1). The heavy lifting
/// is the pure [analyze] function (no I/O), so the math is fully unit-testable
/// with fixtures; [compute] only fetches the window and delegates.
///
/// Framing is supportive by contract: streaks and strengths are highlighted;
/// misses feed only a gentle nudge, never a score or blame (see
/// [AdherenceInsights]).
class AdherenceInsightsUseCase {
  final AdherenceLogRepository adherenceLogRepository;

  const AdherenceInsightsUseCase({required this.adherenceLogRepository});

  /// Trailing window analysed (days), matching the adherence analytics service.
  static const int windowDays = 30;

  /// Fetches the trailing window for [uid] and computes insights. Read-only.
  Future<AdherenceInsights> compute(String uid, {DateTime? now}) async {
    if (uid.isEmpty) return AdherenceInsights.empty();

    final today = _dateOnly(now ?? DateTime.now());
    final start = today.subtract(const Duration(days: windowDays - 1));

    final logs = await adherenceLogRepository
        .getLogsForDateRange(uid, start, today)
        .first;

    return analyze(logs, today: today);
  }

  /// Pure computation: descriptive insights from a list of adherence [logs].
  ///
  /// - **Streaks:** an on-track day has ≥1 taken and 0 missed doses; the current
  ///   streak counts consecutive calendar days back from the most recent logged
  ///   day, the longest is the best such run in range.
  /// - **Time-of-day:** doses are bucketed by scheduled hour; the strongest
  ///   bucket has the highest taken-rate, the focus bucket the lowest (only when
  ///   it has misses and differs from the strongest).
  /// - Pending/unparseable logs are ignored (only resolved taken/missed count).
  static AdherenceInsights analyze(
    List<AdherenceLogModel> logs, {
    required DateTime today,
  }) {
    final normToday = _dateOnly(today);

    // Per-day resolved tallies (only days with ≥1 taken/missed appear).
    final byDay = <DateTime, _Tally>{};
    // Per-bucket resolved tallies.
    final byBucket = <TimeOfDayBucket, _Tally>{};
    var takenCount = 0;
    var missedCount = 0;

    for (final log in logs) {
      final isTaken = log.status == AdherenceStatus.taken;
      final isMissed = log.status == AdherenceStatus.missed;
      if (!isTaken && !isMissed) continue; // ignore pending

      if (isTaken) takenCount++;
      if (isMissed) missedCount++;

      final day = _dateOnly(log.date);
      (byDay[day] ??= _Tally()).add(taken: isTaken, missed: isMissed);

      final bucket = _bucketFor(log.scheduledTime);
      if (bucket != null) {
        (byBucket[bucket] ??= _Tally()).add(taken: isTaken, missed: isMissed);
      }
    }

    if (takenCount == 0 && missedCount == 0) {
      return AdherenceInsights.empty();
    }

    final currentStreak = _currentStreak(byDay);
    final longestStreak = _longestStreak(byDay);
    final strongest = _strongestBucket(byBucket);
    var focus = _focusBucket(byBucket);
    // Don't contradict the strength with an identical "needs work" nudge.
    if (focus != null && focus == strongest) focus = null;

    // (normToday retained for symmetry with compute(); streaks are anchored on
    // the latest logged day so an un-logged 'today' never zeroes a real streak.)
    assert(normToday == _dateOnly(today));

    return AdherenceInsights(
      currentStreakDays: currentStreak,
      longestStreakDays: longestStreak,
      takenCount: takenCount,
      missedCount: missedCount,
      strongestBucket: strongest,
      focusBucket: focus,
    );
  }

  // ── Streak helpers ──────────────────────────────────────────────────────────

  static bool _onTrack(_Tally t) => t.taken > 0 && t.missed == 0;

  /// Consecutive calendar days ending at the most recent logged day that are all
  /// on-track. Zero if the most recent logged day had a miss.
  static int _currentStreak(Map<DateTime, _Tally> byDay) {
    if (byDay.isEmpty) return 0;
    final latest = byDay.keys.reduce((a, b) => a.isAfter(b) ? a : b);
    var streak = 0;
    var cursor = latest;
    while (byDay[cursor] != null && _onTrack(byDay[cursor]!)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// Longest run of consecutive on-track calendar days in range.
  static int _longestStreak(Map<DateTime, _Tally> byDay) {
    final days = byDay.keys.toList()..sort();
    var longest = 0;
    var run = 0;
    DateTime? prev;
    for (final day in days) {
      if (!_onTrack(byDay[day]!)) {
        run = 0;
        prev = day;
        continue;
      }
      if (prev != null && day.difference(prev).inDays == 1) {
        run++;
      } else {
        run = 1;
      }
      if (run > longest) longest = run;
      prev = day;
    }
    return longest;
  }

  // ── Time-of-day helpers ─────────────────────────────────────────────────────

  static TimeOfDayBucket? _bucketFor(String scheduledTime) {
    final parts = scheduledTime.split(':');
    if (parts.isEmpty) return null;
    final hour = int.tryParse(parts.first);
    if (hour == null || hour < 0 || hour > 23) return null;
    return TimeOfDayBucket.forHour(hour);
  }

  /// Bucket with the highest taken-rate (ties → more doses, then earlier bucket).
  static TimeOfDayBucket? _strongestBucket(
    Map<TimeOfDayBucket, _Tally> byBucket,
  ) {
    TimeOfDayBucket? best;
    _Tally? bestT;
    for (final bucket in TimeOfDayBucket.values) {
      final t = byBucket[bucket];
      if (t == null || t.resolved == 0) continue;
      if (bestT == null ||
          t.takenRate > bestT.takenRate ||
          (t.takenRate == bestT.takenRate && t.resolved > bestT.resolved)) {
        best = bucket;
        bestT = t;
      }
    }
    return best;
  }

  /// Bucket with the lowest taken-rate among those with misses (ties → more
  /// misses, then earlier bucket). Null when nothing was missed.
  static TimeOfDayBucket? _focusBucket(Map<TimeOfDayBucket, _Tally> byBucket) {
    TimeOfDayBucket? worst;
    _Tally? worstT;
    for (final bucket in TimeOfDayBucket.values) {
      final t = byBucket[bucket];
      if (t == null || t.missed == 0) continue;
      if (worstT == null ||
          t.takenRate < worstT.takenRate ||
          (t.takenRate == worstT.takenRate && t.missed > worstT.missed)) {
        worst = bucket;
        worstT = t;
      }
    }
    return worst;
  }

  static DateTime _dateOnly(DateTime v) => DateTime(v.year, v.month, v.day);
}

/// Mutable taken/missed counter used only inside [AdherenceInsightsUseCase.analyze].
class _Tally {
  int taken = 0;
  int missed = 0;

  void add({required bool taken, required bool missed}) {
    if (taken) this.taken++;
    if (missed) this.missed++;
  }

  int get resolved => taken + missed;
  double get takenRate => resolved == 0 ? 0 : taken / resolved;
}
