import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/core/widgets/glass_action_button.dart';
import 'package:fyp_foreseeme/features/auth/domain/models/user_model.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/medication/domain/enums/medication_enums.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_log_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/medication_model.dart';
import 'package:fyp_foreseeme/features/medication/presentation/adherence_notifier.dart';
import 'package:fyp_foreseeme/features/medication/presentation/check_in_screen.dart';
import 'package:fyp_foreseeme/features/medication/presentation/widgets/med_orbit_field.dart';

/// Covers the redesigned Daily Check-In ("Medication Orbit") surface: that it
/// still renders the user's real doses, that Take Now / Skip still reach the
/// adherence notifier exactly once, that a failed write rolls back to Pending,
/// and that day navigation still moves the selected date.

// ── Fixtures ─────────────────────────────────────────────────────────────────

MedicationModel _medication({
  String id = 'm1',
  String name = 'Ventolin',
  MedicationType type = MedicationType.pill,
  MedicationFrequency frequency = MedicationFrequency.twiceDaily,
  List<String> reminderTimes = const ['09:00', '21:00'],
}) => MedicationModel(
  id: id,
  uid: 'u1',
  name: name,
  dosage: '2 puffs',
  type: type,
  frequency: frequency,
  reminderTimes: reminderTimes,
  isActive: true,
  createdAt: DateTime(2026, 1, 1),
);

/// "Now", to the minute — a dose scheduled here is actionable per the
/// dose-state engine, which is what puts the check-in controls on screen.
String _nowTime() {
  final now = DateTime.now();
  return '${now.hour.toString().padLeft(2, '0')}:'
      '${now.minute.toString().padLeft(2, '0')}';
}

/// A minute-of-day offset from now that stays inside the same day, so a
/// fixture never wraps past midnight and reorders the schedule.
String _timeNear(int minutesBefore) {
  final now = DateTime.now();
  final base = (now.hour * 60 + now.minute).clamp(minutesBefore, 1439);
  final m = base - minutesBefore;
  return '${(m ~/ 60).toString().padLeft(2, '0')}:'
      '${(m % 60).toString().padLeft(2, '0')}';
}

class _RecordingAdherenceNotifier extends AdherenceNotifier {
  static final List<(String, String, AdherenceStatus)> writes = [];

  /// Held open so a test can observe the in-flight window before the write
  /// settles; completed (or failed) on demand.
  static Completer<void>? gate;

  /// When set, every write fails with this error.
  static Object? failWith;

  @override
  FutureOr<void> build() {}

  @override
  Future<void> updateStatus({
    required MedicationModel medication,
    required DateTime date,
    required String timeString,
    required AdherenceStatus status,
  }) async {
    writes.add((medication.id, timeString, status));
    if (gate != null) await gate!.future;
    if (failWith != null) throw failWith!;
  }
}

Widget _host({
  required List<MedicationModel> medications,
  List<AdherenceLogModel> logs = const [],
  bool reduceMotion = false,
}) => ProviderScope(
  overrides: [
    authStateProvider.overrideWith((ref) => Stream<UserModel?>.value(null)),
    medicationsStreamProvider.overrideWith((ref) => Stream.value(medications)),
    adherenceLogsStreamProvider.overrideWith((ref, date) => Stream.value(logs)),
    adherenceNotifierProvider.overrideWith(_RecordingAdherenceNotifier.new),
  ],
  child: MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: const DailyCheckInScreen(),
    ),
  ),
);

/// Height of the app shell's floating bottom navigation (8 + 68 + 24).
const double kShellNavHeight = 100;

/// Mirrors `AppShell`: `Scaffold(extendBody: true)` with a floating bottom
/// navigation, which is what puts a bottom inset on the Check-In body.
Widget _shellHost({
  required List<MedicationModel> medications,
  double textScale = 1.0,
  Size size = const Size(390, 844),
}) => ProviderScope(
  overrides: [
    authStateProvider.overrideWith((ref) => Stream<UserModel?>.value(null)),
    medicationsStreamProvider.overrideWith((ref) => Stream.value(medications)),
    adherenceLogsStreamProvider.overrideWith(
      (ref, date) => Stream.value(const <AdherenceLogModel>[]),
    ),
    adherenceNotifierProvider.overrideWith(_RecordingAdherenceNotifier.new),
  ],
  child: MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
        padding: const EdgeInsets.only(top: 24),
      ),
      child: const Scaffold(
        extendBody: true,
        body: DailyCheckInScreen(),
        bottomNavigationBar: SizedBox(height: kShellNavHeight),
      ),
    ),
  ),
);

/// Pumps past both check-in beats and the commit.
Future<void> _settleCheckIn(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

void main() {
  setUp(() {
    _RecordingAdherenceNotifier.writes.clear();
    _RecordingAdherenceNotifier.gate = null;
    _RecordingAdherenceNotifier.failWith = null;
  });

  // ── Rendering ──────────────────────────────────────────────────────────────

  testWidgets('renders one orbit object per scheduled dose, with real data', (
    tester,
  ) async {
    await tester.pumpWidget(_host(medications: [_medication()]));
    await tester.pump();

    expect(find.text('Ventolin'), findsOneWidget);
    expect(find.text('2 puffs'), findsOneWidget);
    // Two reminder times → two objects on the temporal path.
    expect(
      tester.widget<MedOrbitField>(find.byType(MedOrbitField)).doses.length,
      2,
    );
    expect(find.text('TODAY'), findsOneWidget);
  });

  testWidgets('an empty day shows the prototype plate, not a dose', (
    tester,
  ) async {
    await tester.pumpWidget(_host(medications: const []));
    await tester.pump();

    expect(find.text('NO DOSES SCHEDULED'), findsOneWidget);
    expect(find.text('Nothing scheduled'), findsOneWidget);
    expect(find.text('NO DOSE'), findsOneWidget);
  });

  // ── Pending state ──────────────────────────────────────────────────────────

  testWidgets('a pending dose offers both glass actions at a 48dp target', (
    tester,
  ) async {
    final time = _nowTime();
    await tester.pumpWidget(
      _host(
        medications: [
          _medication(
            frequency: MedicationFrequency.onceDaily,
            reminderTimes: [time],
          ),
        ],
      ),
    );
    await tester.pump();

    expect(find.text('NEXT DOSE'), findsOneWidget);

    final buttons = tester
        .widgetList<GlassActionButton>(find.byType(GlassActionButton))
        .toList();
    expect(buttons, hasLength(2));
    expect(
      buttons.map((b) => b.semanticLabel),
      containsAll(<String>['Take now', 'Skip']),
    );
    // Meaning is carried by a glyph as well as by tone, so the two are never
    // distinguished by colour alone.
    expect(buttons.every((b) => b.icon != null), isTrue);
    expect(
      buttons.where((b) => b.tone == GlassActionTone.primary),
      hasLength(1),
    );

    for (final element in find.byType(GlassActionButton).evaluate()) {
      final size = (element.renderObject! as RenderBox).size;
      expect(size.height, greaterThanOrEqualTo(48.0));
      expect(size.width, greaterThanOrEqualTo(48.0));
    }
  });

  // ── Mutations ──────────────────────────────────────────────────────────────

  testWidgets('Take Now writes taken through the adherence notifier', (
    tester,
  ) async {
    final time = _nowTime();
    await tester.pumpWidget(
      _host(
        medications: [
          _medication(
            frequency: MedicationFrequency.onceDaily,
            reminderTimes: [time],
          ),
        ],
      ),
    );
    await tester.pump();

    await tester.tap(find.text('TAKE NOW'));
    await _settleCheckIn(tester);

    expect(_RecordingAdherenceNotifier.writes, [
      ('m1', time, AdherenceStatus.taken),
    ]);
  });

  testWidgets('Skip writes missed through the adherence notifier', (
    tester,
  ) async {
    final time = _nowTime();
    await tester.pumpWidget(
      _host(
        medications: [
          _medication(
            frequency: MedicationFrequency.onceDaily,
            reminderTimes: [time],
          ),
        ],
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Skip'));
    await _settleCheckIn(tester);

    expect(_RecordingAdherenceNotifier.writes, [
      ('m1', time, AdherenceStatus.missed),
    ]);
  });

  // ── Final states ───────────────────────────────────────────────────────────

  testWidgets('a taken dose shows completion and withdraws both actions', (
    tester,
  ) async {
    final time = _nowTime();
    await tester.pumpWidget(
      _host(
        medications: [
          _medication(
            frequency: MedicationFrequency.onceDaily,
            reminderTimes: [time],
          ),
        ],
      ),
    );
    await tester.pump();

    await tester.tap(find.text('TAKE NOW'));
    await _settleCheckIn(tester);

    expect(find.text('COMPLETED'), findsOneWidget);
    expect(find.byType(GlassActionButton), findsNothing);
    expect(find.text('TAKE NOW'), findsNothing);
    expect(find.text('Skip'), findsNothing);
  });

  testWidgets('a skipped dose shows its state and withdraws both actions', (
    tester,
  ) async {
    final time = _nowTime();
    await tester.pumpWidget(
      _host(
        medications: [
          _medication(
            frequency: MedicationFrequency.onceDaily,
            reminderTimes: [time],
          ),
        ],
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Skip'));
    await _settleCheckIn(tester);

    expect(find.text('SKIPPED'), findsOneWidget);
    expect(find.byType(GlassActionButton), findsNothing);
  });

  // ── Race conditions ────────────────────────────────────────────────────────

  testWidgets('rapid double tap on Take Now commits exactly one mutation', (
    tester,
  ) async {
    final time = _nowTime();
    await tester.pumpWidget(
      _host(
        medications: [
          _medication(
            frequency: MedicationFrequency.onceDaily,
            reminderTimes: [time],
          ),
        ],
      ),
    );
    await tester.pump();

    // Two taps inside the first beat, before any state has committed. The
    // second goes through the button's hit box, not its label, so it is a real
    // repeat tap rather than a find that happens to miss.
    final takeButton = find.byType(GlassActionButton).first;
    await tester.tap(takeButton, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 20));
    await tester.tap(takeButton, warnIfMissed: false);
    await _settleCheckIn(tester);

    expect(_RecordingAdherenceNotifier.writes, hasLength(1));
  });

  testWidgets('Take Now then Skip in the same beat commits only the first', (
    tester,
  ) async {
    final time = _nowTime();
    await tester.pumpWidget(
      _host(
        medications: [
          _medication(
            frequency: MedicationFrequency.onceDaily,
            reminderTimes: [time],
          ),
        ],
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(GlassActionButton).first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 20));
    await tester.tap(find.byType(GlassActionButton).last, warnIfMissed: false);
    await _settleCheckIn(tester);

    expect(_RecordingAdherenceNotifier.writes, [
      ('m1', time, AdherenceStatus.taken),
    ]);
  });

  // ── Rollback ───────────────────────────────────────────────────────────────

  testWidgets('a failed write restores Pending and its actions', (
    tester,
  ) async {
    _RecordingAdherenceNotifier.failWith = Exception('permission-denied');

    final time = _nowTime();
    await tester.pumpWidget(
      _host(
        medications: [
          _medication(
            frequency: MedicationFrequency.onceDaily,
            reminderTimes: [time],
          ),
        ],
      ),
    );
    await tester.pump();

    await tester.tap(find.text('TAKE NOW'));
    await _settleCheckIn(tester);
    await tester.pump();

    // Back to an actionable dose, with both controls available again.
    expect(find.text('NEXT DOSE'), findsOneWidget);
    expect(find.byType(GlassActionButton), findsNWidgets(2));
    expect(find.text('COMPLETED'), findsNothing);

    // Calm copy on the existing snackbar channel — never the raw exception.
    expect(
      find.text("Couldn't save this dose as taken. Please try again."),
      findsOneWidget,
    );
    expect(find.textContaining('permission-denied'), findsNothing);

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('competing actions are blocked while a write is in flight', (
    tester,
  ) async {
    _RecordingAdherenceNotifier.gate = Completer<void>();

    final time = _nowTime();
    await tester.pumpWidget(
      _host(
        medications: [
          _medication(
            frequency: MedicationFrequency.onceDaily,
            reminderTimes: [time],
          ),
        ],
      ),
    );
    await tester.pump();

    await tester.tap(find.text('TAKE NOW'));
    await _settleCheckIn(tester);

    // Optimistic state is already visible while the write is still open.
    expect(find.text('COMPLETED'), findsOneWidget);
    expect(_RecordingAdherenceNotifier.writes, hasLength(1));

    _RecordingAdherenceNotifier.gate!.complete();
    await tester.pump();
    await tester.pump();

    expect(_RecordingAdherenceNotifier.writes, hasLength(1));
  });

  // ── Reduced motion ─────────────────────────────────────────────────────────

  testWidgets('reduced motion keeps the check-in working, without the travel', (
    tester,
  ) async {
    final time = _nowTime();
    await tester.pumpWidget(
      _host(
        reduceMotion: true,
        medications: [
          _medication(
            frequency: MedicationFrequency.onceDaily,
            reminderTimes: [time],
          ),
        ],
      ),
    );
    await tester.pump();

    expect(find.byType(GlassActionButton), findsNWidgets(2));

    await tester.tap(find.text('TAKE NOW'));
    // No beats to wait through — the state commits on the next frame.
    await tester.pump();
    await tester.pump();

    expect(_RecordingAdherenceNotifier.writes, [
      ('m1', time, AdherenceStatus.taken),
    ]);
    expect(find.text('COMPLETED'), findsOneWidget);
    expect(find.byType(GlassActionButton), findsNothing);
  });

  // ── Shell clearance (regression: controls were drawn under the nav bar) ────

  testWidgets('the check-in controls clear the app shell bottom navigation', (
    tester,
  ) async {
    for (final size in const [
      Size(360, 800),
      Size(390, 844),
      Size(430, 932),
    ]) {
      for (final scale in const [1.0, 1.5, 2.0]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          _shellHost(
            size: size,
            textScale: scale,
            medications: [
              _medication(
                frequency: MedicationFrequency.onceDaily,
                reminderTimes: [_nowTime()],
              ),
            ],
          ),
        );
        await tester.pump();

        final where = '\${size.width.toInt()}x\${size.height.toInt()} @\${scale}x';
        final buttons = find.byType(GlassActionButton);
        expect(buttons, findsNWidgets(2), reason: 'both controls at \$where');

        final navTop = size.height - kShellNavHeight;
        for (final element in buttons.evaluate()) {
          final box = element.renderObject! as RenderBox;
          final rect =
              box.localToGlobal(Offset.zero) & box.size;
          expect(
            rect.bottom,
            lessThanOrEqualTo(navTop),
            reason: 'control overlaps the bottom navigation at \$where',
          );
          expect(rect.height, greaterThanOrEqualTo(48.0), reason: where);
        }
        expect(tester.takeException(), isNull, reason: where);
      }
    }
  });

  // ── Confirmation hold ──────────────────────────────────────────────────────

  testWidgets('focus holds on the resolved dose before advancing', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        medications: [
          _medication(
            id: 'm1',
            name: 'Brufen',
            frequency: MedicationFrequency.onceDaily,
            reminderTimes: [_timeNear(20)],
          ),
          _medication(
            id: 'm2',
            name: 'Panadol',
            frequency: MedicationFrequency.onceDaily,
            reminderTimes: [_timeNear(0)],
          ),
        ],
      ),
    );
    await tester.pump();

    // The earlier dose is the hero and is actionable.
    expect(find.text('Brufen'), findsOneWidget);
    await tester.tap(find.text('TAKE NOW'));
    await _settleCheckIn(tester);

    // Immediately after commit the resolved dose keeps the readout, so its
    // new status is legible rather than being replaced on the spot.
    expect(find.text('COMPLETED'), findsOneWidget);
    expect(find.text('Brufen'), findsOneWidget);
    expect(find.text('Panadol'), findsNothing);

    // Once the beat elapses, the next pending dose takes over.
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump();
    expect(find.text('Panadol'), findsOneWidget);
    expect(find.text('COMPLETED'), findsNothing);

    await tester.pump(const Duration(seconds: 1));
  });

  // ── Navigation + layout ────────────────────────────────────────────────────

  testWidgets('the date shuttle still moves the selected day', (tester) async {
    await tester.pumpWidget(_host(medications: [_medication()]));
    await tester.pump();

    expect(find.text('TODAY'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Next day'));
    await tester.pump();
    await tester.pump();
    expect(find.text('TOMORROW'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Previous day'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Previous day'));
    await tester.pump();
    await tester.pump();
    expect(find.text('YESTERDAY'), findsOneWidget);
  });

  testWidgets('the orbit lays out without overflow at small and large text', (
    tester,
  ) async {
    for (final size in const [Size(360, 640), Size(430, 932)]) {
      for (final textScale in const [1.0, 1.5, 2.0]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authStateProvider.overrideWith(
                (ref) => Stream<UserModel?>.value(null),
              ),
              medicationsStreamProvider.overrideWith(
                (ref) => Stream.value([
                  _medication(
                    frequency: MedicationFrequency.thriceDaily,
                    reminderTimes: ['08:00', _nowTime(), '23:30'],
                  ),
                  _medication(
                    id: 'm2',
                    name: 'Montelukast sodium extended',
                    type: MedicationType.syrup,
                    reminderTimes: const ['07:30', '22:30'],
                  ),
                ]),
              ),
              adherenceLogsStreamProvider.overrideWith(
                (ref, date) => Stream.value(const <AdherenceLogModel>[]),
              ),
              adherenceNotifierProvider.overrideWith(
                _RecordingAdherenceNotifier.new,
              ),
            ],
            child: MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  textScaler: TextScaler.linear(textScale),
                ),
                child: const DailyCheckInScreen(),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
      }
    }
  });
}
