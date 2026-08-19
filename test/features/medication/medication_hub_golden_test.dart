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
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_log_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/medication_model.dart';
import 'package:fyp_foreseeme/features/medication/presentation/adherence_notifier.dart';
import 'package:fyp_foreseeme/features/medication/presentation/medication_hub_providers.dart';
import 'package:fyp_foreseeme/features/medication/presentation/medication_screen.dart';

/// Renders the Medications screen across the sizes, themes and text scales the
/// design review covers, so the layout can be compared against the approved
/// prototype (`docs/Design/ForeSeeMe Medications.html`) rather than eyeballed.
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
/// The fixture deliberately reproduces the prototype's own scenario — four
/// active medications, five doses, two taken and one missed at 13:30 — so the
/// two images are comparable frame for frame.

final DateTime _now = DateTime(2026, 5, 14, 13, 30);
final DateTime _today = DateTime(2026, 5, 14);

MedicationModel _medication({
  required String id,
  required String name,
  required String dosage,
  required MedicationType type,
  required MedicationFrequency frequency,
  required List<String> times,
}) => MedicationModel(
  id: id,
  uid: 'u1',
  name: name,
  dosage: dosage,
  type: type,
  frequency: frequency,
  reminderTimes: times,
  isActive: true,
  createdAt: DateTime(2026, 1, 1),
);

final _medications = [
  _medication(
    id: 'm1',
    name: 'Metformin',
    dosage: '500 mg',
    type: MedicationType.pill,
    frequency: MedicationFrequency.twiceDaily,
    times: const ['08:00', '20:00'],
  ),
  _medication(
    id: 'm2',
    name: 'Lisinopril',
    dosage: '10 mg',
    type: MedicationType.pill,
    frequency: MedicationFrequency.onceDaily,
    times: const ['08:00'],
  ),
  _medication(
    id: 'm3',
    name: 'Amoxicillin',
    dosage: '5 ml suspension',
    type: MedicationType.syrup,
    frequency: MedicationFrequency.thriceDaily,
    times: const ['09:00', '12:00', '14:00'],
  ),
  _medication(
    id: 'm4',
    name: 'Vitamin D3',
    dosage: '1000 IU',
    type: MedicationType.pill,
    frequency: MedicationFrequency.onceDaily,
    times: const ['09:00'],
  ),
];

AdherenceLogModel _log(String medicationId, String time, AdherenceStatus s) =>
    AdherenceLogModel(
      id: '${medicationId}_$time',
      medicationId: medicationId,
      uid: 'u1',
      scheduledTime: time,
      date: _today,
      selectedDate: _today,
      status: s,
      confirmedAt: DateTime(2026, 5, 14, 8, 30),
    );

final _logs = [
  _log('m1', '08:00', AdherenceStatus.taken),
  _log('m2', '08:00', AdherenceStatus.taken),
];

Widget _host({
  required Brightness brightness,
  required double textScale,
  List<MedicationModel>? medications,
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
    medicationsStreamProvider.overrideWith(
      (ref) => Stream.value(medications ?? _medications),
    ),
    adherenceLogsStreamProvider.overrideWith(
      (ref, date) => Stream.value(medications == null ? _logs : const []),
    ),
    hubNowProvider.overrideWithValue(_now),
  ],
  child: MaterialApp(
    theme: ForeSeeMeTheme.light,
    darkTheme: ForeSeeMeTheme.dark,
    themeMode: brightness == Brightness.dark
        ? ThemeMode.dark
        : ThemeMode.light,
    home: const MedicationScreen(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        padding: const EdgeInsets.only(top: 24, bottom: 8),
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
      testWidgets('medications ${brightness.name} ${entry.key}', (tester) async {
        tester.view.physicalSize = entry.value;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          _host(brightness: brightness, textScale: 1.0),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        await expectLater(
          find.byType(MedicationScreen),
          matchesGoldenFile('goldens/meds_${brightness.name}_${entry.key}.png'),
        );
      });
    }
  }

  // The lower medication cards sit below the fold on every supported size, so
  // they need their own frame.
  for (final brightness in Brightness.values) {
    testWidgets('medications ${brightness.name} 390x844 scrolled', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(brightness: brightness, textScale: 1.0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      await tester.drag(find.byType(Scrollable).first, const Offset(0, -320));
      await tester.pump(const Duration(milliseconds: 16));

      await expectLater(
        find.byType(MedicationScreen),
        matchesGoldenFile('goldens/meds_${brightness.name}_scrolled.png'),
      );
    });
  }

  testWidgets('medications dark 390x844 empty', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(brightness: Brightness.dark, textScale: 1.0, medications: const []),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    await expectLater(
      find.byType(MedicationScreen),
      matchesGoldenFile('goldens/meds_dark_empty.png'),
    );
  });

  for (final scale in const [1.5, 2.0]) {
    testWidgets('medications dark 390x844 @${scale}x', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _host(brightness: Brightness.dark, textScale: scale),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      await expectLater(
        find.byType(MedicationScreen),
        matchesGoldenFile('goldens/meds_dark_scale_$scale.png'),
      );
    });
  }
}
