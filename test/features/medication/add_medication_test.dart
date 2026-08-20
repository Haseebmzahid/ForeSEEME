import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/features/auth/domain/models/user_model.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/medication/domain/enums/medication_enums.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_log_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/medication_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/repositories/adherence_log_repository.dart';
import 'package:fyp_foreseeme/features/medication/domain/repositories/medication_repository.dart';
import 'package:fyp_foreseeme/features/medication/presentation/add_medication_screen.dart';
import 'package:fyp_foreseeme/features/medication/presentation/adherence_notifier.dart';
import 'package:fyp_foreseeme/features/medication/presentation/medication_hub_providers.dart';
import 'package:fyp_foreseeme/features/medication/presentation/medication_notifier.dart';
import 'package:fyp_foreseeme/features/medication/presentation/widgets/add_medication_chrome.dart';
import 'package:fyp_foreseeme/features/medication/presentation/widgets/add_medication_sheets.dart';

/// Behaviour and layout of the Add / Edit Medication screen, rebuilt from the
/// approved prototype (`docs/Design/ForeSeeMe Add Medication (1).html`).
///
/// The visual transcription itself is reviewed through
/// `add_medication_golden_test.dart`; these tests cover what the goldens
/// cannot — that the form still saves the same record, that validation refuses
/// an incomplete one, that edit mode round-trips a stored medication, and that
/// nothing overflows or hides behind `AppBottomNavBar`.

final DateTime _now = DateTime(2026, 5, 14, 13, 30);

/// No adherence history — the notification-refresh pipeline that
/// `MedicationNotifier.addMedication` drives reads this; faked so the test
/// never reaches real Firestore.
class _FakeAdherenceLogRepository implements AdherenceLogRepository {
  @override
  Stream<List<AdherenceLogModel>> getLogsForDateRange(
    String uid,
    DateTime startDate,
    DateTime endDate,
  ) => Stream.value(const []);

  @override
  Stream<List<AdherenceLogModel>> getLogsForDate(String uid, DateTime date) =>
      Stream.value(const []);

  @override
  Future<void> logDose(AdherenceLogModel log) async {}

  @override
  Future<void> updateLogStatus(
    String uid,
    String logId,
    AdherenceStatus status,
  ) async {}
}

class _FakeMedicationRepository implements MedicationRepository {
  final List<MedicationModel> added = [];
  final List<MedicationModel> updated = [];
  final Map<String, MedicationModel> store = {};

  @override
  Future<MedicationModel> addMedication(MedicationModel medication) async {
    added.add(medication);
    final saved = medication.copyWith(id: 'generated-id');
    store[saved.id] = saved;
    return saved;
  }

  @override
  Stream<List<MedicationModel>> getMedications(String uid) =>
      Stream.value(store.values.toList(growable: false));

  @override
  Future<void> updateMedication(MedicationModel medication) async {
    updated.add(medication);
    store[medication.id] = medication;
  }

  @override
  Future<void> deleteMedication(String uid, String medicationId) async {}

  @override
  Future<void> deactivateMedication(String uid, String medicationId) async {}
}

MedicationModel _stored({
  String dosage = '500 mg',
  MedicationType type = MedicationType.pill,
  MedicationFrequency frequency = MedicationFrequency.twiceDaily,
  List<String> reminderTimes = const ['08:00', '20:00'],
}) => MedicationModel(
  id: 'm1',
  uid: 'u1',
  name: 'Metformin',
  dosage: dosage,
  type: type,
  frequency: frequency,
  reminderTimes: reminderTimes,
  isActive: true,
  createdAt: DateTime(2026, 1, 1),
);

Widget _host({
  required _FakeMedicationRepository repo,
  MedicationModel? medication,
  Brightness brightness = Brightness.dark,
  double textScale = 1.0,
}) => ProviderScope(
  overrides: [
    authStateProvider.overrideWith(
      (ref) => Stream<UserModel?>.value(
        UserModel(uid: 'u1', email: 'a@b.com', createdAt: DateTime(2026, 1, 1)),
      ),
    ),
    medicationRepositoryProvider.overrideWithValue(repo),
    adherenceLogRepositoryProvider.overrideWithValue(
      _FakeAdherenceLogRepository(),
    ),
    hubNowProvider.overrideWithValue(_now),
  ],
  child: MaterialApp(
    theme: ForeSeeMeTheme.light,
    darkTheme: ForeSeeMeTheme.dark,
    themeMode: brightness == Brightness.dark
        ? ThemeMode.dark
        : ThemeMode.light,
    // `AppShell` keeps `notificationRefreshProvider` — and through it the
    // medication stream — subscribed for the whole session. The save path
    // awaits that pipeline, so a bare test host has to play the same role or
    // the save never completes.
    home: Consumer(
      builder: (context, ref, _) {
        ref.watch(medicationsStreamProvider);
        return AddMedicationScreen(medication: medication);
      },
    ),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        padding: const EdgeInsets.only(top: 24, bottom: 8),
      ),
      child: child!,
    ),
  ),
);

/// Pumps the screen on a viewport tall enough that the whole form is built.
///
/// The form is a [ListView], so off-screen sections do not exist to be found;
/// the behaviour tests below are about the form, not the fold, and the layout
/// group covers the real phone sizes.
Future<void> _pumpScreen(
  WidgetTester tester, {
  required _FakeMedicationRepository repo,
  MedicationModel? medication,
}) async {
  tester.view.physicalSize = const Size(400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_host(repo: repo, medication: medication));
  await tester.pump(const Duration(milliseconds: 600));
}

/// Ignores the reports the notification pipeline makes in a test host.
///
/// Saving runs the real notification refresh, and
/// `flutter_local_notifications` has no platform channel here. The product
/// already treats that step as best-effort and *reports* the failure rather
/// than failing the save; swallowing only that library keeps those reports
/// from counting as test failures while every other error stays visible.
/// Installed inside the test body, because `testWidgets` replaces
/// `FlutterError.onError` after `setUp` runs.
void _ignoreNotificationPlatformGap() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.library == 'notifications') return;
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
}

/// Pumps past the save round-trip and the confirmation sheet's transition.
///
/// `pumpAndSettle` is not an option: the screen's ambient loops never stop, so
/// it would time out rather than settle.
Future<void> _settleSave(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// A reminder row's own time readout. The same time is also printed on the
/// preview card's chip, so an unscoped text finder matches twice.
Finder _rowTime(String time) => find.descendant(
  of: find.byType(AddMedReminderRow),
  matching: find.text(time),
);

/// Fills the form the way a user would: name, amount, frequency.
Future<void> _fillForm(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, 'Metformin');
  await tester.pump();
  await tester.enterText(find.byType(TextField).at(1), '500');
  await tester.pump();
  await tester.tap(find.text('Twice'));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('AddMedicationScreen — form', () {
    testWidgets('opens with nothing chosen and four details outstanding', (
      tester,
    ) async {
      await _pumpScreen(tester, repo: _FakeMedicationRepository());

      expect(find.text('Add medication'), findsWidgets);
      expect(find.text('4 DETAILS LEFT'), findsOneWidget);
      expect(find.text('NOT SET'), findsOneWidget);
      // No frequency chosen yet, so the reminder list is still the prompt.
      expect(find.byType(AddMedReminderEmpty), findsOneWidget);
      expect(find.byType(AddMedReminderRow), findsNothing);
    });

    testWidgets('choosing a frequency proposes that many reminder times', (
      tester,
    ) async {
      await _pumpScreen(tester, repo: _FakeMedicationRepository());

      await tester.tap(find.text('Thrice'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(AddMedReminderRow), findsNWidgets(3));
      expect(_rowTime('08:00 AM'), findsOneWidget);
      expect(_rowTime('02:00 PM'), findsOneWidget);
      expect(_rowTime('08:00 PM'), findsOneWidget);
      // At three reminders there is nothing left to add.
      expect(find.byType(AddMedAddTimeButton), findsNothing);
    });

    testWidgets('adding a reminder keeps the times already chosen', (
      tester,
    ) async {
      await _pumpScreen(tester, repo: _FakeMedicationRepository());

      await tester.tap(find.text('Once'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AddMedReminderRow), findsOneWidget);

      await tester.tap(find.text('Add a second reminder'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(AddMedReminderRow), findsNWidgets(2));
      expect(_rowTime('08:00 AM'), findsOneWidget);
      expect(_rowTime('08:00 PM'), findsOneWidget);
    });

    testWidgets('an incomplete form is refused and every gap is named', (
      tester,
    ) async {
      final repo = _FakeMedicationRepository();
      await _pumpScreen(tester, repo: repo);

      await tester.tap(find.text('Add medication').last);
      await tester.pump(const Duration(milliseconds: 400));

      expect(repo.added, isEmpty);
      expect(
        find.text('Add the medication name so you recognise the reminder.'),
        findsOneWidget,
      );
      expect(
        find.text('Enter how much you take at one time, e.g. 500.'),
        findsOneWidget,
      );
      expect(
        find.text('Choose how many times a day you take this.'),
        findsOneWidget,
      );
    });

    testWidgets('Change opens the picker and the chosen time lands on the row', (
      tester,
    ) async {
      await _pumpScreen(tester, repo: _FakeMedicationRepository());

      await tester.tap(find.text('Once'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(_rowTime('08:00 AM'), findsOneWidget);

      await tester.tap(find.text('Change'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AddMedTimePickerSheet), findsOneWidget);
      expect(find.text('Reminder 1 time'), findsOneWidget);

      // The presets are a horizontal rail; the last one starts off-screen.
      await tester.scrollUntilVisible(
        find.text('Bedtime 10:00'),
        120,
        scrollable: find
            .descendant(
              of: find.byType(AddMedTimePickerSheet),
              matching: find.byType(Scrollable),
            )
            .last,
      );
      await tester.tap(find.text('Bedtime 10:00'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Set time'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(AddMedTimePickerSheet), findsNothing);
      expect(_rowTime('10:00 PM'), findsOneWidget);
    });

    testWidgets('a suggestion chip fills the name field', (tester) async {
      await _pumpScreen(tester, repo: _FakeMedicationRepository());

      await tester.tap(find.text('Paracetamol'));
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.controller?.text, 'Paracetamol');
    });
  });

  group('AddMedicationScreen — saving', () {
    testWidgets('a complete form saves the composed record', (tester) async {
      _ignoreNotificationPlatformGap();
      final repo = _FakeMedicationRepository();
      await _pumpScreen(tester, repo: repo);

      await _fillForm(tester);
      expect(find.text('READY TO SAVE'), findsOneWidget);
      expect(find.text('READY'), findsOneWidget);

      await tester.tap(find.text('Add medication').last);
      await _settleSave(tester);

      expect(repo.added, hasLength(1));
      final saved = repo.added.single;
      expect(saved.uid, 'u1');
      expect(saved.name, 'Metformin');
      expect(saved.dosage, '500 mg');
      expect(saved.type, MedicationType.pill);
      expect(saved.frequency, MedicationFrequency.twiceDaily);
      expect(saved.reminderTimes, ['08:00', '20:00']);
      expect(saved.isActive, isTrue);

      // The prototype's confirmation, not a snackbar.
      expect(find.text('Metformin added'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('the unit chosen is what lands in the stored dosage', (
      tester,
    ) async {
      _ignoreNotificationPlatformGap();
      final repo = _FakeMedicationRepository();
      await _pumpScreen(tester, repo: repo);

      await tester.tap(find.text('Syrup'));
      await tester.pump(const Duration(milliseconds: 300));
      await _fillForm(tester);

      await tester.tap(find.text('Add medication').last);
      await _settleSave(tester);

      // Choosing Syrup swaps the unit off mg, as the prototype does.
      expect(repo.added.single.dosage, '500 ml');
      expect(repo.added.single.type, MedicationType.syrup);
    });
  });

  group('AddMedicationScreen — edit mode', () {
    testWidgets('pre-populates from the stored medication', (tester) async {
      await _pumpScreen(
        tester,
        repo: _FakeMedicationRepository(),
        medication: _stored(),
      );

      expect(find.text('Edit medication'), findsWidgets);
      expect(find.text('CHANGES READY'), findsOneWidget);

      final name = tester.widget<TextField>(find.byType(TextField).first);
      final dose = tester.widget<TextField>(find.byType(TextField).at(1));
      expect(name.controller?.text, 'Metformin');
      expect(dose.controller?.text, '500');

      expect(find.byType(AddMedReminderRow), findsNWidgets(2));
      expect(_rowTime('08:00 AM'), findsOneWidget);
      expect(_rowTime('08:00 PM'), findsOneWidget);

      // Archive is offered only when editing.
      expect(find.byType(AddMedArchiveButton), findsOneWidget);
    });

    testWidgets('a dosage stored without a space still round-trips', (
      tester,
    ) async {
      _ignoreNotificationPlatformGap();
      final repo = _FakeMedicationRepository();
      await _pumpScreen(
        tester,
        repo: repo,
        medication: _stored(
          dosage: '850mg',
          frequency: MedicationFrequency.onceDaily,
          reminderTimes: const ['09:00'],
        ),
      );

      final dose = tester.widget<TextField>(find.byType(TextField).at(1));
      expect(dose.controller?.text, '850');

      await tester.tap(find.text('Save changes'));
      await _settleSave(tester);

      expect(repo.updated, hasLength(1));
      expect(repo.updated.single.id, 'm1');
      expect(repo.updated.single.dosage, '850 mg');
      expect(repo.updated.single.reminderTimes, ['09:00']);
      // The record keeps its identity — no duplicate is created.
      expect(repo.added, isEmpty);
    });

    testWidgets('a duplicate reminder time blocks the save and says why', (
      tester,
    ) async {
      final repo = _FakeMedicationRepository();
      await _pumpScreen(
        tester,
        repo: repo,
        medication: _stored(reminderTimes: const ['08:00', '08:00']),
      );

      await tester.tap(find.text('Save changes'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(repo.updated, isEmpty);
      expect(
        find.textContaining('Two reminders share the same time'),
        findsOneWidget,
      );
      expect(find.text('Same time as another reminder'), findsNWidgets(2));
    });
  });

  group('AddMedicationScreen — layout', () {
    // `AppShell` draws `AppBottomNavBar` over this screen, so the footer has to
    // reserve its space; the form scrolls in its own region above it.
    for (final size in const [
      Size(360, 800),
      Size(390, 844),
      Size(430, 932),
    ]) {
      testWidgets(
        'the CTA clears the bottom navigation at '
        '${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            _host(repo: _FakeMedicationRepository(), medication: _stored()),
          );
          await tester.pump(const Duration(milliseconds: 600));

          final cta = tester.getRect(find.byType(AddMedCta));
          // 68px bar + 24px inset + 8px top padding, plus the 8px safe-area
          // bottom the host supplies.
          expect(cta.bottom, lessThan(size.height - 100));
          expect(tester.takeException(), isNull);

          // Nothing overflows once the form is scrolled to its end either.
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, -1400),
          );
          await tester.pump(const Duration(milliseconds: 16));
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('renders in the light theme without overflow', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _host(
          repo: _FakeMedicationRepository(),
          medication: _stored(),
          brightness: Brightness.light,
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));

      expect(tester.takeException(), isNull);
      expect(find.text('Edit medication'), findsWidgets);
    });

    for (final scale in const [1.5, 2.0]) {
      testWidgets('survives a ${scale}x text scale without overflow', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          _host(
            repo: _FakeMedicationRepository(),
            medication: _stored(),
            textScale: scale,
          ),
        );
        await tester.pump(const Duration(milliseconds: 600));
        expect(tester.takeException(), isNull);

        await tester.drag(
          find.byType(Scrollable).first,
          const Offset(0, -1800),
        );
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull);
      });
    }
  });
}
