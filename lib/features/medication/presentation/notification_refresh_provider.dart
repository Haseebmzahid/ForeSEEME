import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fyp_foreseeme/core/routes/app_router.dart';
import 'package:fyp_foreseeme/core/services/local_notification_service.dart';
import 'package:fyp_foreseeme/core/theme/theme_provider.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/medication/data/services/local_notification_scheduler_adapter.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_journey_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/services/medication_coaching_service.dart';
import 'package:fyp_foreseeme/features/medication/domain/services/medication_notification_orchestrator.dart';
import 'package:fyp_foreseeme/features/medication/domain/services/notification_scheduler.dart';
import 'package:fyp_foreseeme/features/medication/presentation/adherence_analytics_provider.dart';
import 'package:fyp_foreseeme/features/medication/presentation/adherence_journey_provider.dart';
import 'package:fyp_foreseeme/features/medication/presentation/adherence_notifier.dart';
import 'package:fyp_foreseeme/features/medication/presentation/services/medication_notification_tap_handler.dart';

// ── Core building blocks ────────────────────────────────────────────────────

final notificationSchedulerProvider = Provider<NotificationScheduler>((ref) {
  return const LocalNotificationSchedulerAdapter();
});

final medicationCoachingServiceProvider = Provider<MedicationCoachingService>((
  ref,
) {
  return const MedicationCoachingService();
});

final medicationNotificationOrchestratorProvider =
    Provider<MedicationNotificationOrchestrator>((ref) {
      return MedicationNotificationOrchestrator(
        scheduler: ref.watch(notificationSchedulerProvider),
        coaching: ref.watch(medicationCoachingServiceProvider),
      );
    });

// ── Deep linking (Phase 6) ───────────────────────────────────────────────────

/// Wires medication-notification taps to navigation. Started once at app
/// launch, mirroring `fcmMessageHandlerProvider`.
final medicationNotificationTapHandlerProvider =
    Provider<MedicationNotificationTapHandler>((ref) {
      final handler = MedicationNotificationTapHandler(
        tapStream: LocalNotificationService.onNotificationTapped,
        consumeInitialPayload: LocalNotificationService.consumeLaunchPayload,
        navigate: (route) => ref.read(appRouterProvider).go(route),
      );
      ref.onDispose(handler.dispose);
      return handler;
    });

// ── Refresh pipeline (Phases 3/4/8) ─────────────────────────────────────────

/// [container] rather than a `Ref`: both `Ref` (providers) and `WidgetRef`
/// (widgets) expose the same underlying [ProviderContainer] via `.container`
/// (they're unrelated sealed types otherwise, so neither can be passed where
/// the other is expected). This lets [refreshMedicationNotifications] be the
/// single source of truth for scheduling — called directly from
/// `MedicationNotifier.addMedication`/`updateMedication` for immediate
/// coaching-content feedback, from a `Provider` (`notificationRefreshProvider`,
/// on every medications-list change and cold start), and from a
/// `ConsumerStatefulWidget` (`MedicationCardWidget`, after a check-in).
///
/// Best-effort refresh of every medication-coaching notification for [uid].
/// Reuses the already-computed journey/stats providers (no new Firestore
/// reads beyond what the Adherence Journey screen already performs); never
/// throws to its caller — a failed refresh just means the next trigger
/// (app open, check-in, medication edit) tries again, and today's already-
/// scheduled reminder keeps whatever content was last set successfully.
Future<void> refreshMedicationNotifications(
  ProviderContainer container,
  String uid,
) async {
  if (uid.isEmpty) return;
  try {
    final medications = await container.read(medicationsStreamProvider.future);
    final stats = await container.read(adherenceAnalyticsProvider(uid).future);
    final journey = await container.read(adherenceJourneyProvider(uid).future);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startDate = today.subtract(const Duration(days: 29));
    final logs = await container
        .read(adherenceLogRepositoryProvider)
        .getLogsForDateRange(uid, startDate, today)
        .first;

    final orchestrator = container.read(medicationNotificationOrchestratorProvider);
    await orchestrator.refresh(
      medications: medications,
      stats: stats,
      logs: logs,
      journey: journey,
      now: now,
    );

    await _refreshWeeklyReflection(container, journey, now);
    await _maybeCelebrateMissionComplete(container, journey, now);
  } catch (e, st) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: e,
        stack: st,
        library: 'notifications',
        context: ErrorDescription(
          'refreshing medication coaching notifications',
        ),
      ),
    );
  }
}

/// Reschedules the Sunday-evening weekly summary (Phase 2.4) as a one-off
/// for the upcoming Sunday 6pm — refreshed on every call so its content
/// stays current with this week's actual numbers.
Future<void> _refreshWeeklyReflection(
  ProviderContainer container,
  AdherenceJourneyModel journey,
  DateTime now,
) async {
  final scheduler = container.read(notificationSchedulerProvider);
  final coaching = container.read(medicationCoachingServiceProvider);
  await scheduler.scheduleOnce(
    notificationId: LocalNotificationService.generateCoachingNotificationId(
      'weekly_reflection',
    ),
    content: coaching.buildReflectionContent(journey.reflection),
    time: nextSundayEvening(now),
  );
}

/// Fires the "Mission Complete" celebration at most once per calendar day —
/// gated the same way `MilestoneStore` gates milestones, via a date-stamped
/// SharedPreferences flag (Phase 2.3, Phase 8: never repeat a celebration).
Future<void> _maybeCelebrateMissionComplete(
  ProviderContainer container,
  AdherenceJourneyModel journey,
  DateTime now,
) async {
  if (journey.todaysMission.state != MissionState.allComplete) return;

  final preferences = container.read(sharedPreferencesProvider);
  final todayKey = '${now.year}-${now.month}-${now.day}';
  if (preferences.getString(_kMissionCelebratedDateKey) == todayKey) return;

  final scheduler = container.read(notificationSchedulerProvider);
  final coaching = container.read(medicationCoachingServiceProvider);
  await scheduler.showNow(
    notificationId: LocalNotificationService.generateCoachingNotificationId(
      'mission_complete_$todayKey',
    ),
    content: coaching.buildMissionCompleteContent(journey.todaysMission),
  );
  await preferences.setString(_kMissionCelebratedDateKey, todayKey);
}

const _kMissionCelebratedDateKey = 'notif_mission_complete_celebrated_date';

/// The next Sunday at 18:00 strictly after [now].
DateTime nextSundayEvening(DateTime now) {
  final daysUntilSunday = (DateTime.sunday - now.weekday) % 7;
  final candidateDay = DateTime(
    now.year,
    now.month,
    now.day,
  ).add(Duration(days: daysUntilSunday));
  var target = DateTime(
    candidateDay.year,
    candidateDay.month,
    candidateDay.day,
    18,
  );
  if (!target.isAfter(now)) {
    target = target.add(const Duration(days: 7));
  }
  return target;
}

/// Auto-triggers a refresh whenever the medications list changes — covers
/// medication add/edit/archive (Phase 8: notifications never go stale after
/// a CRUD change) and cold app start. `fireImmediately: true` is required
/// for the cold-start case: `ref.listen` only fires on *subsequent* state
/// transitions by default, so without it, a medication that already existed
/// before this listener attached (i.e. everything on a normal login, since
/// `medicationsStreamProvider` may already be resolved elsewhere in the
/// widget tree by the time `AppShell` builds) would never get refreshed
/// until its next unrelated CRUD change. `addMedication`/`updateMedication`
/// already call [refreshMedicationNotifications] directly for their own
/// immediate feedback; this listener is what keeps *every other* medication
/// current on every app open. Activated by watching it once from an
/// always-mounted widget (`AppShell`); Riverpod keeps the underlying
/// listener alive for the rest of the app session.
final notificationRefreshProvider = Provider<void>((ref) {
  ref.listen(medicationsStreamProvider, (previous, next) {
    next.whenData((_) {
      final uid = ref.read(authStateProvider).value?.uid ?? '';
      unawaited(refreshMedicationNotifications(ref.container, uid));
    });
  }, fireImmediately: true);
});
