import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fyp_foreseeme/features/health_profile/domain/constants/cities_constants.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/risk/data/repositories/firestore_risk_repository.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/trend_direction.dart';
import 'package:fyp_foreseeme/features/risk/domain/repositories/risk_repository.dart';
import 'package:fyp_foreseeme/features/risk/domain/services/risk_trend_service.dart';

/// Provides the concrete [RiskRepository].
///
/// Mirrors `authRepositoryProvider` / `medicationRepositoryProvider`: depends on
/// the ABSTRACT type, so it can be overridden with [FakeRiskRepository] in
/// tests/dev. This file imports no `firebase_*` / Flutter-widget libraries —
/// Firebase stays inside [FirestoreRiskRepository] (GOLDEN_RULES rule 3).
final riskRepositoryProvider = Provider<RiskRepository>((ref) {
  return FirestoreRiskRepository();
});

/// Latest risk estimate for an explicit [city], as `AsyncValue<RiskEstimate?>`.
///
/// Read-only (ADR-001); never calls `/predict`. This is the reusable primitive
/// the Sprint-3 dashboard plugs into.
final latestRiskForCityProvider =
    FutureProvider.family<RiskEstimateModel?, String>((ref, city) {
      final repository = ref.watch(riskRepositoryProvider);
      return repository.getLatestRiskForCity(city);
    });

/// Latest risk estimate for the *current user's* city, as
/// `AsyncValue<RiskEstimate?>`.
///
/// Derives the city from [userCityProvider], then delegates to
/// [latestRiskForCityProvider]. This is the single source the dashboard binds
/// to; its `AsyncValue` maps directly onto the four UI states:
///
/// * **loading** — `AsyncLoading` while the city / estimate resolve;
/// * **data**    — `AsyncData(estimate)` with a real [RiskEstimateModel];
/// * **empty**   — `AsyncData(null)` when there is no user, no city on file, or
///   no estimate yet for the city (a clean empty state, never a crash);
/// * **error / offline-without-cache** — `AsyncError`, surfaced by the read
///   throwing (e.g. a denied read, or offline with nothing cached). When the
///   device is offline *with* a cached estimate, Firestore serves it and this
///   resolves to **data** transparently (see
///   [FirestoreRiskRepository.getLatestRiskForCity]).
final currentCityRiskProvider = FutureProvider<RiskEstimateModel?>((ref) async {
  final city = await ref.watch(userCityProvider.future);
  if (city == null) return null;

  return ref.watch(latestRiskForCityProvider(city).future);
});

/// Trailing risk history for an explicit [city] (newest first), as
/// `AsyncValue<List<RiskEstimate>>`.
///
/// Additive read (Prompt 3); fetches the last [kTrendWindowWeeks] estimates.
/// Reuses the same `riskEstimates` collection — never the write path.
final riskHistoryProvider =
    FutureProvider.family<List<RiskEstimateModel>, String>((ref, city) {
      final repository = ref.watch(riskRepositoryProvider);
      return repository.getRiskHistory(city, weeks: kTrendWindowWeeks);
    });

/// Risk trend (Rising / Stable / Falling / Insufficient) for the current user's
/// city, as `AsyncValue<TrendDirection>`.
///
/// Derives the city from [userCityProvider], pulls the trailing history, and
/// applies the deterministic [computeTrend]. Returns
/// [TrendDirection.insufficient] when there is no city or too little history —
/// never a misleading arrow.
final riskTrendProvider = FutureProvider<TrendDirection>((ref) async {
  final city = await ref.watch(userCityProvider.future);
  if (city == null) return TrendDirection.insufficient;

  final history = await ref.watch(riskHistoryProvider(city).future);
  return computeTrend(history);
});

/// Trailing risk history for the **current user's** city (newest first), as
/// `AsyncValue<List<RiskEstimate>>` — backs the Risk Details trend chart.
///
/// The single new provider for the Risk Details screen (per the plan): it only
/// composes existing pieces — derives the city from [userCityProvider] and
/// delegates to the existing [riskHistoryProvider] family (which reads the same
/// `riskEstimates` collection via [RiskRepository.getRiskHistory]). No new
/// repository, query, or business logic. Returns an empty list when there is no
/// user/city so the chart can show its empty state rather than error.
final currentCityRiskHistoryProvider = FutureProvider<List<RiskEstimateModel>>((
  ref,
) async {
  final city = await ref.watch(userCityProvider.future);
  if (city == null) return const [];
  return ref.watch(riskHistoryProvider(city).future);
});

/// Latest risk estimate for every supported city, as
/// `AsyncValue<List<RiskEstimate>>` — backs the national risk map (Prompt 4).
///
/// Additive, read-only (ADR-001). Cities without an estimate are omitted, so
/// the map renders only the cities that currently have data.
final allCitiesRiskProvider = FutureProvider<List<RiskEstimateModel>>((ref) {
  return ref
      .watch(riskRepositoryProvider)
      .getLatestRiskAllCities(kSupportedCities);
});
