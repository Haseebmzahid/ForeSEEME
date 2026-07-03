import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fyp_foreseeme/features/admin/data/repositories/firebase_admin_repository.dart';
import 'package:fyp_foreseeme/features/admin/domain/repositories/admin_repository.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_override.dart';
import 'package:fyp_foreseeme/features/risk/domain/repositories/risk_override_repository.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_override_provider.dart';

/// Provides the concrete [AdminRepository] (overridable in tests/dev).
final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return FirebaseAdminRepository();
});

/// Whether the current user is an admin, as `AsyncValue<bool>`. Re-evaluates when
/// the auth state changes (sign-in/out). Defaults to non-admin on any error, so
/// the admin surface fails closed.
final isAdminProvider = FutureProvider<bool>((ref) async {
  // Depend on auth so the claim is re-read after a sign-in/out.
  ref.watch(authStateProvider);
  try {
    return await ref.watch(adminRepositoryProvider).isCurrentUserAdmin();
  } catch (_) {
    return false;
  }
});

/// Write controller for the admin override surface. Thin: it validates nothing
/// beyond delegating to the repository; the repository's Firestore rules enforce
/// the admin claim, and the screen enforces required fields.
class AdminOverrideController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  RiskOverrideRepository get _repo =>
      ref.read(riskOverrideRepositoryProvider);

  /// Write (or supersede) the override for [city]. Author fields are taken from
  /// the signed-in user so the audit trail is genuine, never client-supplied.
  Future<void> submit({
    required String city,
    required RiskLevel riskLevel,
    required String disease,
    required String reason,
    DateTime? expiresAt,
    DateTime? now,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final user = ref.read(authStateProvider).value;
      if (user == null) {
        throw StateError('Must be signed in to write an override.');
      }
      final override = RiskOverride(
        city: city,
        riskLevel: riskLevel,
        disease: disease,
        reason: reason.trim(),
        authorUid: user.uid,
        authorEmail: user.email,
        createdAt: (now ?? DateTime.now()).toUtc(),
        active: true,
        expiresAt: expiresAt?.toUtc(),
      );
      await _repo.setOverride(override);
      _invalidate(city);
    });
  }

  /// Clear the active override for [city].
  Future<void> clear(String city) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _repo.clearOverride(city);
      _invalidate(city);
    });
  }

  void _invalidate(String city) {
    ref.invalidate(activeOverrideForCityProvider(city));
    ref.invalidate(currentCityOverrideProvider);
  }
}

final adminOverrideControllerProvider =
    AsyncNotifierProvider<AdminOverrideController, void>(
      AdminOverrideController.new,
    );
