import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_log_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/medication_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/enums/medication_enums.dart';
import 'package:fyp_foreseeme/features/medication/domain/repositories/adherence_log_repository.dart';
import 'package:fyp_foreseeme/features/medication/data/repositories/firestore_adherence_log_repository.dart';
import 'package:fyp_foreseeme/features/medication/presentation/medication_notifier.dart';

/// Provider for the AdherenceLogRepository
final adherenceLogRepositoryProvider = Provider<AdherenceLogRepository>((ref) {
  return FirestoreAdherenceLogRepository();
});

/// Stream of a user's medications
final medicationsStreamProvider = StreamProvider<List<MedicationModel>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null || user.uid.isEmpty) return Stream.value(const []);

  final repository = ref.watch(medicationRepositoryProvider);
  return repository.getMedications(user.uid);
});

/// Stream of adherence logs for a specific date
final adherenceLogsStreamProvider =
    StreamProvider.family<List<AdherenceLogModel>, DateTime>((ref, date) {
      final user = ref.watch(authStateProvider).value;
      if (user == null || user.uid.isEmpty) return Stream.value(const []);

      final repository = ref.watch(adherenceLogRepositoryProvider);
      return repository.getLogsForDate(user.uid, date);
    });

/// Notifier handling the action updates
final adherenceNotifierProvider =
    AsyncNotifierProvider<AdherenceNotifier, void>(() {
      return AdherenceNotifier();
    });

class AdherenceNotifier extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  /// Deterministic log ID generator matching medication and time securely
  String generateLogId(String medicationId, DateTime date, String timeString) {
    final normalizedDate = _dateOnly(date);
    final dString =
        '${normalizedDate.year.toString().padLeft(4, '0')}-${normalizedDate.month.toString().padLeft(2, '0')}-${normalizedDate.day.toString().padLeft(2, '0')}';
    final tString = timeString.replaceAll(':', '');
    return '${medicationId}_${dString}_$tString';
  }

  /// Updates or creates the adherence log for a specific dose
  Future<void> updateStatus({
    required MedicationModel medication,
    required DateTime date,
    required String timeString,
    required AdherenceStatus status,
  }) async {
    state = const AsyncValue.loading();
    try {
      final user = ref.read(authStateProvider).value;
      if (user == null) throw Exception('User not authenticated');

      final repo = ref.read(adherenceLogRepositoryProvider);
      final normalizedDate = _dateOnly(date);
      final logId = generateLogId(medication.id, normalizedDate, timeString);

      // Create model representing the dose event
      final now = DateTime.now();
      final log = AdherenceLogModel(
        id: logId,
        medicationId: medication.id,
        uid: user.uid,
        scheduledTime: timeString,
        date: normalizedDate,
        selectedDate: normalizedDate,
        status: status,
        confirmedAt: status == AdherenceStatus.pending ? null : now,
        timestamp: now,
      );

      // Write directly (creates or overwrites the deterministic ID)
      await repo.logDose(log);

      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      Error.throwWithStackTrace(e, st);
    }
  }
}
