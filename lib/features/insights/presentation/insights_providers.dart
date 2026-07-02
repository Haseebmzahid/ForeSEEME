import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fyp_foreseeme/core/safety/content_safety_guard.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/insights/data/repositories/static_recommendation_repository.dart';
import 'package:fyp_foreseeme/features/insights/domain/models/adherence_insights.dart';
import 'package:fyp_foreseeme/features/insights/domain/models/health_recommendation.dart';
import 'package:fyp_foreseeme/features/insights/domain/models/weekly_report.dart';
import 'package:fyp_foreseeme/features/insights/domain/repositories/recommendation_repository.dart';
import 'package:fyp_foreseeme/features/insights/domain/services/adherence_insights_use_case.dart';
import 'package:fyp_foreseeme/features/insights/domain/services/environmental_insights.dart';
import 'package:fyp_foreseeme/features/insights/domain/services/recommendation_mapper.dart';
import 'package:fyp_foreseeme/features/insights/domain/services/recommendation_prioritizer.dart';
import 'package:fyp_foreseeme/features/insights/domain/services/weekly_report_use_case.dart';
import 'package:fyp_foreseeme/features/medication/presentation/adherence_notifier.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
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

/// Composed environmental-insights view (Sprint 5, Prompt 10): the estimate, the
/// genuine environmental drivers behind it, and the prioritized cited guidance.
class EnvironmentalInsightsView {
  final RiskEstimateModel? estimate;
  final List<EnvironmentalDriver> drivers;
  final List<PrioritizedRecommendation> guidance;

  const EnvironmentalInsightsView({
    required this.estimate,
    required this.drivers,
    required this.guidance,
  });

  /// There is something to show only when an estimate exists and it yields
  /// either real environmental drivers or prioritized guidance.
  bool get hasContent =>
      estimate != null && (drivers.isNotEmpty || guidance.isNotEmpty);
}

/// Environmental drivers of the current risk (from real attributions) + the
/// most-relevant cited guidance first (Sprint 5, Prompt 10).
///
/// Pure composition of existing signals: the drivers come from the estimate's
/// stored [attributions] via [deriveEnvironmentalDrivers] (nothing recomputed);
/// the guidance is the deterministic [prioritizeRecommendations] over the CITED
/// content library. Every guidance item is re-checked by the Rule-11 guard, so
/// un-sourced text can never surface. Degrades to empty (never errors) when there
/// is no estimate.
final environmentalInsightsProvider = FutureProvider<EnvironmentalInsightsView>((
  ref,
) async {
  RiskEstimateModel? estimate;
  try {
    estimate = await ref.watch(currentCityRiskProvider.future);
  } catch (_) {
    estimate = null;
  }

  final drivers = deriveEnvironmentalDrivers(estimate?.attributions);

  var guidance = const <PrioritizedRecommendation>[];
  if (estimate != null) {
    final conditions = await ref.watch(userConditionsProvider.future);
    guidance = prioritizeRecommendations(
      riskLevel: estimate.riskLevel,
      disease: estimate.disease,
      conditions: conditions,
      repository: ref.watch(recommendationRepositoryProvider),
    );
    // Rule 11: every surfaced advisory must be a cited lookup, never generated.
    for (final item in guidance) {
      ContentSafetyGuard.requireCited(
        label: 'recommendation ${item.recommendation.id}',
        source: item.recommendation.source,
        sourceUrl: item.recommendation.sourceUrl,
      );
    }
  }

  return EnvironmentalInsightsView(
    estimate: estimate,
    drivers: drivers,
    guidance: guidance,
  );
});

/// The current Monday (UTC) — the ISO week a weekly report covers. Overridable
/// in tests for a deterministic ``weekOf``.
final weekOfProvider = Provider<DateTime>((ref) {
  final now = DateTime.now().toUtc();
  final monday = now.subtract(Duration(days: now.weekday - DateTime.monday));
  return DateTime.utc(monday.year, monday.month, monday.day);
});

/// The composed Weekly Health Report for the current user (Sprint 5, Prompt 8).
///
/// Pure composition of EXISTING signals — the week's risk, its trend, adherence
/// insights, and a cited recommendation — via [composeWeeklyReport]. It degrades
/// gracefully: a risk read that fails (offline/denied) or a recommendation guard
/// violation is treated as "unavailable" (that section shows its empty copy)
/// rather than failing the whole digest, so the report still shows what it can.
final weeklyReportProvider = FutureProvider<WeeklyReport>((ref) async {
  RiskEstimateModel? risk;
  try {
    risk = await ref.watch(currentCityRiskProvider.future);
  } catch (_) {
    risk = null;
  }

  final trend = await ref.watch(riskTrendProvider.future);
  final adherence = await ref.watch(adherenceInsightsProvider.future);

  HealthRecommendation? recommendation;
  try {
    recommendation = await ref.watch(currentRecommendationProvider.future);
  } catch (_) {
    // Rule 11 guard tripped, or no estimate — never surface un-sourced text.
    recommendation = null;
  }

  return composeWeeklyReport(
    weekOf: ref.watch(weekOfProvider),
    risk: risk,
    trend: trend,
    adherence: adherence,
    recommendation: recommendation,
  );
});
