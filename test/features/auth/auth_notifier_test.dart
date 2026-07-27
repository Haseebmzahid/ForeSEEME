import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/core/utils/either.dart';
import 'package:fyp_foreseeme/features/auth/domain/exceptions/auth_exception.dart';
import 'package:fyp_foreseeme/features/auth/domain/models/user_directory_entry.dart';
import 'package:fyp_foreseeme/features/auth/domain/models/user_model.dart';
import 'package:fyp_foreseeme/features/auth/domain/repositories/auth_repository.dart';
import 'package:fyp_foreseeme/features/auth/domain/repositories/user_directory_repository.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_state.dart';

class _FakeAuthRepo implements AuthRepository {
  final Either<AuthException, UserModel> signUpResult;
  _FakeAuthRepo(this.signUpResult);

  @override
  Stream<UserModel?> get currentUser => const Stream.empty();

  @override
  Future<Either<AuthException, UserModel>> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async => signUpResult;

  @override
  Future<Either<AuthException, UserModel>> signInWithEmail({
    required String email,
    required String password,
  }) async => throw UnimplementedError();

  @override
  Future<Either<AuthException, UserModel>> signInWithGoogle() async =>
      throw UnimplementedError();

  @override
  Future<Either<AuthException, void>> signOut() async =>
      throw UnimplementedError();

  @override
  Future<Either<AuthException, void>> sendPasswordReset(String email) async =>
      throw UnimplementedError();
}

class _FakeDirectoryRepo implements UserDirectoryRepository {
  final List<String> registeredUids = [];
  final bool throwOnRegister;
  _FakeDirectoryRepo({this.throwOnRegister = false});

  @override
  Future<void> register({
    required String uid,
    required String email,
    String? name,
  }) async {
    if (throwOnRegister) throw Exception('directory unavailable');
    registeredUids.add(uid);
  }

  @override
  Future<void> markProfileActive(String uid) async {}

  @override
  Future<List<UserDirectoryEntry>> list({int limit = 200}) async => [];
}

UserModel _user() => UserModel(
  uid: 'u1',
  email: 'new@example.com',
  displayName: 'New User',
  createdAt: DateTime.utc(2026, 1, 1),
);

void main() {
  group('AuthNotifier.signUp — user-directory registration (Sprint M8.4)', () {
    test('a successful sign-up registers the new account in the directory', () async {
      final directory = _FakeDirectoryRepo();
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            _FakeAuthRepo(Right(_user())),
          ),
          userDirectoryRepositoryProvider.overrideWithValue(directory),
        ],
      );
      addTearDown(container.dispose);

      await container.read(authNotifierProvider.notifier).signUp(
            email: 'new@example.com',
            password: 'password123',
            displayName: 'New User',
          );

      expect(container.read(authNotifierProvider), isA<AuthStateAuthenticated>());
      expect(directory.registeredUids, ['u1']);
    });

    test('a directory-registration failure never turns a successful sign-up into an error', () async {
      final directory = _FakeDirectoryRepo(throwOnRegister: true);
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            _FakeAuthRepo(Right(_user())),
          ),
          userDirectoryRepositoryProvider.overrideWithValue(directory),
        ],
      );
      addTearDown(container.dispose);

      await container.read(authNotifierProvider.notifier).signUp(
            email: 'new@example.com',
            password: 'password123',
            displayName: 'New User',
          );

      expect(container.read(authNotifierProvider), isA<AuthStateAuthenticated>());
    });

    test('a failed sign-up never attempts to register a directory entry', () async {
      final directory = _FakeDirectoryRepo();
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            _FakeAuthRepo(const Left(AuthException('email already in use'))),
          ),
          userDirectoryRepositoryProvider.overrideWithValue(directory),
        ],
      );
      addTearDown(container.dispose);

      await container.read(authNotifierProvider.notifier).signUp(
            email: 'new@example.com',
            password: 'password123',
            displayName: 'New User',
          );

      expect(container.read(authNotifierProvider), isA<AuthStateError>());
      expect(directory.registeredUids, isEmpty);
    });
  });
}
