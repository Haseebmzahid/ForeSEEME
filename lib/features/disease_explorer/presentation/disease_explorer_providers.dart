import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../risk/presentation/risk_provider.dart';
import '../../../core/safety/content_safety_guard.dart';
import '../../insights/presentation/insights_providers.dart';
import '../../insights/domain/services/recommendation_prioritizer.dart';
import '../../insights/domain/models/health_recommendation.dart';
import '../../risk/domain/models/risk_estimate_model.dart';
import '../domain/models/disease_risk_estimate.dart';
import '../domain/services/disease_explorer_service.dart';

// Compose the existing repository-backed cache. No duplicate Firestore queries.
final diseaseHistoryProvider = FutureProvider.autoDispose
    .family<List<DiseaseRiskEstimate>, ({String city, String disease})>((
      ref,
      key,
    ) async {
      final documents = await ref.watch(riskHistoryProvider(key.city).future);
      return DiseaseExplorerService.history(documents, key.city, key.disease);
    });

final diseaseAdviceProvider = FutureProvider.autoDispose
    .family<HealthRecommendation, ({String disease, String level})>((
      ref,
      key,
    ) async {
      final conditions = await ref.watch(userConditionsProvider.future);
      final advice = prioritizeRecommendations(
        riskLevel: RiskLevelX.fromJson(key.level),
        disease: diseaseNames[key.disease]!,
        conditions: conditions,
        repository: ref.watch(recommendationRepositoryProvider),
      ).first.recommendation;
      ContentSafetyGuard.requireCited(
        label: 'disease guidance',
        source: advice.source,
        sourceUrl: advice.sourceUrl,
      );
      return advice;
    });
