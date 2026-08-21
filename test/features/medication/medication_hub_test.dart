import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/features/auth/domain/models/user_model.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/medication/domain/enums/medication_enums.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_log_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/medication_hub_state.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/medication_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/services/medication_hub_service.dart';
import 'package:fyp_foreseeme/features/medication/presentation/adherence_notifier.dart';
import 'package:fyp_foreseeme/features/medication/presentation/medication_hub_providers.dart';
import 'package:fyp_foreseeme/features/medication/presentation/medication_screen.dart';
import 'package:fyp_foreseeme/features/medication/presentation/widgets/medication_hub_chrome.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

/// `AppBottomNavBar`'s laid-out height: a 68px bar with 8px above and 24px
/// below it. Matches `check_in_orbit_test.dart`'s constant of the same name.
const double kShellNavHeight = 100;

MedicationModel _medication({
  required String id,
  String name = 'Metformin',
  String dosage = '500 mg',
  MedicationType type = MedicationType.pill,
  MedicationFrequency frequency = MedicationFrequency.twiceDaily,
  List<String> reminderTimes = const ['08:00', '20:00'],
  bool isActive = true,
}) => MedicationModel(
  id: id,
  uid: 'u1',
  name: name,
  dosage: dosage,
  type: type,
  frequency: frequency,
  reminderTimes: reminderTimes,
  isActive: isActive,
  createdAt: DateTime(2026, 1, 1),
);

AdherenceLogModel _log({
  required String medicationId,
  required String time,
  required DateTime date,
  required AdherenceStatus status,
  DateTime? confirmedAt,
}) => AdherenceLogModel(
  id: '${medicationId}_$time',
  medicationId: medicationId,
  uid: 'u1',
  scheduledTime: time,
  date: date,
  selectedDate: date,
  status: status,
  confirmedAt: confirmedAt,
);

/// Midday on a fixed day, so the 08:00 dose is past, 12:00 is current and
/// 20:00 is still ahead.
final DateTime _now = DateTime(2026, 5, 14, 13, 30);
final DateTime _today = DateTime(2026, 5, 14);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  const service = MedicationHubService();

  // ── Domain derivation ──────────────────────────────────────────────────────

  group('MedicationHubService', () {
    test('archived medications are neither listed nor scheduled', () {
      final summary = service.summarise(
        medications: [
          _medication(id: 'm1'),
          _medication(id: 'm2', name: 'Archived', isActive: false),
        ],
        logs: const [],
        now: _now,
      );

      expect(summary.activeCount, 1);
      expect(summary.medications.single.medication.id, 'm1');
      expect(
        summary.doses.every((d) => d.medication.id == 'm1'),
        isTrue,
      );
    });

    test('expands doses from real reminder times, in order', () {
      final summary = service.summarise(
        medications: [
          _medication(
            id: 'm1',
            reminderTimes: const ['20:00', '08:00'],
          ),
          _medication(
            id: 'm2',
            name: 'Vitamin D3',
            frequency: MedicationFrequency.onceDaily,
            reminderTimes: const ['09:00'],
          ),
        ],
        logs: const [],
        now: _now,
      );

      expect(
        summary.doses.map((d) => d.time).toList(),
        ['08:00', '09:00', '20:00'],
      );
      expect(summary.scheduledCount, 3);
    });

    test('caps reminder times at the frequency and drops malformed ones', () {
      final summary = service.summarise(
        medications: [
          _medication(
            id: 'm1',
            frequency: MedicationFrequency.onceDaily,
            reminderTimes: const ['08:00', '20:00'],
          ),
          _medication(
            id: 'm2',
            name: 'Broken',
            frequency: MedicationFrequency.onceDaily,
            reminderTimes: const ['not-a-time'],
          ),
        ],
        logs: const [],
        now: _now,
      );

      expect(summary.doses.map((d) => d.time).toList(), ['08:00']);
      expect(
        summary.medications
            .firstWhere((m) => m.medication.id == 'm2')
            .status,
        HubMedicationStatus.noSchedule,
      );
    });

    test('phases follow the dose-state engine, promoting one NEXT UP', () {
      final summary = service.summarise(
        medications: [
          _medication(
            id: 'm1',
            frequency: MedicationFrequency.thriceDaily,
            reminderTimes: const ['08:00', '13:40', '20:00'],
          ),
        ],
        logs: [
          _log(
            medicationId: 'm1',
            time: '08:00',
            date: _today,
            status: AdherenceStatus.taken,
            confirmedAt: DateTime(2026, 5, 14, 8, 5),
          ),
        ],
        now: _now,
      );

      expect(
        summary.doses.map((d) => d.phase).toList(),
        [HubDosePhase.taken, HubDosePhase.next, HubDosePhase.later],
      );
      expect(summary.nextDose?.time, '13:40');
      expect(summary.takenCount, 1);
      expect(summary.missedCount, 0);
    });

    test('a lapsed dose is MISSED and a user-skipped dose is SKIPPED', () {
      final summary = service.summarise(
        medications: [
          _medication(
            id: 'm1',
            frequency: MedicationFrequency.twiceDaily,
            reminderTimes: const ['06:00', '08:00'],
          ),
        ],
        logs: [
          // Confirmed as skipped inside the grace window — a deliberate skip.
          _log(
            medicationId: 'm1',
            time: '08:00',
            date: _today,
            status: AdherenceStatus.missed,
            confirmedAt: DateTime(2026, 5, 14, 8, 10),
          ),
        ],
        now: _now,
      );

      expect(summary.doses[0].phase, HubDosePhase.missed);
      expect(summary.doses[0].phase.label, 'MISSED');
      expect(summary.doses[1].phase, HubDosePhase.skipped);
      expect(summary.doses[1].phase.label, 'SKIPPED');
      expect(summary.missedCount, 2);
      expect(summary.nextDose, isNull);
    });

    test('per-medication status is derived from today only', () {
      final summary = service.summarise(
        medications: [
          _medication(id: 'm1', name: 'AllTaken'),
          _medication(id: 'm2', name: 'Behind'),
          _medication(id: 'm3', name: 'Ongoing'),
        ],
        logs: [
          _log(
            medicationId: 'm1',
            time: '08:00',
            date: _today,
            status: AdherenceStatus.taken,
            confirmedAt: DateTime(2026, 5, 14, 8, 1),
          ),
          _log(
            medicationId: 'm1',
            time: '20:00',
            date: _today,
            status: AdherenceStatus.taken,
            confirmedAt: DateTime(2026, 5, 14, 8, 2),
          ),
          _log(
            medicationId: 'm3',
            time: '08:00',
            date: _today,
            status: AdherenceStatus.taken,
            confirmedAt: DateTime(2026, 5, 14, 8, 3),
          ),
        ],
        now: _now,
      );

      HubMedication of(String id) =>
          summary.medications.firstWhere((m) => m.medication.id == id);

      expect(of('m1').status, HubMedicationStatus.allTaken);
      expect(of('m2').status, HubMedicationStatus.behind);
      expect(of('m2').missedCount, 1);
      expect(of('m3').status, HubMedicationStatus.onTrack);
    });

    test('logs from another day are ignored', () {
      final summary = service.summarise(
        medications: [_medication(id: 'm1')],
        logs: [
          _log(
            medicationId: 'm1',
            time: '08:00',
            date: _today.subtract(const Duration(days: 1)),
            status: AdherenceStatus.taken,
            confirmedAt: DateTime(2026, 5, 13, 8, 1),
          ),
        ],
        now: _now,
      );

      expect(summary.takenCount, 0);
      expect(summary.doses.first.phase, HubDosePhase.missed);
    });

    test('no active medications yields the empty summary', () {
      final summary = service.summarise(
        medications: [_medication(id: 'm1', isActive: false)],
        logs: const [],
        now: _now,
      );

      expect(summary.activeCount, 0);
      expect(summary.doses, isEmpty);
      expect(summary.nextDose, isNull);
    });
  });

  // ── Screen ─────────────────────────────────────────────────────────────────

  Widget host({
    required List<MedicationModel> medications,
    List<AdherenceLogModel> logs = const [],
    Brightness brightness = Brightness.dark,
    Stream<List<MedicationModel>>? medicationStream,
    bool shell = false,
  }) => ProviderScope(
    overrides: [
      authStateProvider.overrideWith(
        (ref) => Stream<UserModel?>.value(
          UserModel(
            uid: 'u1',
            email: 'a@b.com',
            createdAt: DateTime(2026, 1, 1),
          ),
        ),
      ),
      medicationsStreamProvider.overrideWith(
        (ref) => medicationStream ?? Stream.value(medications),
      ),
      adherenceLogsStreamProvider.overrideWith(
        (ref, date) => Stream.value(logs),
      ),
      hubNowProvider.overrideWithValue(_now),
    ],
    child: MaterialApp(
      theme: ForeSeeMeTheme.light,
      darkTheme: ForeSeeMeTheme.dark,
      themeMode: brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      // `shell` mirrors `AppShell`: `Scaffold(extendBody: true)` with a
      // floating bottom navigation, which is what puts the bar's height on
      // this screen's bottom inset — the seam `_BottomActions` reads for its
      // clearance.
      home: shell
          ? const Scaffold(
              extendBody: true,
              body: MedicationScreen(),
              bottomNavigationBar: SizedBox(height: kShellNavHeight),
            )
          : const MedicationScreen(),
    ),
  );

  group('MedicationScreen', () {
    testWidgets('renders real medications from the stream', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        host(
          medications: [
            _medication(id: 'm1'),
            _medication(
              id: 'm2',
              name: 'Amoxicillin',
              dosage: '5 ml',
              type: MedicationType.syrup,
              frequency: MedicationFrequency.thriceDaily,
              reminderTimes: const ['08:00', '14:00', '20:00'],
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Metformin'), findsOneWidget);
      expect(find.text('Amoxicillin'), findsOneWidget);
      expect(find.text('500 mg · Twice daily'), findsOneWidget);
      expect(find.text('5 ml · Three times daily'), findsOneWidget);

      // Reminder times, exactly as stored — two shown in full, three
      // compressed to hours, as the prototype does.
      expect(find.text('08:00 · 20:00'), findsOneWidget);
      expect(find.text('08 · 14 · 20'), findsOneWidget);

      // Counts, not placeholders. The prototype states the active count twice:
      // the hero chip and the `YOUR MEDICATIONS` header.
      expect(find.text('2 ACTIVE'), findsNWidgets(2));
      expect(find.text('0 of 5 taken'), findsOneWidget);
    });

    testWidgets('archived medications never reach the screen', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        host(
          medications: [
            _medication(id: 'm1'),
            _medication(id: 'm2', name: 'Archived', isActive: false),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Metformin'), findsOneWidget);
      expect(find.text('Archived'), findsNothing);
      expect(find.text('1 ACTIVE'), findsNWidgets(2));
    });

    testWidgets('empty state invites a first medication, inventing none', (
      tester,
    ) async {
      await tester.pumpWidget(host(medications: const []));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('No medications yet'), findsOneWidget);
      expect(find.byType(MedHubMedicationCard), findsNothing);
      // Nothing to check in on, so the slab is not offered — but Add
      // Medication stays reachable.
      expect(find.byType(MedHubCheckInCta), findsNothing);
      expect(find.byType(MedHubFab), findsOneWidget);
    });

    testWidgets('loading state shows no fabricated counts', (tester) async {
      await tester.pumpWidget(
        host(
          medications: const [],
          medicationStream: const Stream<List<MedicationModel>>.empty(),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.textContaining('ACTIVE'), findsNothing);
    });

    testWidgets('a medication with no usable reminder time says so', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          medications: [
            _medication(id: 'm1', reminderTimes: const []),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('NO REMINDERS'), findsOneWidget);
      expect(find.text('ON TRACK'), findsNothing);
      expect(find.textContaining('No doses are scheduled today'), findsOneWidget);
    });

    testWidgets('taken doses are reflected from the adherence log', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        host(
          medications: [_medication(id: 'm1')],
          logs: [
            _log(
              medicationId: 'm1',
              time: '08:00',
              date: _today,
              status: AdherenceStatus.taken,
              confirmedAt: DateTime(2026, 5, 14, 8, 5),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('1 of 2 taken'), findsOneWidget);
      expect(find.text('1 TAKEN'), findsOneWidget);
      expect(find.text('ON TRACK'), findsOneWidget);
    });

    testWidgets('tapping a medication card opens the detail sheet', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(medications: [_medication(id: 'm1')]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.byType(MedHubMedicationCard));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Edit Medication'), findsOneWidget);
      expect(find.text('Archive Medication'), findsOneWidget);
    });

    testWidgets('the schedule readout reaches the adherence history', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(host(medications: [_medication(id: 'm1')]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // The entry point the previous screen carried in its app bar survives as
      // a labelled control rather than a hidden gesture.
      final readout = find.ancestor(
        of: find.text('0 TAKEN · 1 MISSED'),
        matching: find.byType(Semantics),
      );
      expect(readout, findsWidgets);
      expect(
        tester.getSemantics(readout.first).flagsCollection.isButton,
        isTrue,
      );

      handle.dispose();
    });

    // ── Bottom action composition ──────────────────────────────────────────
    //
    // The actions live in their own region below the list rather than floating
    // over it, so neither can cover a medication card at any scroll position.

    for (final size in const [Size(360, 800), Size(390, 844), Size(430, 932)]) {
      testWidgets(
        'actions never overlap a medication card at '
        '${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            host(
              shell: true,
              medications: [
                for (var i = 0; i < 6; i++)
                  _medication(id: 'm$i', name: 'Med $i'),
              ],
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          // Scrolled to the very bottom is where an overlay would bite.
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, -1200),
          );
          await tester.pump(const Duration(milliseconds: 16));

          final fab = tester.getRect(find.byType(MedHubFab));
          final cta = tester.getRect(find.byType(MedHubCheckInCta));

          for (final card in find.byType(MedHubMedicationCard).evaluate()) {
            final rect = tester.getRect(find.byWidget(card.widget));
            expect(
              rect.overlaps(fab),
              isFalse,
              reason: 'Add Medication overlaps a medication card',
            );
            expect(
              rect.overlaps(cta),
              isFalse,
              reason: 'Check-In overlaps a medication card',
            );
          }

          // The two actions do not cover each other either.
          expect(fab.overlaps(cta), isFalse);

          // Neither reaches into the navigation…
          final navTop = size.height - kShellNavHeight;
          for (final action in <(String, Rect)>[
            ('Add Medication', fab),
            ('Check-In', cta),
          ]) {
            expect(
              action.$2.bottom,
              lessThanOrEqualTo(navTop),
              reason: '${action.$1} overlaps the bottom navigation',
            );
          }

          // …and the action row settles against it rather than floating in a
          // dead band. `_BottomActions` keeps a 24dp gap; anything much larger
          // means the navigation's height has been reserved twice on top of
          // the inset the shell already reports. Measured on whichever action
          // reaches lowest — the FAB is the shorter of the two and rides
          // centred in the row.
          final rowBottom = math.max(fab.bottom, cta.bottom);
          expect(
            navTop - rowBottom,
            lessThanOrEqualTo(32),
            reason: 'the actions are stranded above the bottom navigation',
          );
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('the Check-In slab appears only when a dose is due', (
      tester,
    ) async {
      // Every dose confirmed: nothing left to check in on.
      await tester.pumpWidget(
        host(
          medications: [
            _medication(
              id: 'm1',
              frequency: MedicationFrequency.onceDaily,
              reminderTimes: const ['08:00'],
            ),
          ],
          logs: [
            _log(
              medicationId: 'm1',
              time: '08:00',
              date: _today,
              status: AdherenceStatus.taken,
              confirmedAt: DateTime(2026, 5, 14, 8, 5),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(MedHubCheckInCta), findsNothing);
      expect(find.byType(MedHubFab), findsOneWidget);
    });

    testWidgets('the Check-In slab names the dose it would confirm', (
      tester,
    ) async {
      await tester.pumpWidget(host(medications: [_medication(id: 'm1')]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(MedHubCheckInCta), findsOneWidget);
      expect(find.text('Confirm your 20:00 dose'), findsOneWidget);
    });

    testWidgets('renders in the light theme without overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        host(
          medications: [
            _medication(id: 'm1'),
            _medication(
              id: 'm2',
              name: 'Amoxicillin',
              dosage: '5 ml',
              type: MedicationType.syrup,
              frequency: MedicationFrequency.thriceDaily,
              reminderTimes: const ['08:00', '14:00', '20:00'],
            ),
          ],
          brightness: Brightness.light,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);
      expect(find.text('Metformin'), findsOneWidget);
    });

    testWidgets('survives a 2x text scale without overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(
              (ref) => Stream<UserModel?>.value(
                UserModel(
                  uid: 'u1',
                  email: 'a@b.com',
                  createdAt: DateTime(2026, 1, 1),
                ),
              ),
            ),
            medicationsStreamProvider.overrideWith(
              (ref) => Stream.value([
                _medication(id: 'm1'),
                _medication(
                  id: 'm2',
                  name: 'Amoxicillin',
                  type: MedicationType.syrup,
                  frequency: MedicationFrequency.thriceDaily,
                  reminderTimes: const ['08:00', '14:00', '20:00'],
                ),
              ]),
            ),
            adherenceLogsStreamProvider.overrideWith(
              (ref, date) => Stream.value(const <AdherenceLogModel>[]),
            ),
            hubNowProvider.overrideWithValue(_now),
          ],
          child: MaterialApp(
            theme: ForeSeeMeTheme.dark,
            home: const MedicationScreen(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2.0)),
              child: child!,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);
    });
  });
}
