import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fyp_foreseeme/features/health_profile/data/repositories/firestore_health_profile_repository.dart';
import 'package:fyp_foreseeme/features/health_profile/domain/models/health_profile_model.dart';
import 'package:fyp_foreseeme/features/health_profile/domain/repositories/health_profile_repository.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_notifier.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_state.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import '../data/repositories/firestore_disclaimer_repository.dart';
import '../domain/repositories/disclaimer_repository.dart';
import '../domain/constants/cities_constants.dart';

final disclaimerRepositoryProvider = Provider<DisclaimerRepository>((ref) {
  return FirestoreDisclaimerRepository();
});

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
  if (user == null || !user.emailVerified) {
    return false;
  }

  final repository = ref.read(healthProfileRepositoryProvider);
  final result = await repository.getProfile(user.uid);

  return result.fold(
    (error) {
      debugPrint(
        'profileExistsProvider: Error fetching profile (code: ${error.code})',
      );
      return false;
    },
    (profile) => kSupportedCities.contains(profile?.city),
  );
});

/// The signed-in user's full health profile, or `null`.
///
/// Resolves to `null` when there is no authenticated user or no profile on
/// file yet (an honest empty state). Deliberately **does not** collapse a
/// read failure to `null` the way [userCityProvider] does: this provider
/// backs the edit-mode form's prefill (S6C-01), where silently opening blank
/// on a transient error risks the user re-saving with their real conditions
/// wiped out. A read failure surfaces as `AsyncError` so the screen can show
/// a retry instead of a deceptively-empty form.
final currentHealthProfileProvider = FutureProvider<HealthProfileModel?>((
  ref,
) async {
  final user = await ref.watch(authStateProvider.future);
  if (user == null || !user.emailVerified) return null;

  final result = await ref
      .read(healthProfileRepositoryProvider)
      .getProfile(user.uid);

  return result.fold((error) => throw error, (profile) => profile);
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
  if (user == null || !user.emailVerified) return null;

  final result = await ref
      .read(healthProfileRepositoryProvider)
      .getProfile(user.uid);

  return result.fold((_) => null, (profile) {
    final city = profile?.city;
    return (city == null || city.isEmpty) ? null : city;
  });
});
