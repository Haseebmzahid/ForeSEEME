import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/core/utils/either.dart';
import 'package:fyp_foreseeme/features/auth/domain/models/user_directory_entry.dart';
import 'package:fyp_foreseeme/features/auth/domain/repositories/user_directory_repository.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/health_profile/domain/exceptions/health_profile_exception.dart';
import 'package:fyp_foreseeme/features/health_profile/domain/models/health_profile_model.dart';
import 'package:fyp_foreseeme/features/health_profile/domain/repositories/health_profile_repository.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_state.dart';

class _FakeProfileRepo implements HealthProfileRepository {
  final bool saveSucceeds;
  _FakeProfileRepo({this.saveSucceeds = true});

  @override
  Future<Either<HealthProfileException, HealthProfileModel?>> getProfile(
    String uid,
  ) async => const Right(null);

  @override
  Future<Either<HealthProfileException, void>> saveProfile(
    HealthProfileModel profile,
  ) async => saveSucceeds
      ? const Right(null)
      : const Left(HealthProfileException('save failed'));

  @override
  Future<Either<HealthProfileException, void>> updateProfile(
    String uid, {
    String? city,
    List<String>? conditions,
  }) async => const Right(null);
}

class _FakeDirectoryRepo implements UserDirectoryRepository {
  final List<String> activatedUids = [];
  final bool throwOnMarkActive;
  _FakeDirectoryRepo({this.throwOnMarkActive = false});

  @override
  Future<void> register({
    required String uid,
    required String email,
    String? name,
  }) async {}

  @override
  Future<void> markProfileActive(String uid) async {
    if (throwOnMarkActive) throw Exception('directory unavailable');
    activatedUids.add(uid);
  }

  @override
  Future<List<UserDirectoryEntry>> list({int limit = 200}) async => [];
}

void main() {
  group(
    'HealthProfileNotifier.saveProfile — user-directory activation (Sprint M8.4)',
    () {
      test('a successful first-run save marks the user active in the directory', () async {
        final directory = _FakeDirectoryRepo();
        final container = ProviderContainer(
          overrides: [
            healthProfileRepositoryProvider.overrideWithValue(_FakeProfileRepo()),
            userDirectoryRepositoryProvider.overrideWithValue(directory),
          ],
        );
        addTearDown(container.dispose);

        await container.read(healthProfileNotifierProvider.notifier).saveProfile(
              uid: 'u1',
              city: 'Lahore',
              conditions: const ['Asthma'],
            );

        expect(
          container.read(healthProfileNotifierProvider),
          isA<HealthProfileStateSaved>(),
        );
        expect(directory.activatedUids, ['u1']);
      });

      test('a directory-activation failure never turns a successful save into an error', () async {
        final directory = _FakeDirectoryRepo(throwOnMarkActive: true);
        final container = ProviderContainer(
          overrides: [
            healthProfileRepositoryProvider.overrideWithValue(_FakeProfileRepo()),
            userDirectoryRepositoryProvider.overrideWithValue(directory),
          ],
        );
        addTearDown(container.dispose);

        await container.read(healthProfileNotifierProvider.notifier).saveProfile(
              uid: 'u1',
              city: 'Lahore',
              conditions: const ['Asthma'],
            );

        expect(
          container.read(healthProfileNotifierProvider),
          isA<HealthProfileStateSaved>(),
        );
      });

      test('a failed save never attempts to mark the user active', () async {
        final directory = _FakeDirectoryRepo();
        final container = ProviderContainer(
          overrides: [
            healthProfileRepositoryProvider.overrideWithValue(
              _FakeProfileRepo(saveSucceeds: false),
            ),
            userDirectoryRepositoryProvider.overrideWithValue(directory),
          ],
        );
        addTearDown(container.dispose);

        await container.read(healthProfileNotifierProvider.notifier).saveProfile(
              uid: 'u1',
              city: 'Lahore',
              conditions: const ['Asthma'],
            );

        expect(
          container.read(healthProfileNotifierProvider),
          isA<HealthProfileStateError>(),
        );
        expect(directory.activatedUids, isEmpty);
      });
    },
  );
}
