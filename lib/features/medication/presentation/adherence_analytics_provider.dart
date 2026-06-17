import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_stats_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/services/adherence_analytics_service.dart';
import 'package:fyp_foreseeme/features/medication/presentation/adherence_notifier.dart';
import 'package:fyp_foreseeme/features/medication/presentation/medication_notifier.dart';

final adherenceAnalyticsServiceProvider = Provider<AdherenceAnalyticsService>((
  ref,
) {
  return AdherenceAnalyticsService(
    adherenceLogRepository: ref.watch(adherenceLogRepositoryProvider),
    medicationRepository: ref.watch(medicationRepositoryProvider),
  );
});

final adherenceAnalyticsProvider =
    FutureProvider.family<List<AdherenceStatsModel>, String>((ref, uid) {
      if (uid.isEmpty) return Future.value(const []);

      final service = ref.watch(adherenceAnalyticsServiceProvider);
      return service.computeStats(uid);
    });
