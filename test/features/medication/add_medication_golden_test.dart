@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/features/auth/domain/models/user_model.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/medication/domain/enums/medication_enums.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/medication_model.dart';
import 'package:fyp_foreseeme/features/medication/presentation/add_medication_screen.dart';
import 'package:fyp_foreseeme/features/medication/presentation/medication_hub_providers.dart';

/// Renders the Add / Edit Medication screen across the sizes, themes and text
/// scales the design review covers, so the layout can be compared against the
/// approved prototype (`docs/Design/ForeSeeMe Add Medication (1).html`) rather
/// than eyeballed.
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
///
/// `hubNowProvider` is pinned so the preview card's NOW marker lands in the
/// same place every run.

final DateTime _now = DateTime(2026, 5, 14, 13, 30);

final _sample = MedicationModel(
  id: 'm1',
  uid: 'u1',
  name: 'Metformin',
  dosage: '500 mg',
  type: MedicationType.pill,
  frequency: MedicationFrequency.twiceDaily,
  reminderTimes: const ['08:00', '20:00'],
  isActive: true,
  createdAt: DateTime(2026, 1, 1),
);

Widget _host({
  required Brightness brightness,
  double textScale = 1.0,
  MedicationModel? medication,
}) => ProviderScope(
  overrides: [
    authStateProvider.overrideWith(
      (ref) => Stream<UserModel?>.value(
        UserModel(
          uid: 'u1',
          email: 'amara@example.com',
          displayName: 'Amara Okafor',
          createdAt: DateTime(2026, 1, 1),
        ),
      ),
    ),
    hubNowProvider.overrideWithValue(_now),
  ],
  child: MaterialApp(
    theme: ForeSeeMeTheme.light,
    darkTheme: ForeSeeMeTheme.dark,
    themeMode: brightness == Brightness.dark
        ? ThemeMode.dark
        : ThemeMode.light,
    home: AddMedicationScreen(medication: medication),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        // `AppShell` runs `Scaffold(extendBody: true)`, so in the real app
        // Flutter reports `AppBottomNavBar`'s 100px height as this screen's
        // bottom inset. Reproducing it here is what makes the footer sit where
        // the review needs to see it.
        padding: const EdgeInsets.only(top: 24, bottom: 100),
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
      testWidgets('add medication ${brightness.name} ${entry.key}', (
        tester,
      ) async {
        tester.view.physicalSize = entry.value;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_host(brightness: brightness));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 700));

        await expectLater(
          find.byType(AddMedicationScreen),
          matchesGoldenFile(
            'goldens/addmed_${brightness.name}_${entry.key}.png',
          ),
        );
      });
    }
  }

  // Everything below "3 · HOW OFTEN" sits under the fold on every supported
  // size, so the filled edit-mode form needs its own scrolled frame.
  for (final brightness in Brightness.values) {
    testWidgets('add medication ${brightness.name} filled scrolled', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _host(brightness: brightness, medication: _sample),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      await tester.drag(find.byType(Scrollable).first, const Offset(0, -360));
      await tester.pump(const Duration(milliseconds: 16));

      await expectLater(
        find.byType(AddMedicationScreen),
        matchesGoldenFile('goldens/addmed_${brightness.name}_filled.png'),
      );
    });
  }

  for (final scale in const [1.5, 2.0]) {
    testWidgets('add medication dark 390x844 scale $scale', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _host(
          brightness: Brightness.dark,
          textScale: scale,
          medication: _sample,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      await expectLater(
        find.byType(AddMedicationScreen),
        matchesGoldenFile('goldens/addmed_dark_scale_$scale.png'),
      );

      // The frequency cards and the reminder rows are the geometry most at
      // risk from a large text scale, and both sit under the fold.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -430));
      await tester.pump(const Duration(milliseconds: 16));

      await expectLater(
        find.byType(AddMedicationScreen),
        matchesGoldenFile('goldens/addmed_dark_scale_${scale}_scrolled.png'),
      );
    });
  }
}
