import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/core/utils/either.dart';
import 'package:fyp_foreseeme/features/auth/domain/exceptions/auth_exception.dart';
import 'package:fyp_foreseeme/features/auth/domain/models/user_model.dart';
import 'package:fyp_foreseeme/features/auth/domain/repositories/auth_repository.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/auth/presentation/password_reset_controller.dart';

/// Fake repository that records the reset email and returns a scripted result.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository(this._result);

  final Either<AuthException, void> _result;
  final List<String> resetCalls = [];

  @override
  Future<Either<AuthException, void>> sendPasswordReset(String email) async {
    resetCalls.add(email);
    return _result;
  }

  // ── Unused by these tests ──────────────────────────────────────────────────
  @override
  Future<Either<AuthException, void>> sendEmailVerification(
    String uid,
  ) async => const Right(null);

  @override
  Future<Either<AuthException, bool>> refreshEmailVerification(
    String uid,
  ) async => const Right(false);

  @override
  Stream<UserModel?> get currentUser => const Stream.empty();
  @override
  Future<Either<AuthException, UserModel>> signInWithEmail({
    required String email,
    required String password,
  }) => throw UnimplementedError();
  @override
  Future<Either<AuthException, UserModel>> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) => throw UnimplementedError();
  @override
  Future<Either<AuthException, UserModel>> signInWithGoogle() =>
      throw UnimplementedError();
  @override
  Future<Either<AuthException, void>> signOut() => throw UnimplementedError();
}

ProviderContainer _containerReturning(Either<AuthException, void> result) {
  final repo = FakeAuthRepository(result);
  final container = ProviderContainer(
    overrides: [authRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return container;
}

Future<PasswordResetState> _send(
  ProviderContainer container,
  String email,
) async {
  await container
      .read(passwordResetControllerProvider.notifier)
      .sendResetEmail(email);
  return container.read(passwordResetControllerProvider);
}

void main() {
  group('PasswordResetController — happy path', () {
    test('a successful send resolves to PasswordResetSent', () async {
      final container = _containerReturning(const Right(null));
      expect(
        await _send(container, 'user@example.com'),
        isA<PasswordResetSent>(),
      );
    });

    test(
      'the email is trimmed before being passed to the repository',
      () async {
        final repo = FakeAuthRepository(const Right(null));
        final container = ProviderContainer(
          overrides: [authRepositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);

        await container
            .read(passwordResetControllerProvider.notifier)
            .sendResetEmail('  user@example.com  ');

        expect(repo.resetCalls.single, 'user@example.com');
      },
    );

    test('starts idle', () {
      final container = _containerReturning(const Right(null));
      expect(
        container.read(passwordResetControllerProvider),
        isA<PasswordResetIdle>(),
      );
    });
  });

  group('PasswordResetController — enumeration safety (no account leak)', () {
    test(
      'user-not-found is reported as success (neutral), never revealed',
      () async {
        final container = _containerReturning(
          const Left(AuthException('no user', 'user-not-found')),
        );
        expect(
          await _send(container, 'ghost@example.com'),
          isA<PasswordResetSent>(),
        );
      },
    );

    test('user-disabled is also masked as success', () async {
      final container = _containerReturning(
        const Left(AuthException('disabled', 'user-disabled')),
      );
      expect(await _send(container, 'x@example.com'), isA<PasswordResetSent>());
    });

    test('the neutral message never mentions the account', () {
      final m = kPasswordResetNeutralMessage.toLowerCase();
      expect(m, contains('if an account exists'));
      expect(m, isNot(contains('not found')));
      expect(m, isNot(contains('no account')));
      expect(m, isNot(contains("doesn't exist")));
    });
  });

  group('PasswordResetController — surfaced failures', () {
    Future<String> messageFor(String code) async {
      final container = _containerReturning(Left(AuthException('e', code)));
      final state = await _send(container, 'user@example.com');
      return (state as PasswordResetFailure).message;
    }

    test('invalid-email → format message', () async {
      expect(await messageFor('invalid-email'), contains('valid email'));
    });

    test('network-request-failed → network message', () async {
      expect(
        (await messageFor('network-request-failed')).toLowerCase(),
        contains('network'),
      );
    });

    test('too-many-requests → rate-limit message', () async {
      expect(
        (await messageFor('too-many-requests')).toLowerCase(),
        contains('too many'),
      );
    });

    test(
      'operation-not-allowed → generic config message (not revealing)',
      () async {
        final msg = await messageFor('operation-not-allowed');
        expect(msg.toLowerCase(), contains("couldn't process"));
      },
    );

    test('an unknown/unexpected code → safe generic message', () async {
      expect(
        await messageFor('some-weird-code'),
        'Something went wrong. Please try again.',
      );
    });

    test(
      'a non-Firebase exception (null code) → safe generic message',
      () async {
        final container = _containerReturning(
          const Left(AuthException('boom')), // no code
        );
        final state = await _send(container, 'user@example.com');
        expect(
          (state as PasswordResetFailure).message,
          'Something went wrong. Please try again.',
        );
      },
    );
  });

  group('PasswordResetController — lifecycle', () {
    test('goes through Sending while awaiting, then resolves', () async {
      final container = _containerReturning(const Right(null));
      final states = <PasswordResetState>[];
      container.listen(
        passwordResetControllerProvider,
        (_, next) => states.add(next),
        fireImmediately: false,
      );

      await container
          .read(passwordResetControllerProvider.notifier)
          .sendResetEmail('user@example.com');

      expect(states.first, isA<PasswordResetSending>());
      expect(states.last, isA<PasswordResetSent>());
    });

    test('reset() returns to idle', () async {
      final container = _containerReturning(const Right(null));
      await _send(container, 'user@example.com');
      container.read(passwordResetControllerProvider.notifier).reset();
      expect(
        container.read(passwordResetControllerProvider),
        isA<PasswordResetIdle>(),
      );
    });
  });
}
