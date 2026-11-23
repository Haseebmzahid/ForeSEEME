import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/risk/data/repositories/firestore_risk_override_repository.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_override.dart';
import 'package:fyp_foreseeme/features/risk/domain/repositories/risk_override_repository.dart';

/// Provides the concrete [RiskOverrideRepository] (overridable with a fake in
/// tests/dev). Mirrors [riskRepositoryProvider]; imports no `firebase_*` — the
/// SDK stays inside [FirestoreRiskOverrideRepository] (GOLDEN_RULES rule 3).
final riskOverrideRepositoryProvider = Provider<RiskOverrideRepository>((ref) {
  return FirestoreRiskOverrideRepository();
});

/// The **active** operator override for an explicit [city], or `null` when none
/// is in force. Read-only; applies [RiskOverride.isActive] (honouring expiry) so
/// a cleared/expired override never leaks onto a risk surface.
final activeOverrideForCityProvider = FutureProvider.autoDispose
    .family<RiskOverride?, String>((ref, city) async {
      final override = await ref
          .watch(riskOverrideRepositoryProvider)
          .getOverride(city)
          .timeout(const Duration(seconds: 12));
      if (!ref.mounted || override == null || !override.isActive()) return null;
      if (override.expiresAt case final expiration?) {
        final timer = Timer(
          expiration.difference(DateTime.now()),
          ref.invalidateSelf,
        );
        ref.onDispose(timer.cancel);
      }
      return override;
    }, retry: (_, _) => null);

/// The active override for the **current user's** city, or `null`.
///
/// Derives the city from [userCityProvider] then delegates to
/// [activeOverrideForCityProvider]. This is what the dashboard card + Risk
/// Details bind to alongside [currentCityRiskProvider] to overlay the operator
/// value with a clear label.
///
/// **Best-effort by design:** the override is an additive enhancement over the
/// genuine estimate, so any failure to resolve the city or read the override
/// degrades to `null` (no override) rather than surfacing an error onto the risk
/// display — the honest model estimate must always win through.
final currentCityOverrideProvider = FutureProvider.autoDispose<RiskOverride?>((
  ref,
) async {
  try {
    final city = await ref.watch(userCityProvider.future);
    if (city == null) return null;
    return await ref.watch(activeOverrideForCityProvider(city).future);
  } catch (_) {
    return null;
  }
});
