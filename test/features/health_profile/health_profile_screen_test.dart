import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/core/utils/either.dart';
import 'package:fyp_foreseeme/core/widgets/error_state.dart';
import 'package:fyp_foreseeme/features/auth/domain/models/user_model.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/health_profile/domain/exceptions/health_profile_exception.dart';
import 'package:fyp_foreseeme/features/health_profile/domain/models/health_profile_model.dart';
import 'package:fyp_foreseeme/features/health_profile/domain/repositories/health_profile_repository.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_screen.dart';

/// Configurable test double — only [getProfile] is exercised by this screen's
/// prefill path; the write methods aren't called by any test here.
class _FakeHealthProfileRepository implements HealthProfileRepository {
  _FakeHealthProfileRepository(this._result, {this.delay});
  final Either<HealthProfileException, HealthProfileModel?> _result;
  final Duration? delay;

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
  ) => throw UnimplementedError();

  @override
  Future<Either<HealthProfileException, void>> updateProfile(
    String uid, {
    String? city,
    List<String>? conditions,
  }) => throw UnimplementedError();
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
}
