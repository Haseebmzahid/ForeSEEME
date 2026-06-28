import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/risk/data/repositories/firestore_risk_repository.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/domain/repositories/risk_repository.dart';

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
/// Derives the city from the signed-in user's health profile, then delegates to
/// [latestRiskForCityProvider]. Returns `null` when there is no user, no
/// profile, or no city on file.
final currentCityRiskProvider = FutureProvider<RiskEstimateModel?>((ref) async {
  final user = await ref.watch(authStateProvider.future);
  if (user == null) return null;

  final profileResult = await ref
      .read(healthProfileRepositoryProvider)
      .getProfile(user.uid);
  final city = profileResult.fold((_) => null, (profile) => profile?.city);
  if (city == null || city.isEmpty) return null;

  return ref.watch(latestRiskForCityProvider(city).future);
});
