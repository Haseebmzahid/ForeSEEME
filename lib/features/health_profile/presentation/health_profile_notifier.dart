import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  }) async {
    if (state is HealthProfileStateLoading) return;
    state = const HealthProfileStateLoading();

    final profile = HealthProfileModel(
      uid: uid,
      city: city,
      chronicConditions: conditions,
      lastUpdated: DateTime.now(), // Overwritten server-side by FieldValue
    );

    final result = await _repository.saveProfile(profile);

    state = result.fold(
      (error) => HealthProfileStateError(error.message),
      (_) => const HealthProfileStateSaved(),
    );
  }

  /// Update an existing profile with the given fields (used in edit mode).
  Future<void> updateProfile({
    required String uid,
    required String city,
    required List<String> conditions,
  }) async {
    if (state is HealthProfileStateLoading) return;
    state = const HealthProfileStateLoading();

    final result = await _repository.updateProfile(
      uid,
      city: city,
      conditions: conditions,
    );

    state = result.fold(
      (error) => HealthProfileStateError(error.message),
      (_) => const HealthProfileStateSaved(),
    );
  }

  /// Reset to idle — call this after handling an error or after navigation.
  void reset() => state = const HealthProfileStateIdle();
}
