import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fyp_foreseeme/core/services/local_notification_service.dart';
import 'package:fyp_foreseeme/core/theme/theme_provider.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_journey_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/services/milestone_detector.dart';
import 'package:fyp_foreseeme/features/medication/presentation/notification_refresh_provider.dart';

const _kHighestLevelKey = 'adherence_milestone_highest_level';
const _kLongestStreakKey = 'adherence_milestone_longest_streak';
const _kHighestAdherenceKey = 'adherence_milestone_highest_adherence';
const _kPerfectWeekKey = 'adherence_milestone_perfect_week_celebrated';

/// Persists the highest values ever celebrated (Feature 7) so a milestone
/// fires exactly once. Mirrors `ThemeNotifier`'s direct `SharedPreferences`
/// usage rather than adding a repository layer for a handful of local ints.
class MilestoneStore {
  final SharedPreferences _preferences;

  const MilestoneStore(this._preferences);

  MilestoneRecord read() => MilestoneRecord(
    highestLevelIndex: _preferences.getInt(_kHighestLevelKey) ?? 0,
    longestStreakEver: _preferences.getInt(_kLongestStreakKey) ?? 0,
    highestAdherencePercentEver:
        _preferences.getInt(_kHighestAdherenceKey) ?? 0,
    perfectWeekCelebrated: _preferences.getBool(_kPerfectWeekKey) ?? false,
  );

  Future<void> write(MilestoneRecord record) async {
    await _preferences.setInt(_kHighestLevelKey, record.highestLevelIndex);
    await _preferences.setInt(_kLongestStreakKey, record.longestStreakEver);
    await _preferences.setInt(
      _kHighestAdherenceKey,
      record.highestAdherencePercentEver,
    );
    await _preferences.setBool(
      _kPerfectWeekKey,
      record.perfectWeekCelebrated,
    );
  }
}

final milestoneStoreProvider = Provider<MilestoneStore>((ref) {
  return MilestoneStore(ref.watch(sharedPreferencesProvider));
});

/// The milestone to celebrate right now, or null. The screen calls
/// [MilestoneCelebrationNotifier.checkJourney] whenever a fresh journey
/// arrives (via `ref.listen`) and [MilestoneCelebrationNotifier.dismiss]
/// once the celebration overlay has been shown.
final milestoneCelebrationProvider =
    NotifierProvider<MilestoneCelebrationNotifier, Milestone?>(
      MilestoneCelebrationNotifier.new,
    );

class MilestoneCelebrationNotifier extends Notifier<Milestone?> {
  @override
  Milestone? build() => null;

  /// Awaited (not fire-and-forget): the record must land before the next
  /// check reads it back, so a rapid re-check (e.g. two journey emissions in
  /// quick succession) never re-celebrates the same milestone.
  Future<void> checkJourney(AdherenceJourneyModel journey) async {
    final store = ref.read(milestoneStoreProvider);
    final previousRecord = store.read();
    final milestone = MilestoneDetector.detect(
      previous: previousRecord,
      journey: journey,
    );
    final updatedRecord = MilestoneDetector.updateRecord(
      previousRecord,
      journey,
    );
    await store.write(updatedRecord);

    if (milestone != null) {
      state = milestone;
      await _notifyCelebration(milestone);
    }
  }

  /// Best-effort push notification for the in-app overlay's milestone
  /// (Phase 2.3) — reuses the same [Milestone] content, no new detection
  /// logic. The in-app overlay (already shown via `state = milestone`)
  /// remains the primary celebration surface even if this fails.
  Future<void> _notifyCelebration(Milestone milestone) async {
    try {
      final scheduler = ref.read(notificationSchedulerProvider);
      final coaching = ref.read(medicationCoachingServiceProvider);
      await scheduler.showNow(
        notificationId: LocalNotificationService.generateCoachingNotificationId(
          'milestone_${milestone.type.name}_${DateTime.now().millisecondsSinceEpoch}',
        ),
        content: coaching.buildCelebrationContent(milestone),
      );
    } catch (_) {
      // Non-fatal — see doc comment above.
    }
  }

  void dismiss() {
    state = null;
  }
}
