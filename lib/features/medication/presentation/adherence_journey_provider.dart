import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fyp_foreseeme/features/medication/domain/models/adherence_journey_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/services/adherence_journey_service.dart';
import 'package:fyp_foreseeme/features/medication/presentation/adherence_analytics_provider.dart';
import 'package:fyp_foreseeme/features/medication/presentation/adherence_notifier.dart';

final adherenceJourneyServiceProvider = Provider<AdherenceJourneyService>((
  ref,
) {
  return const AdherenceJourneyService();
});

/// The storytelling layer over `adherenceAnalyticsProvider` (Sprint UX-M2.2).
/// Reuses that provider's already-computed stats (no duplicate streak/rate
/// math) and re-fetches the same 30-day log window it internally queries —
/// needed here for the day-of-week and time-of-day breakdowns
/// `AdherenceStatsModel` doesn't carry. Also watches the app's existing
/// `medicationsStreamProvider` (Sprint UX-M2.3) — the same stream the
/// Medications and Daily Check-In screens already subscribe to — for the
/// Weekly Journey Timeline and Today's Mission, which need medication names
/// and reminder times rather than just aggregated stats.
final adherenceJourneyProvider =
    FutureProvider.family<AdherenceJourneyModel, String>((ref, uid) async {
      final service = ref.watch(adherenceJourneyServiceProvider);

      if (uid.isEmpty) {
        return service.buildJourney(
          stats: const [],
          logs: const [],
          medications: const [],
        );
      }

      final stats = await ref.watch(adherenceAnalyticsProvider(uid).future);
      final medications = await ref.watch(medicationsStreamProvider.future);

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final startDate = today.subtract(const Duration(days: 29));
      final logs = await ref
          .watch(adherenceLogRepositoryProvider)
          .getLogsForDateRange(uid, startDate, today)
          .first;

      return service.buildJourney(
        stats: stats,
        logs: logs,
        medications: medications,
        now: now,
      );
    });
