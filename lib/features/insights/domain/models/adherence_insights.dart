/// Part of the day a dose is scheduled in — used for gentle time-of-day patterns.
enum TimeOfDayBucket {
  morning,
  afternoon,
  evening;

  /// Display label, e.g. "Morning".
  String get label => switch (this) {
    TimeOfDayBucket.morning => 'Morning',
    TimeOfDayBucket.afternoon => 'Afternoon',
    TimeOfDayBucket.evening => 'Evening',
  };

  /// Inline phrase for supportive copy, e.g. "the morning".
  String get phrase => switch (this) {
    TimeOfDayBucket.morning => 'the morning',
    TimeOfDayBucket.afternoon => 'the afternoon',
    TimeOfDayBucket.evening => 'the evening',
  };

  /// Buckets an hour-of-day (0–23): morning < 12, afternoon < 17, else evening.
  static TimeOfDayBucket forHour(int hour) {
    if (hour < 12) return TimeOfDayBucket.morning;
    if (hour < 17) return TimeOfDayBucket.afternoon;
    return TimeOfDayBucket.evening;
  }
}

/// Descriptive, **supportive** adherence insights (Sprint 4, Prompt 7).
///
/// Read-only summary computed from existing adherence logs — never a grade or a
/// failure score. All copy is framed kindly (encouragement, gentle nudges); it
/// avoids shaming language by design. Framework-free (pure Dart): the numbers
/// come from [AdherenceInsightsUseCase], the copy is derived here deterministically.
class AdherenceInsights {
  /// Consecutive on-track days (≥1 taken, 0 missed) ending at the most recent
  /// logged day.
  final int currentStreakDays;

  /// Longest on-track run in the window.
  final int longestStreakDays;

  /// Doses confirmed taken in the window.
  final int takenCount;

  /// Doses marked missed in the window (used for gentle nudges, never blame).
  final int missedCount;

  /// The part of day the user is most consistent in, or `null` with no data.
  final TimeOfDayBucket? strongestBucket;

  /// A part of day that could use a little extra support, or `null` when there
  /// is nothing to nudge (perfect adherence, or it would duplicate the strongest).
  final TimeOfDayBucket? focusBucket;

  const AdherenceInsights({
    required this.currentStreakDays,
    required this.longestStreakDays,
    required this.takenCount,
    required this.missedCount,
    required this.strongestBucket,
    required this.focusBucket,
  });

  /// The no-data state (signed-out, empty uid, or no logs yet).
  factory AdherenceInsights.empty() => const AdherenceInsights(
    currentStreakDays: 0,
    longestStreakDays: 0,
    takenCount: 0,
    missedCount: 0,
    strongestBucket: null,
    focusBucket: null,
  );

  int get resolvedCount => takenCount + missedCount;

  /// Whether there is anything to describe yet.
  bool get hasData => resolvedCount > 0;

  /// Every resolved dose was taken — celebrated, never assumed.
  bool get isPerfect => hasData && missedCount == 0;

  // ── Supportive copy (deterministic, kind — no shaming, no scoring) ──────────

  /// A warm headline reflecting the user's recent effort.
  String get headline {
    if (!hasData) return 'Your adherence insights';
    if (isPerfect) return 'Every dose taken — beautiful consistency';
    if (currentStreakDays >= 2) {
      return "You're on a $currentStreakDays-day streak";
    }
    return "You're showing up — that's what matters";
  }

  /// A gentle, supportive elaboration: strengths first, nudges framed kindly.
  String get supportiveMessage {
    if (!hasData) {
      return 'Log a few doses and gentle, supportive patterns will appear here.';
    }
    final parts = <String>[];
    if (strongestBucket != null) {
      parts.add("You're most consistent in ${strongestBucket!.phrase}.");
    }
    if (focusBucket != null) {
      parts.add(
        'A little extra support in ${focusBucket!.phrase} could help — '
        'perhaps an extra reminder.',
      );
    }
    if (parts.isEmpty) {
      parts.add('Keep going at your own pace — every dose counts.');
    }
    return parts.join(' ');
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdherenceInsights &&
          other.currentStreakDays == currentStreakDays &&
          other.longestStreakDays == longestStreakDays &&
          other.takenCount == takenCount &&
          other.missedCount == missedCount &&
          other.strongestBucket == strongestBucket &&
          other.focusBucket == focusBucket;

  @override
  int get hashCode => Object.hash(
    currentStreakDays,
    longestStreakDays,
    takenCount,
    missedCount,
    strongestBucket,
    focusBucket,
  );

  @override
  String toString() =>
      'AdherenceInsights(streak: $currentStreakDays, longest: $longestStreakDays, '
      'taken: $takenCount, missed: $missedCount, strongest: $strongestBucket, '
      'focus: $focusBucket)';
}
