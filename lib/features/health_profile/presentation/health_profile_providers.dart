import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fyp_foreseeme/features/health_profile/data/repositories/firestore_health_profile_repository.dart';
import 'package:fyp_foreseeme/features/health_profile/domain/repositories/health_profile_repository.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_notifier.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_state.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';

/// Provides the concrete [HealthProfileRepository] implementation.
final healthProfileRepositoryProvider = Provider<HealthProfileRepository>((
  ref,
) {
  return FirestoreHealthProfileRepository();
});

/// Provides the [HealthProfileNotifier] with its [HealthProfileState].
final healthProfileNotifierProvider =
    NotifierProvider<HealthProfileNotifier, HealthProfileState>(() {
      return HealthProfileNotifier();
    });

/// Exposes the current user's profile existence status.
final profileExistsProvider = FutureProvider<bool>((ref) async {
  final user = await ref.watch(authStateProvider.future);
  if (user == null) {
    debugPrint('profileExistsProvider: User is null, returning false');
    return false;
  }

  debugPrint(
    'profileExistsProvider: Checking profile for authenticated uid: ${user.uid}',
  );
  final repository = ref.read(healthProfileRepositoryProvider);
  final result = await repository.getProfile(user.uid);

  return result.fold(
    (error) {
      debugPrint(
        'profileExistsProvider: Error fetching profile: ${error.message} (code: ${error.code})',
      );
      return false;
    },
    (profile) {
      debugPrint('profileExistsProvider: Profile exists: ${profile != null}');
      return profile != null;
    },
  );
});

/// The signed-in user's city from their health profile, or `null`.
///
/// Resolves to `null` when there is no authenticated user, no profile yet, no
/// city on file, or the profile read fails. A missing city is an *empty* state,
/// not an error: profile-read failures collapse to `null` (mirroring
/// [profileExistsProvider]) so dependents render "no city / nothing to show yet"
/// instead of an error screen.
///
/// Reactive: rebuilds when auth changes or the profile is re-fetched, so risk
/// consumers (dashboard card, trend, map) follow a city change automatically.
final userCityProvider = FutureProvider<String?>((ref) async {
  final user = await ref.watch(authStateProvider.future);
  if (user == null) return null;

  final result = await ref
      .read(healthProfileRepositoryProvider)
      .getProfile(user.uid);

  return result.fold((_) => null, (profile) {
    final city = profile?.city;
    return (city == null || city.isEmpty) ? null : city;
  });
});
