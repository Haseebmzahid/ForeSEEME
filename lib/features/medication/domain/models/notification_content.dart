/// The behavioral-coaching notification system's shared vocabulary (Sprint
/// UX-M2.5). Pure data — no Flutter, no plugin types — so the whole coaching
/// pipeline stays testable without a device.
library;

/// The five notification categories (Phase 2). Every notification answers
/// exactly one of: what should I do / why does it matter / what happens if I
/// do it / how am I progressing / how can I improve.
enum NotificationCategory { action, recovery, celebration, reflection, coaching }

/// A fully-formed notification, ready to hand to a `NotificationScheduler`.
/// [payload] encodes the category (and optional context) so a tap can be
/// routed without re-deriving it — see `MedicationDeepLinkRouter`.
class NotificationContent {
  final NotificationCategory category;
  final String title;
  final String body;
  final String payload;

  const NotificationContent({
    required this.category,
    required this.title,
    required this.body,
    required this.payload,
  });
}

/// A deterministic, explainable suggestion to shift a medication's reminder
/// time — Phase 3's flagship "Adaptive Reminder Intelligence". Never applied
/// automatically: it's surfaced as a coaching notification / insight, and
/// only takes effect if the user edits the medication themselves.
class TimingRecommendation {
  final String medicationId;
  final String medicationName;

  /// "HH:mm" — the medication's current scheduled reminder time.
  final String currentReminderTime;

  /// "HH:mm" — the recommended time, derived from the average actual
  /// confirmed-taken time over the trailing window.
  final String recommendedTime;

  /// How many minutes earlier than the current reminder the user tends to
  /// actually take this dose. Always positive (a recommendation only ever
  /// fires when it would move the reminder earlier — see
  /// `MedicationCoachingService.analyzeTimingRecommendation`).
  final int minutesEarlier;

  const TimingRecommendation({
    required this.medicationId,
    required this.medicationName,
    required this.currentReminderTime,
    required this.recommendedTime,
    required this.minutesEarlier,
  });
}
