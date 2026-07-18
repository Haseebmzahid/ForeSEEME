/// Pure mapping from a medication-notification payload to an in-app route
/// (Sprint UX-M2.5, Phase 6). Mirrors `AlertDeepLinkRouter` in
/// `features/alerts` — no navigation, no side effects, fully unit-testable.
/// The payload is simply the `NotificationCategory.name` the notification
/// was built with (see `MedicationCoachingService`).
class MedicationDeepLinkRouter {
  MedicationDeepLinkRouter._();

  /// Safe destination when the payload is missing or unrecognised.
  static const String fallbackRoute = '/home';

  /// Action/Recovery notifications are "what should I do right now" — they
  /// open Daily Check-In, where a dose is actually marked taken. Never the
  /// bare Dashboard.
  static const Set<String> _checkInCategories = {'action', 'recovery'};

  /// Celebration/Reflection/Coaching notifications are "how am I doing" —
  /// they open the Adherence Journey, where Today's Mission, Achievements,
  /// and Weekly Reflection all already live.
  static const Set<String> _journeyCategories = {
    'celebration',
    'reflection',
    'coaching',
  };

  static String resolve(String? payload) {
    final category = payload?.trim();
    if (category == null || category.isEmpty) return fallbackRoute;
    if (_checkInCategories.contains(category)) return '/check-in';
    if (_journeyCategories.contains(category)) return '/adherence-history';
    return fallbackRoute;
  }
}
