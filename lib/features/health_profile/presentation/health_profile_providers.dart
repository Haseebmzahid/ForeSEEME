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
  if (user == null) return false;

  final repository = ref.read(healthProfileRepositoryProvider);
  final result = await repository.getProfile(user.uid);

  return result.fold((error) => false, (profile) => profile != null);
});
