import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fyp_foreseeme/core/utils/either.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/health_profile/domain/models/health_profile_model.dart';
import 'package:fyp_foreseeme/features/health_profile/domain/repositories/health_profile_repository.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_state.dart';

/// Manages all write operations (save / update) for a user's health profile.
///
/// State begins as [HealthProfileStateIdle] and transitions through
/// [HealthProfileStateLoading] → [HealthProfileStateSaved] or
/// [HealthProfileStateError] per operation.
class HealthProfileNotifier extends Notifier<HealthProfileState> {
  late final HealthProfileRepository _repository;

  @override
  HealthProfileState build() {
    _repository = ref.watch(healthProfileRepositoryProvider);
    return const HealthProfileStateIdle();
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Persist a brand-new profile (used on first-run setup after registration).
  Future<void> saveProfile({
    required String uid,
    required String city,
    required List<String> conditions,
    List<String> customConditions = const [],
  }) async {
    if (state is HealthProfileStateLoading) return;
    state = const HealthProfileStateLoading();

    final profile = HealthProfileModel(
      uid: uid,
      city: city,
      chronicConditions: conditions,
      customConditions: customConditions,
      lastUpdated: DateTime.now(), // Overwritten server-side by FieldValue
    );

    final result = await _repository.saveProfile(profile);

    if (result is Right) _refreshProfileData();
    state = result.fold(
      (error) => HealthProfileStateError(error.message),
      (_) => const HealthProfileStateSaved(),
    );

    // Best-effort admin-directory update (Sprint M8.4, SDS FR8.5): first-run
    // profile completion is this app's real, honest "onboarded" signal.
    // Never let a failure here surface as a profile-save failure — the save
    // above already succeeded or failed on its own. Deliberately not called
    // from `updateProfile` (the edit-mode path): a user editing an existing
    // profile is by definition already active.
    if (result is Right) {
      try {
        await ref.read(userDirectoryRepositoryProvider).markProfileActive(uid);
      } catch (_) {
        // Non-fatal by design — see doc comment above.
      }
    }
  }

  /// Update an existing profile with the given fields (used in edit mode).
  Future<void> updateProfile({
    required String uid,
    required String city,
    required List<String> conditions,
    List<String>? customConditions,
  }) async {
    if (state is HealthProfileStateLoading) return;
    state = const HealthProfileStateLoading();

    final result = await _repository.updateProfile(
      uid,
      city: city,
      conditions: conditions,
      customConditions: customConditions,
    );

    if (result is Right) _refreshProfileData();
    state = result.fold(
      (error) => HealthProfileStateError(error.message),
      (_) => const HealthProfileStateSaved(),
    );
  }

  void _refreshProfileData() {
    ref.invalidate(currentHealthProfileProvider);
    ref.invalidate(userCityProvider);
  }

  /// Reset to idle — call this after handling an error or after navigation.
  void reset() => state = const HealthProfileStateIdle();
}
