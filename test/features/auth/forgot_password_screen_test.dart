import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/utils/either.dart';
import 'package:fyp_foreseeme/features/auth/domain/exceptions/auth_exception.dart';
import 'package:fyp_foreseeme/features/auth/domain/models/user_model.dart';
import 'package:fyp_foreseeme/features/auth/domain/repositories/auth_repository.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/auth/presentation/forgot_password_screen.dart';

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository(this._result, {this.delay = Duration.zero});
  final Either<AuthException, void> _result;
  final Duration delay;
  final List<String> resetCalls = [];

  @override
  Future<Either<AuthException, void>> sendPasswordReset(String email) async {
    resetCalls.add(email);
    if (delay != Duration.zero) await Future.delayed(delay);
    return _result;
  }

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

Future<FakeAuthRepository> _pump(
  WidgetTester tester,
  Either<AuthException, void> result, {
  Duration delay = Duration.zero,
}) async {
  // A tall surface so no glass section is clipped out of the hit-test region.
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final repo = FakeAuthRepository(result, delay: delay);
  final router = GoRouter(
    initialLocation: '/login',
    routes: [
      GoRoute(
        path: '/login',
        builder: (_, _) => const Scaffold(body: Text('LOGIN SCREEN')),
      ),
      GoRoute(path: '/forgot', builder: (_, _) => const ForgotPasswordScreen()),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(repo)],
      // NoSplash avoids the ink_sparkle shader the test binding can't decode.
      child: MaterialApp.router(
        routerConfig: router,
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
      ),
    ),
  );
  router.push('/forgot');
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  group(
    'ForgotPasswordScreen — really calls Firebase (root-cause safeguard)',
    () {
      testWidgets('submitting a valid email invokes the repository', (
        tester,
      ) async {
        final repo = await _pump(tester, const Right(null));

        await tester.enterText(find.byType(TextFormField), 'user@example.com');
        await tester.tap(find.text('Send reset link'));
        await tester.pumpAndSettle();

        expect(repo.resetCalls, ['user@example.com']);
      });

      testWidgets('a blank email is validated and never hits the repository', (
        tester,
      ) async {
        final repo = await _pump(tester, const Right(null));

        await tester.tap(find.text('Send reset link'));
        await tester.pumpAndSettle();

        expect(repo.resetCalls, isEmpty);
        expect(find.text('Email is required'), findsOneWidget);
      });
    },
  );

  group('ForgotPasswordScreen — states', () {
    testWidgets('loading: the CTA shows a spinner while sending', (
      tester,
    ) async {
      await _pump(
        tester,
        const Right(null),
        delay: const Duration(milliseconds: 400),
      );

      await tester.enterText(find.byType(TextFormField), 'user@example.com');
      await tester.tap(find.text('Send reset link'));
      await tester.pump(); // enter the Sending state
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle(); // let it complete
    });

    testWidgets('success: shows the neutral, enumeration-safe confirmation', (
      tester,
    ) async {
      await _pump(tester, const Right(null));

      await tester.enterText(find.byType(TextFormField), 'user@example.com');
      await tester.tap(find.text('Send reset link'));
      await tester.pumpAndSettle();

      expect(find.text('Check your inbox'), findsOneWidget);
      expect(find.textContaining('If an account exists'), findsOneWidget);
      expect(find.text('Back to Sign In'), findsOneWidget);
    });

    testWidgets('user-not-found is indistinguishable from success', (
      tester,
    ) async {
      await _pump(
        tester,
        const Left(AuthException('no user', 'user-not-found')),
      );

      await tester.enterText(find.byType(TextFormField), 'ghost@example.com');
      await tester.tap(find.text('Send reset link'));
      await tester.pumpAndSettle();

      // Same success surface — never reveals the account does not exist.
      expect(find.text('Check your inbox'), findsOneWidget);
      expect(find.textContaining('If an account exists'), findsOneWidget);
    });

    testWidgets('error: shows an inline message and stays on the form', (
      tester,
    ) async {
      await _pump(
        tester,
        const Left(AuthException('offline', 'network-request-failed')),
      );

      await tester.enterText(find.byType(TextFormField), 'user@example.com');
      await tester.tap(find.text('Send reset link'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Network error'), findsOneWidget);
      // Still on the form (CTA present), no success surface.
      expect(find.text('Send reset link'), findsOneWidget);
      expect(find.text('Check your inbox'), findsNothing);
    });
  });

  group('ForgotPasswordScreen — actions', () {
    testWidgets('resend re-invokes the repository from the success state', (
      tester,
    ) async {
      final repo = await _pump(tester, const Right(null));

      await tester.enterText(find.byType(TextFormField), 'user@example.com');
      await tester.tap(find.text('Send reset link'));
      await tester.pumpAndSettle();

      await tester.tap(find.text("Didn't get it? Resend email"));
      await tester.pumpAndSettle();

      expect(repo.resetCalls, ['user@example.com', 'user@example.com']);
    });

    testWidgets('back to sign in returns to the login route', (tester) async {
      await _pump(tester, const Right(null));

      await tester.enterText(find.byType(TextFormField), 'user@example.com');
      await tester.tap(find.text('Send reset link'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Back to Sign In'));
      await tester.pumpAndSettle();

      expect(find.text('LOGIN SCREEN'), findsOneWidget);
    });
  });
}
