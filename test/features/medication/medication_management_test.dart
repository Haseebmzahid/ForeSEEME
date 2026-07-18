import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/auth/domain/models/user_model.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/medication/data/repositories/firestore_medication_repository.dart';
import 'package:fyp_foreseeme/features/medication/domain/enums/medication_enums.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_log_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/medication_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/repositories/adherence_log_repository.dart';
import 'package:fyp_foreseeme/features/medication/domain/repositories/medication_repository.dart';
import 'package:fyp_foreseeme/features/medication/presentation/adherence_notifier.dart';
import 'package:fyp_foreseeme/features/medication/presentation/medication_notifier.dart';
import 'package:fyp_foreseeme/features/medication/presentation/widgets/medication_detail_sheet.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

UserModel _testUser([String uid = 'user-1']) =>
    UserModel(uid: uid, email: 'a@b.com', createdAt: DateTime.utc(2026, 1, 1));

/// No adherence history — the notification-refresh pipeline (triggered by
/// `MedicationNotifier.addMedication`/`updateMedication`) reads this via
/// `adherenceLogRepositoryProvider`; faked here so it never touches real
/// Firestore in these repository-fake-backed tests.
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

MedicationModel _medication({
  String id = '',
  String uid = 'user-1',
  String name = 'Paracetamol',
  String dosage = '500mg',
  MedicationType type = MedicationType.pill,
  MedicationFrequency frequency = MedicationFrequency.onceDaily,
  List<String> reminderTimes = const ['08:00'],
  bool isActive = true,
  DateTime? createdAt,
}) => MedicationModel(
  id: id,
  uid: uid,
  name: name,
  dosage: dosage,
  type: type,
  frequency: frequency,
  reminderTimes: reminderTimes,
  isActive: isActive,
  createdAt: createdAt ?? DateTime.utc(2026, 1, 1),
);

class _FakeMedicationRepository implements MedicationRepository {
  final Map<String, MedicationModel> store = {};
  final List<String> deactivatedIds = [];
  final List<String> deletedIds = [];

  @override
  Future<MedicationModel> addMedication(MedicationModel medication) async {
    final saved = medication.id.isEmpty
        ? medication.copyWith(id: 'generated-id')
        : medication;
    store[saved.id] = saved;
    return saved;
  }

  @override
  Stream<List<MedicationModel>> getMedications(String uid) {
    return Stream.value(
      store.values.where((m) => m.uid == uid).toList(growable: false),
    );
  }

  @override
  Future<void> updateMedication(MedicationModel medication) async {
    store[medication.id] = medication;
  }

  @override
  Future<void> deleteMedication(String uid, String medicationId) async {
    deletedIds.add(medicationId);
    store.remove(medicationId);
  }

  @override
  Future<void> deactivateMedication(String uid, String medicationId) async {
    deactivatedIds.add(medicationId);
    final existing = store[medicationId];
    if (existing != null) {
      store[medicationId] = existing.copyWith(isActive: false);
    }
  }
}

void main() {
  // ── Firestore repository round-trip (real impl, fake backend) ──────────────
  group('FirestoreMedicationRepository', () {
    test(
      'add → update → archive → delete lifecycle preserves record identity',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = FirestoreMedicationRepository(firestore: firestore);

        final saved = await repo.addMedication(
          _medication(name: 'Ibuprofen', dosage: '200mg'),
        );
        expect(saved.id, isNotEmpty);
        expect(saved.isActive, isTrue);

        // Edit: same id, no duplicate record created.
        final edited = saved.copyWith(
          dosage: '400mg',
          frequency: MedicationFrequency.twiceDaily,
          reminderTimes: ['08:00', '20:00'],
        );
        await repo.updateMedication(edited);

        var all = await repo.getMedications('user-1').first;
        expect(all, hasLength(1));
        expect(all.single.id, saved.id);
        expect(all.single.dosage, '400mg');
        expect(all.single.frequency, MedicationFrequency.twiceDaily);
        expect(all.single.reminderTimes, ['08:00', '20:00']);

        // Archive: soft delete — record stays, only isActive flips.
        await repo.deactivateMedication('user-1', saved.id);
        all = await repo.getMedications('user-1').first;
        expect(all, hasLength(1));
        expect(all.single.id, saved.id);
        expect(all.single.isActive, isFalse);

        // Permanent delete: exposed by the repository but unused by the UI
        // (archiving is the only deletion path Sprint M2.1 wires up).
        await repo.deleteMedication('user-1', saved.id);
        all = await repo.getMedications('user-1').first;
        expect(all, isEmpty);
      },
    );
  });

  // ── MedicationNotifier (fake repo — no Firestore or platform channels) ─────
  group('MedicationNotifier', () {
    test('updateMedication persists edits without creating a duplicate', () async {
      final repo = _FakeMedicationRepository();
      repo.store['m1'] = _medication(id: 'm1', name: 'Paracetamol', dosage: '500mg');

      final container = ProviderContainer(
        overrides: [
          medicationRepositoryProvider.overrideWithValue(repo),
          // updateMedication now routes through the notification-refresh
          // pipeline directly (MedicationNotificationOrchestrator) — these
          // keep it off real Firebase/Firestore in this repo-fake test.
          authStateProvider.overrideWith((ref) => Stream.value(_testUser())),
          adherenceLogRepositoryProvider.overrideWithValue(
            _FakeAdherenceLogRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);
      // Keeps medicationsStreamProvider's subscription pumping for
      // `container.read(...future)` below — in the real app `AppShell`'s
      // permanent `ref.listen` (notificationRefreshProvider) plays this
      // role; a bare test container has nothing else doing so.
      container.listen(medicationsStreamProvider, (previous, next) {});

      final updated = repo.store['m1']!.copyWith(
        name: 'Paracetamol Extra',
        dosage: '650mg',
      );
      await container
          .read(medicationNotifierProvider.notifier)
          .updateMedication(updated);

      expect(repo.store, hasLength(1)); // no duplicate record
      expect(repo.store['m1']!.name, 'Paracetamol Extra');
      expect(repo.store['m1']!.dosage, '650mg');
    });

    test(
      'archiveMedication soft-deletes via deactivateMedication (history preserved)',
      () async {
        final repo = _FakeMedicationRepository();
        repo.store['m2'] = _medication(id: 'm2', uid: 'user-1');

        final container = ProviderContainer(
          overrides: [medicationRepositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);

        await container
            .read(medicationNotifierProvider.notifier)
            .archiveMedication('user-1', 'm2');

        expect(repo.deactivatedIds, contains('m2'));
        expect(repo.deletedIds, isEmpty); // never permanently deleted
        expect(repo.store['m2'], isNotNull); // record still exists
        expect(repo.store['m2']!.isActive, isFalse);
      },
    );
  });

  // ── Medication Detail Bottom Sheet ──────────────────────────────────────────
  group('MedicationDetailSheet', () {
    testWidgets('shows the medication details and Active status', (tester) async {
      final medication = _medication(
        name: 'Metformin',
        dosage: '850mg',
        frequency: MedicationFrequency.twiceDaily,
        reminderTimes: const ['08:00', '20:00'],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MedicationDetailSheet(
              medication: medication,
              onEdit: () {},
              onArchive: () {},
            ),
          ),
        ),
      );

      expect(find.text('Metformin'), findsOneWidget);
      expect(find.text('850mg'), findsOneWidget);
      expect(find.text('Twice daily'), findsOneWidget);
      expect(find.textContaining('8:00 AM'), findsOneWidget);
      expect(find.textContaining('8:00 PM'), findsOneWidget);
      expect(find.text('ACTIVE'), findsOneWidget);
    });

    testWidgets('tapping Edit Medication invokes onEdit', (tester) async {
      var editTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MedicationDetailSheet(
              medication: _medication(),
              onEdit: () => editTapped = true,
              onArchive: () {},
            ),
          ),
        ),
      );

      await tester.tap(find.text('Edit Medication'));
      await tester.pumpAndSettle();

      expect(editTapped, isTrue);
    });

    testWidgets('tapping Archive Medication invokes onArchive', (tester) async {
      var archiveTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MedicationDetailSheet(
              medication: _medication(),
              onEdit: () {},
              onArchive: () => archiveTapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Archive Medication'));
      await tester.pumpAndSettle();

      expect(archiveTapped, isTrue);
    });

    testWidgets('tapping Cancel dismisses the sheet without side effects', (
      tester,
    ) async {
      var editTapped = false;
      var archiveTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => MedicationDetailSheet(
                    medication: _medication(),
                    onEdit: () => editTapped = true,
                    onArchive: () => archiveTapped = true,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(MedicationDetailSheet), findsNothing);
      expect(editTapped, isFalse);
      expect(archiveTapped, isFalse);
    });
  });
}
