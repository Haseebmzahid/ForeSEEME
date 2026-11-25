@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/utils/either.dart';
import 'package:fyp_foreseeme/features/admin/presentation/admin_providers.dart';
import 'package:fyp_foreseeme/features/alerts/domain/models/notification_preferences.dart';
import 'package:fyp_foreseeme/features/alerts/domain/repositories/notification_preferences_repository.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/alerts_providers.dart';
import 'package:fyp_foreseeme/features/auth/domain/models/user_model.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/health_profile/domain/exceptions/health_profile_exception.dart';
import 'package:fyp_foreseeme/features/health_profile/domain/models/health_profile_model.dart';
import 'package:fyp_foreseeme/features/health_profile/domain/repositories/health_profile_repository.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/medication/domain/enums/medication_enums.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/medication_model.dart';
import 'package:fyp_foreseeme/features/medication/presentation/adherence_notifier.dart';
import 'package:fyp_foreseeme/features/profile/presentation/profile_screen.dart';

/// Renders the Profile Hub across the sizes, themes and text scales the design
/// review covers, so the layout can be compared against the approved prototype
/// (`docs/Design/ForeSeeMe Profile Hub (1).html`) rather than eyeballed.
///
/// Tagged `golden` and excluded from the default run (see `dart_test.yaml`), so
/// the ordinary suite stays free of image comparisons. Regenerate with:
///
/// ```
/// flutter test --tags golden --run-skipped --update-goldens
/// ```
///
/// Glyphs render as the test font's boxes — these goldens are about geometry,
/// colour, gradients, shadows and rhythm, not letterforms.

class _Repo implements HealthProfileRepository {
  @override
  Future<Either<HealthProfileException, HealthProfileModel?>> getProfile(
    String uid,
  ) async => Right<HealthProfileException, HealthProfileModel?>(
    HealthProfileModel(
      uid: 'u1',
      city: 'Lahore',
      chronicConditions: const ['asthma'],
      lastUpdated: DateTime.utc(2026, 1, 1),
    ),
  );

  @override
  Future<Either<HealthProfileException, void>> saveProfile(
    HealthProfileModel profile,
  ) async => throw UnimplementedError();

  @override
  Future<Either<HealthProfileException, void>> updateProfile(
    String uid, {
    String? city,
    List<String>? conditions,
    List<String>? customConditions,
  }) async => throw UnimplementedError();
}

class _Prefs implements NotificationPreferencesRepository {
  @override
  Future<NotificationPreferences> load(String uid) async =>
      NotificationPreferences.defaults();

  @override
  Future<void> save(String uid, NotificationPreferences preferences) async {}
}

Widget _host({required Brightness brightness, required double textScale}) =>
    ProviderScope(
      overrides: [
        authStateProvider.overrideWith(
          (ref) => Stream<UserModel?>.value(
            UserModel(
              uid: 'u1',
              email: 'amara@example.com',
              displayName: 'Amara Okafor',
              emailVerified: true,
              createdAt: DateTime.utc(2026, 1, 1),
            ),
          ),
        ),
        healthProfileRepositoryProvider.overrideWithValue(_Repo()),
        medicationsStreamProvider.overrideWith(
          (ref) => Stream.value([
            MedicationModel(
              id: 'm1',
              uid: 'u1',
              name: 'Ventolin',
              dosage: '2 puffs',
              type: MedicationType.pill,
              frequency: MedicationFrequency.onceDaily,
              reminderTimes: const ['08:00'],
              isActive: true,
              createdAt: DateTime.utc(2026, 1, 1),
            ),
          ]),
        ),
        isAdminProvider.overrideWith((ref) async => true),
        notificationPreferencesRepositoryProvider.overrideWithValue(_Prefs()),
      ],
      child: MaterialApp(
        theme: ForeSeeMeTheme.light,
        darkTheme: ForeSeeMeTheme.dark,
        themeMode: brightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
        home: const ProfileScreen(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            padding: const EdgeInsets.only(top: 24),
          ),
          child: child!,
        ),
      ),
    );

void main() {
  // The test host has no network; without this google_fonts tries to fetch
  // Space Grotesk / IBM Plex Mono at runtime and the pending HTTP failure is
  // reported as a test error. Disabled, it falls back to the bundled default.
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  const sizes = <String, Size>{
    '360x800': Size(360, 800),
    '390x844': Size(390, 844),
    '430x932': Size(430, 932),
  };

  for (final brightness in Brightness.values) {
    for (final entry in sizes.entries) {
      testWidgets('profile hub ${brightness.name} ${entry.key}', (
        tester,
      ) async {
        tester.view.physicalSize = entry.value;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          _host(brightness: brightness, textScale: 1.0),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        await expectLater(
          find.byType(ProfileScreen),
          matchesGoldenFile(
            'goldens/hub_${brightness.name}_${entry.key}.png',
          ),
        );
      });
    }
  }

  // The lower cards (Privacy, Help Center, About, the admin slab and sign-out)
  // sit below the fold on every supported size, so they need their own frame.
  for (final brightness in Brightness.values) {
    testWidgets('profile hub ${brightness.name} 390x844 scrolled', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(brightness: brightness, textScale: 1.0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.drag(
        find.byType(Scrollable).first,
        const Offset(0, -700),
      );
      await tester.pump(const Duration(milliseconds: 16));

      await expectLater(
        find.byType(ProfileScreen),
        matchesGoldenFile('goldens/hub_${brightness.name}_scrolled.png'),
      );
    });
  }

  for (final scale in const [1.5, 2.0]) {
    testWidgets('profile hub dark 390x844 @${scale}x', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _host(brightness: Brightness.dark, textScale: scale),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await expectLater(
        find.byType(ProfileScreen),
        matchesGoldenFile('goldens/hub_dark_scale_$scale.png'),
      );
    });
  }
}
