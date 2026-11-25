import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/core/utils/either.dart';
import 'package:fyp_foreseeme/core/widgets/app_button.dart';
import 'package:fyp_foreseeme/features/auth/domain/exceptions/auth_exception.dart';
import 'package:fyp_foreseeme/features/auth/domain/models/user_directory_entry.dart';
import 'package:fyp_foreseeme/features/auth/domain/models/user_model.dart';
import 'package:fyp_foreseeme/features/auth/domain/repositories/auth_repository.dart';
import 'package:fyp_foreseeme/features/auth/domain/repositories/user_directory_repository.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_state.dart';
import 'package:fyp_foreseeme/features/auth/presentation/login_screen.dart';
import 'package:fyp_foreseeme/features/auth/presentation/register_screen.dart';

class _FakeAuthRepo implements AuthRepository {
  final Either<AuthException, UserModel> signUpResult;
  final Either<AuthException, void> verificationResult;
  final Completer<void>? signInGate;
  int verificationSends = 0;
  int signInCalls = 0;

  _FakeAuthRepo(this.signUpResult, {
    this.verificationResult = const Right(null),
    this.signInGate,
  });

  @override
  Future<Either<AuthException, void>> sendEmailVerification(
    String uid,
  ) async {
    verificationSends++;
    return verificationResult;
  }

  @override
  Future<Either<AuthException, bool>> refreshEmailVerification(
    String uid,
  ) async => const Right(false);

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
  }) async {
    signInCalls++;
    await signInGate?.future;
    return signUpResult;
  }

  @override
  Future<Either<AuthException, UserModel>> signInWithGoogle() async =>
      signUpResult;

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
  void useTallViewport(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  for (final (screen, count) in [(const LoginScreen(), 1), (const RegisterScreen(), 2)]) {
    testWidgets('${screen.runtimeType} masks passwords and supports the toggle', (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(_FakeAuthRepo(Right(_user())))],
        child: MaterialApp(home: screen),
      ));
      await tester.pumpAndSettle();
      final masked = find.byTooltip('Show password');
      expect(masked, findsNWidgets(count));
      await tester.ensureVisible(masked.first);
      await tester.tap(masked.first);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Hide password'), findsOneWidget);
      expect(tester.widgetList<EditableText>(find.byType(EditableText))
          .where((field) => field.obscureText), hasLength(count - 1));
    });
  }

  test('a failed initial send leaves signup pending with retry feedback', () async {
    final repository = _FakeAuthRepo(
      Right(_user()), verificationResult: const Left(AuthException('Send failed. Try again.')),
    );
    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(repository),
      userDirectoryRepositoryProvider.overrideWithValue(_FakeDirectoryRepo()),
    ]);
    addTearDown(container.dispose);
    await container.read(authNotifierProvider.notifier).signUp(
      email: _user().email, password: '12345678', displayName: 'Test User',
    );
    expect(repository.verificationSends, 1);
    expect(container.read(authNotifierProvider), isA<AuthStateVerificationPending>()
        .having((state) => state.message, 'message', contains('Send failed')));
  });

  testWidgets('registration shows criteria and blocks incomplete or invalid fields', (tester) async {
    useTallViewport(tester);
    final repository = _FakeAuthRepo(Right(_user()));
    await tester.pumpWidget(ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
      child: const MaterialApp(home: RegisterScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Use at least 8 characters.'), findsOneWidget);
    final fields = find.byType(EditableText);
    await tester.enterText(fields.at(1), 'invalid example@test');
    await tester.enterText(fields.at(2), '1234567');
    final submit = find.byWidgetPredicate(
      (widget) => widget is AppButton && widget.text == 'Create Account',
    );
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text('Name is required'), findsOneWidget);
    expect(find.text('Enter a valid email'), findsOneWidget);
    expect(find.text('Password must be at least 8 characters'), findsOneWidget);
    expect(repository.verificationSends, 0);
  });

  test('duplicate login calls are ignored and pending Firebase users stay pending', () async {
    final gate = Completer<void>();
    final user = _user();
    final repository = _FakeAuthRepo(Right(user), signInGate: gate);
    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(repository),
    ]);
    addTearDown(container.dispose);
    final notifier = container.read(authNotifierProvider.notifier);
    final first = notifier.signIn(email: user.email, password: '12345678');
    expect(container.read(authNotifierProvider), isA<AuthStateLoading>());
    await notifier.signIn(email: user.email, password: '12345678');
    expect(repository.signInCalls, 1);
    gate.complete();
    await first;
    expect(container.read(authNotifierProvider), isA<AuthStateVerificationPending>());
  });

  test('verified Google user activates through the same notifier', () async {
    final user = UserModel(
      uid: 'google-fixture', email: 'google@example.test',
      emailVerified: true, createdAt: DateTime.utc(2026),
    );
    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(_FakeAuthRepo(Right(user))),
    ]);
    addTearDown(container.dispose);
    await container.read(authNotifierProvider.notifier).signInWithGoogle();
    expect(container.read(authNotifierProvider), isA<AuthStateAuthenticated>());
  });

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

        expect(
          container.read(authNotifierProvider),
          isA<AuthStateVerificationPending>(),
        );
        expect(directory.registeredUids, ['u1']);
      },
    );

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

        expect(
          container.read(authNotifierProvider),
          isA<AuthStateVerificationPending>(),
        );
      },
    );

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
