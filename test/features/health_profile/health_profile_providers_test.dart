import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyp_foreseeme/core/utils/either.dart';
import 'package:fyp_foreseeme/features/auth/domain/models/user_model.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/health_profile/domain/exceptions/health_profile_exception.dart';
import 'package:fyp_foreseeme/features/health_profile/domain/models/health_profile_model.dart';
import 'package:fyp_foreseeme/features/health_profile/domain/repositories/health_profile_repository.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';

/// Configurable test double for [HealthProfileRepository]. Only [getProfile] is
/// exercised by [userCityProvider]; the write methods are never called.
class _FakeHealthProfileRepository implements HealthProfileRepository {
  _FakeHealthProfileRepository(this._result);

  final Either<HealthProfileException, HealthProfileModel?> _result;

  @override
  Future<Either<HealthProfileException, HealthProfileModel?>> getProfile(
    String uid,
  ) async => _result;

  @override
  Future<Either<HealthProfileException, void>> saveProfile(
    HealthProfileModel profile,
  ) => throw UnimplementedError();

  @override
  Future<Either<HealthProfileException, void>> updateProfile(
    String uid, {
    String? city,
    List<String>? conditions,
    List<String>? customConditions,
  }) => throw UnimplementedError();
}

UserModel _user() => UserModel(
  uid: 'u1',
  email: 'patient@example.com',
  emailVerified: true,
  createdAt: DateTime.utc(2026, 1, 1),
);

HealthProfileModel _profile({required String city}) => HealthProfileModel(
  uid: 'u1',
  city: city,
  chronicConditions: const [],
  lastUpdated: DateTime.utc(2026, 6, 1),
);

ProviderContainer _containerWith({
  required UserModel? user,
  Either<HealthProfileException, HealthProfileModel?>? profileResult,
}) {
  // A controller that emits the user and stays open until teardown. A closed
  // `Stream.value` would leave the StreamProvider's `.future` mid-loading at
  // dispose; keeping the stream open delivers the value deterministically.
  final authController = StreamController<UserModel?>();
  authController.add(user);
  addTearDown(authController.close);

  final container = ProviderContainer(
    overrides: [
      authStateProvider.overrideWith((ref) => authController.stream),
      healthProfileRepositoryProvider.overrideWithValue(
        _FakeHealthProfileRepository(profileResult ?? const Right(null)),
      ),
    ],
  );
  addTearDown(container.dispose);
  // Listening drives the full async lifecycle (the stream subscription that
  // feeds `authStateProvider.future`); a bare `read(.future)` can otherwise sit
  // in loading forever in a container test.
  container.listen(authStateProvider, (_, _) {}, fireImmediately: true);
  container.listen(userCityProvider, (_, _) {}, fireImmediately: true);
  return container;
}

void main() {
  group('userCityProvider', () {
    test('returns the city when the profile has one', () async {
      final container = _containerWith(
        user: _user(),
        profileResult: Right(_profile(city: 'Lahore')),
      );

      expect(await container.read(userCityProvider.future), 'Lahore');
    });

    test('returns null when the profile city is empty', () async {
      final container = _containerWith(
        user: _user(),
        profileResult: Right(_profile(city: '')),
      );

      expect(await container.read(userCityProvider.future), isNull);
    });

    test('returns null when the user has no profile yet', () async {
      final container = _containerWith(
        user: _user(),
        profileResult: const Right(null),
      );

      expect(await container.read(userCityProvider.future), isNull);
    });

    test('collapses a profile-read error to null (empty, not error)', () async {
      final container = _containerWith(
        user: _user(),
        profileResult: const Left(
          HealthProfileException('boom', 'unavailable'),
        ),
      );

      expect(await container.read(userCityProvider.future), isNull);
    });

    test('returns null when there is no authenticated user', () async {
      final container = _containerWith(user: null);

      expect(await container.read(userCityProvider.future), isNull);
    });
  });
}
