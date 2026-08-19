import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fyp_foreseeme/features/alerts/domain/models/notification_preferences.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/alerts_providers.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/health_profile/domain/services/profile_completeness_service.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/medication/presentation/adherence_notifier.dart';

/// Derived state backing the Profile Hub.
///
/// Every provider here is a **projection of existing providers** — no new
/// repository, no new Firestore path, no new backend contract. The screen reads
/// these instead of reaching for repositories itself (Golden Rule 1).

/// The scoring service. A `Provider` rather than a bare const so tests can
/// override it and so the dependency is explicit.
final profileCompletenessServiceProvider = Provider<ProfileCompletenessService>(
  (ref) => const ProfileCompletenessService(),
);

/// How complete the signed-in user's profile is, from real stored data.
///
/// Composes the auth user, the health profile and the medication list. Stays in
/// `AsyncLoading` until all three have resolved, so the hero ring animates to a
/// real value rather than snapping up from a placeholder zero.
final profileCompletenessProvider = FutureProvider<ProfileCompleteness>((
  ref,
) async {
  final user = await ref.watch(authStateProvider.future);
  final profile = await ref.watch(currentHealthProfileProvider.future);
  final medications = await ref.watch(medicationsStreamProvider.future);

  final active = medications.where((m) => m.isActive).toList();

  return ref
      .watch(profileCompletenessServiceProvider)
      .score(
        displayName: user?.displayName,
        photoUrl: user?.photoUrl,
        hasProfile: profile != null,
        city: profile?.city,
        chronicConditions: profile?.chronicConditions ?? const [],
        activeMedicationCount: active.length,
        medicationsWithRemindersCount: active
            .where((m) => m.reminderTimes.isNotEmpty)
            .length,
      );
});

/// The next scheduled medication reminder time as `HH:mm`, or `null` when the
/// user has no active medication carrying a reminder.
///
/// "Next" is the earliest reminder at or after the current wall-clock minute;
/// once the day's last reminder has passed it wraps to the earliest of the day,
/// which is the next one that will actually fire. This is a *display* read of
/// times the user themselves configured — it schedules nothing and is not a
/// source of dosing truth.
final nextReminderTimeProvider = Provider<AsyncValue<String?>>((ref) {
  final medications = ref.watch(medicationsStreamProvider);

  return medications.whenData((list) {
    final times = <int>{};
    for (final medication in list.where((m) => m.isActive)) {
      for (final raw in medication.reminderTimes) {
        final minutes = _minutesOfDay(raw);
        if (minutes != null) times.add(minutes);
      }
    }
    if (times.isEmpty) return null;

    final sorted = times.toList()..sort();
    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;

    final next = sorted.firstWhere(
      (m) => m >= nowMinutes,
      orElse: () => sorted.first,
    );
    return _formatMinutes(next);
  });
});

/// Parses `HH:mm` into a minute-of-day, or `null` when malformed.
int? _minutesOfDay(String value) {
  final parts = value.split(':');
  if (parts.length != 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
  return hour * 60 + minute;
}

String _formatMinutes(int minutes) {
  final hour = (minutes ~/ 60).toString().padLeft(2, '0');
  final minute = (minutes % 60).toString().padLeft(2, '0');
  return '$hour:$minute';
}

/// Whether **any** risk-alert category is currently enabled.
///
/// The prototype's Notifications card carries one switch, while the stored
/// contract is three independent booleans plus a per-condition map. Rather than
/// invent a fourth stored field, the switch reads as a master mute over what is
/// already there: on when at least one category would deliver, off when none
/// would. The per-category detail stays editable on the notification settings
/// screen, which this card links to.
bool notificationsActive(NotificationPreferences preferences) =>
    preferences.highRiskAlerts ||
    preferences.mediumRiskAlerts ||
    preferences.lowRiskUpdates;

/// Applies the master mute.
///
/// Muting clears all three categories. Un-muting restores the app's own
/// documented defaults (High + Medium on, Low off) rather than switching
/// everything on — turning the switch back on must not sign the user up for
/// more than they had, and `NotificationPreferences.defaults()` is the single
/// place that opinion lives.
///
/// Per-condition selections are deliberately left untouched, so a user who
/// mutes and un-mutes gets their condition choices back exactly as they were.
Future<void> setNotificationsActive(WidgetRef ref, bool active) {
  final current = ref.read(notificationPreferencesControllerProvider).value;
  if (current == null) return Future.value();

  return ref
      .read(notificationPreferencesControllerProvider.notifier)
      .setAllRiskCategories(enabled: active);
}
