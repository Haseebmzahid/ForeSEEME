import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fyp_foreseeme/core/safety/content_safety_guard.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/insights/data/repositories/static_recommendation_repository.dart';
import 'package:fyp_foreseeme/features/insights/domain/models/adherence_insights.dart';
import 'package:fyp_foreseeme/features/insights/domain/models/health_recommendation.dart';
import 'package:fyp_foreseeme/features/insights/domain/repositories/recommendation_repository.dart';
import 'package:fyp_foreseeme/features/insights/domain/services/adherence_insights_use_case.dart';
import 'package:fyp_foreseeme/features/insights/domain/services/recommendation_mapper.dart';
import 'package:fyp_foreseeme/features/medication/presentation/adherence_notifier.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';

/// The verified recommendation content library. Overridable with a fake in tests.
///
/// Depends on the ABSTRACT type (like `riskRepositoryProvider`) so it can be
/// swapped; the concrete table lives in [StaticRecommendationRepository].
final recommendationRepositoryProvider = Provider<RecommendationRepository>((
  ref,
) {
  return const StaticRecommendationRepository();
});

/// The signed-in user's chronic conditions from their health profile, or `[]`.
///
/// Mirrors `userCityProvider`: reads the same profile, collapses auth-absent /
/// no-profile / read-failure to an *empty* list (an empty state, never an
/// error), and rebuilds reactively when auth or the profile changes.
final userConditionsProvider = FutureProvider<List<String>>((ref) async {
  final user = await ref.watch(authStateProvider.future);
  if (user == null) return const [];

  final result = await ref
      .read(healthProfileRepositoryProvider)
      .getProfile(user.uid);

  return result.fold(
    (_) => const [],
    (profile) => profile?.chronicConditions ?? const [],
  );
});

/// The cited recommendation for the current user, given today's city risk and
/// their conditions — surfaced on the dashboard (Prompt 6).
///
/// Deterministic lookup, **never generated**: derives the `(category, driver)`
/// key via [resolveKey] and reads it from [recommendationRepositoryProvider].
/// Always resolves to a sourced advisory — the cited default when there is no
/// current estimate or the user has no condition matched by the current driver.
final currentRecommendationProvider = FutureProvider<HealthRecommendation>((
  ref,
) async {
  final repository = ref.watch(recommendationRepositoryProvider);

  final risk = await ref.watch(currentCityRiskProvider.future);
  final HealthRecommendation recommendation;
  if (risk == null) {
    // No estimate for the user's city yet → safe cited default (total lookup).
    recommendation = repository.lookup('*', '*');
  } else {
    final conditions = await ref.watch(userConditionsProvider.future);
    final key = resolveKey(conditions, risk.disease);
    recommendation = repository.lookup(key.category ?? '*', key.driver);
  }

  // Rule 11 guardrail: whatever advisory reaches the user must be a cited
  // lookup, never generated. A violation surfaces as an AsyncError that the
  // recommendation card hides — it can never show un-sourced medical text.
  ContentSafetyGuard.requireCited(
    label: 'recommendation ${recommendation.id}',
    source: recommendation.source,
    sourceUrl: recommendation.sourceUrl,
  );
  return recommendation;
});

/// The read-only adherence-intelligence use case (Prompt 7). Overridable in tests.
///
/// Reuses the frozen Sprint-1 [adherenceLogRepositoryProvider] — additive and
/// read-only; it never writes to `adherenceLogs`.
final adherenceInsightsUseCaseProvider = Provider<AdherenceInsightsUseCase>((
  ref,
) {
  return AdherenceInsightsUseCase(
    adherenceLogRepository: ref.watch(adherenceLogRepositoryProvider),
  );
});

/// Supportive adherence insights for the current user (Prompt 7).
///
/// Resolves to [AdherenceInsights.empty] when signed out or with no logs (a calm
/// empty state, never an error), and rebuilds when auth changes.
final adherenceInsightsProvider = FutureProvider<AdherenceInsights>((
  ref,
) async {
  final user = await ref.watch(authStateProvider.future);
  if (user == null) return AdherenceInsights.empty();

  return ref.watch(adherenceInsightsUseCaseProvider).compute(user.uid);
});
