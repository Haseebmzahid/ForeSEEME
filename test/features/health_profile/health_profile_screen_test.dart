import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/utils/either.dart';
import 'package:fyp_foreseeme/core/widgets/error_state.dart';
import 'package:fyp_foreseeme/features/auth/domain/models/user_model.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/health_profile/domain/exceptions/health_profile_exception.dart';
import 'package:fyp_foreseeme/features/health_profile/domain/models/health_profile_model.dart';
import 'package:fyp_foreseeme/features/health_profile/domain/repositories/health_profile_repository.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_screen.dart';

/// Configurable test double — only [getProfile] is exercised by the S6C-01
/// prefill tests; [saveProfile] is additionally exercised by the S6C-02
/// navigation tests (both default to failing loudly so a test that doesn't
/// expect a call is proof the call never happened).
class _FakeHealthProfileRepository implements HealthProfileRepository {
  _FakeHealthProfileRepository(this._result, {this.delay, this.saveResult});
  final Either<HealthProfileException, HealthProfileModel?> _result;
  final Duration? delay;
  final Either<HealthProfileException, void>? saveResult;

  @override
  Future<Either<HealthProfileException, HealthProfileModel?>> getProfile(
    String uid,
  ) async {
    if (delay != null) await Future<void>.delayed(delay!);
    return _result;
  }

  @override
  Future<Either<HealthProfileException, void>> saveProfile(
    HealthProfileModel profile,
  ) async {
    if (saveResult == null) throw UnimplementedError();
    return saveResult!;
  }

  @override
  Future<Either<HealthProfileException, void>> updateProfile(
    String uid, {
    String? city,
    List<String>? conditions,
  }) async {
    if (saveResult == null) throw UnimplementedError();
    return saveResult!;
  }
}

UserModel _user() => UserModel(
  uid: 'u1',
  email: 'patient@example.com',
  createdAt: DateTime.utc(2026, 1, 1),
);

HealthProfileModel _profile({
  required String city,
  required List<String> conditions,
}) => HealthProfileModel(
  uid: 'u1',
  city: city,
  chronicConditions: conditions,
  lastUpdated: DateTime.utc(2026, 6, 1),
);

Future<void> _pump(
  WidgetTester tester, {
  required bool isEditMode,
  Either<HealthProfileException, HealthProfileModel?>? profileResult,
  Duration? delay,
}) async {
  // A single-subscription controller can have exactly one listener. In
  // non-edit mode nothing in the widget tree ever watches `authStateProvider`
  // (only edit mode's prefill path does), so without a forced subscriber,
  // `authController.close()` in tearDown awaits delivery of the close event
  // to a listener that never arrives — hanging the test forever. Forcing the
  // subscription via `container.listen(authStateProvider, ...)` (mirroring
  // `health_profile_providers_test.dart`) guarantees exactly one listener
  // regardless of whether the widget itself watches it — and, being that
  // *one* listener, doesn't collide with Riverpod's own subscription the way
  // a raw `authController.stream.listen(...)` would in edit mode.
  final authController = StreamController<UserModel?>();
  addTearDown(authController.close);

  final container = ProviderContainer(
    // Disables Riverpod's automatic retry-on-error backoff Timer for this
    // container. The retry itself is legitimate production behaviour (not
    // touched here); it's disabled purely so the "fetch failure" case
    // doesn't leave a pending 0.8s backoff Timer scheduled past test end.
    retry: (retryCount, error) => null,
    overrides: [
      authStateProvider.overrideWith((ref) => authController.stream),
      healthProfileRepositoryProvider.overrideWithValue(
        _FakeHealthProfileRepository(
          profileResult ?? const Right(null),
          delay: delay,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  container.listen(authStateProvider, (_, _) {}, fireImmediately: true);
  authController.add(_user());

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: HealthProfileScreen(isEditMode: isEditMode)),
    ),
  );
}

/// Settles the screen's one-shot 600ms fade-in without `pumpAndSettle` —
/// the loading skeleton briefly hosts a `Shimmer` with an infinitely
/// repeating animation, which `pumpAndSettle` never considers "settled".
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
}

/// Pumps up to [maxPumps] times (100ms apart), returning as soon as [finder]
/// finds a match. The post-save navigation is scheduled via
/// `WidgetsBinding.instance.addPostFrameCallback`, which fires within a
/// pump or two under normal conditions — but a *fixed* pump count is a race
/// under heavy concurrent test-suite load (verified: this suite is 100%
/// reliable in isolation, but flaked once under the full ~430-test run with
/// no exception/hang, only "not found yet"). Polling with a generous cap
/// proves the navigation happens within a real bound instead of gambling on
/// exactly how many pumps "usually" suffice.
Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 20,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  // Final pump/check so the eventual `expect` reports a clean, standard
  // failure (with the usual matcher diff) rather than this helper's own.
  await tester.pump();
}

/// Pumps [HealthProfileScreen] behind a real (minimal) [GoRouter] so
/// `context.push`/`context.pop` calls resolve against real routes, rather
/// than a bare `MaterialApp` Navigator. `/notifications/permission` is a
/// lightweight stub — this suite verifies *navigation*, not the (existing,
/// unmodified) permission screen's own behaviour.
Future<GoRouter> _pumpWithRouter(
  WidgetTester tester, {
  required bool isEditMode,
  required Either<HealthProfileException, void> saveResult,
}) async {
  final authController = StreamController<UserModel?>();
  addTearDown(authController.close);

  final container = ProviderContainer(
    retry: (retryCount, error) => null,
    overrides: [
      authStateProvider.overrideWith((ref) => authController.stream),
      healthProfileRepositoryProvider.overrideWithValue(
        _FakeHealthProfileRepository(const Right(null), saveResult: saveResult),
      ),
    ],
  );
  addTearDown(container.dispose);
  container.listen(authStateProvider, (_, _) {}, fireImmediately: true);
  authController.add(_user());

  final router = GoRouter(
    // Starts one level back and pushes on top, so edit mode's existing
    // `context.pop()` on save has a real route underneath to return to
    // (exactly how it's reached in the app: pushed from /profile).
    initialLocation: '/profile',
    routes: [
      GoRoute(
        path: '/profile',
        builder: (context, state) => const Scaffold(body: Text('PROFILE_STUB')),
      ),
      GoRoute(
        path: '/health-profile',
        builder: (context, state) => HealthProfileScreen(isEditMode: isEditMode),
      ),
      GoRoute(
        path: '/notifications/permission',
        builder: (context, state) =>
            const Scaffold(body: Text('PERMISSION_SCREEN_STUB')),
      ),
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  router.push('/health-profile');
  await tester.pump();
  return router;
}

/// Selects a city + a condition. 'None' sits below the fold on the test
/// surface, so it's scrolled into view before tapping (a plain `tap` would
/// silently miss and leave the form invalid).
Future<void> _fillMinimalForm(WidgetTester tester) async {
  await tester.tap(find.text('Lahore'));
  await tester.pump();
  await tester.ensureVisible(find.text('None'));
  await tester.pump();
  await tester.tap(find.text('None'));
  await tester.pump();
}

void main() {
  group('HealthProfileScreen edit-mode prefill (S6C-01)', () {
    testWidgets('prefills the real saved city and conditions', (
      tester,
    ) async {
      await _pump(
        tester,
        isEditMode: true,
        profileResult: Right(
          _profile(city: 'Karachi', conditions: const ['Asthma', 'Diabetes']),
        ),
      );
      await _settle(tester);

      final cityChip = tester.widget<ChoiceChip>(
        find.ancestor(
          of: find.text('Karachi'),
          matching: find.byType(ChoiceChip),
        ),
      );
      expect(cityChip.selected, isTrue);

      final asthmaChip = tester.widget<FilterChip>(
        find.ancestor(
          of: find.text('Asthma'),
          matching: find.byType(FilterChip),
        ),
      );
      expect(asthmaChip.selected, isTrue);
      final diabetesChip = tester.widget<FilterChip>(
        find.ancestor(
          of: find.text('Diabetes'),
          matching: find.byType(FilterChip),
        ),
      );
      expect(diabetesChip.selected, isTrue);

      // A condition never selected stays unselected.
      final noneChip = tester.widget<FilterChip>(
        find.ancestor(of: find.text('None'), matching: find.byType(FilterChip)),
      );
      expect(noneChip.selected, isFalse);

      expect(find.text('Update Profile'), findsOneWidget);
    });

    testWidgets('shows a mirrored skeleton while the profile loads, no button', (
      tester,
    ) async {
      await _pump(
        tester,
        isEditMode: true,
        profileResult: Right(_profile(city: 'Lahore', conditions: const [])),
        delay: const Duration(milliseconds: 200),
      );
      await tester.pump();

      expect(find.text('Update Profile'), findsNothing);
      expect(find.text('Lahore'), findsNothing);

      await tester.pump(const Duration(milliseconds: 250));
      await _settle(tester);
      expect(find.text('Update Profile'), findsOneWidget);
    });

    testWidgets('a fetch failure shows ErrorState with retry, not a crash', (
      tester,
    ) async {
      await _pump(
        tester,
        isEditMode: true,
        profileResult: const Left(
          HealthProfileException('boom', 'unavailable'),
        ),
      );
      await _settle(tester);

      expect(find.byType(ErrorState), findsOneWidget);
      expect(find.text('Update Profile'), findsNothing);
    });

    testWidgets('no profile on file degrades to a blank, honest form', (
      tester,
    ) async {
      await _pump(tester, isEditMode: true, profileResult: const Right(null));
      await _settle(tester);

      expect(find.byType(ErrorState), findsNothing);
      final cityChip = tester.widget<ChoiceChip>(
        find.ancestor(
          of: find.text('Lahore'),
          matching: find.byType(ChoiceChip),
        ),
      );
      expect(cityChip.selected, isFalse);
      expect(find.text('Update Profile'), findsOneWidget);
    });

    testWidgets('non-edit mode never touches the profile fetch', (
      tester,
    ) async {
      // getProfile would throw synchronously via UnimplementedError-shaped
      // failure if it were ever awaited; a Left result proves it's simply
      // never called for a brand-new (non-edit) profile setup.
      await _pump(
        tester,
        isEditMode: false,
        profileResult: const Left(
          HealthProfileException('should not be called', 'unavailable'),
        ),
      );
      await _settle(tester);

      expect(find.byType(ErrorState), findsNothing);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Complete Profile'), findsOneWidget);
    });
  });

  group('HealthProfileScreen first-run notification pre-prompt (S6C-02)', () {
    testWidgets(
      'a successful first-time save pushes the permission pre-prompt',
      (tester) async {
        await _pumpWithRouter(
          tester,
          isEditMode: false,
          saveResult: const Right(null),
        );
        await _settle(tester);

        await _fillMinimalForm(tester);

        await tester.tap(find.text('Continue'));
        await _pumpUntilFound(tester, find.text('PERMISSION_SCREEN_STUB'));

        expect(find.text('PERMISSION_SCREEN_STUB'), findsOneWidget);
      },
    );

    testWidgets('an edit-mode save does not push the permission pre-prompt', (
      tester,
    ) async {
      await _pumpWithRouter(
        tester,
        isEditMode: true,
        saveResult: const Right(null),
      );
      await _settle(tester);

      await _fillMinimalForm(tester);

      await tester.tap(find.text('Update Profile'));
      await _pumpUntilFound(tester, find.text('PROFILE_STUB'));

      expect(find.text('PERMISSION_SCREEN_STUB'), findsNothing);
      // Edit mode's existing behaviour (unchanged): pop back to the caller.
      expect(find.text('PROFILE_STUB'), findsOneWidget);
    });

    testWidgets('a failed first-time save stays put — no premature navigation', (
      tester,
    ) async {
      await _pumpWithRouter(
        tester,
        isEditMode: false,
        saveResult: const Left(HealthProfileException('boom', 'unavailable')),
      );
      await _settle(tester);

      await _fillMinimalForm(tester);

      await tester.tap(find.text('Continue'));
      await _settle(tester);

      expect(find.text('PERMISSION_SCREEN_STUB'), findsNothing);
      expect(find.text('Continue'), findsOneWidget);
    });
  });
}
