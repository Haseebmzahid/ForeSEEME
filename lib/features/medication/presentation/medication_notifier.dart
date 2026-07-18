import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/local_notification_service.dart';
import '../domain/models/medication_model.dart';
import '../domain/repositories/medication_repository.dart';
import '../data/repositories/firestore_medication_repository.dart';
import 'notification_refresh_provider.dart';

/// Provider for the MedicationRepository
final medicationRepositoryProvider = Provider<MedicationRepository>((ref) {
  return FirestoreMedicationRepository();
});

/// Provider for the MedicationNotifier
final medicationNotifierProvider =
    AsyncNotifierProvider<MedicationNotifier, void>(() {
      return MedicationNotifier();
    });

class MedicationNotifier extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  /// Validates the form data, saves medication to Firestore, and schedules
  /// its coaching-aware notifications through [MedicationNotificationOrchestrator]
  /// (via [refreshMedicationNotifications]) — same pipeline used on app open
  /// and after a check-in, so the very first reminder already carries
  /// contextual `MedicationCoachingService` content and a category-based
  /// deep-link payload. Never throws from the scheduling step: it's
  /// best-effort and already reports its own errors.
  Future<MedicationModel> addMedication(MedicationModel medication) async {
    state = const AsyncValue.loading();
    try {
      final repository = ref.read(medicationRepositoryProvider);

      // Save to Firestore
      final savedMedication = await repository.addMedication(medication);

      await refreshMedicationNotifications(ref.container, savedMedication.uid);

      state = const AsyncValue.data(null);
      return savedMedication;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      Error.throwWithStackTrace(e, st);
    }
  }

  /// Validates the form data, updates the medication in Firestore, and
  /// reschedules its notifications through the same coaching pipeline as
  /// [addMedication].
  Future<MedicationModel> updateMedication(MedicationModel medication) async {
    state = const AsyncValue.loading();
    try {
      final repository = ref.read(medicationRepositoryProvider);

      await repository.updateMedication(medication);

      await refreshMedicationNotifications(ref.container, medication.uid);

      state = const AsyncValue.data(null);
      return medication;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      Error.throwWithStackTrace(e, st);
    }
  }

  /// Archives (soft-deletes) a medication: marks it inactive in Firestore and
  /// cancels its pending reminders. Adherence history is preserved.
  Future<void> archiveMedication(String uid, String medicationId) async {
    state = const AsyncValue.loading();
    try {
      final repository = ref.read(medicationRepositoryProvider);

      await repository.deactivateMedication(uid, medicationId);

      try {
        await LocalNotificationService.cancelMedicationReminders(
          medicationId,
        );
      } catch (e, st) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: e,
            stack: st,
            library: 'medication',
            context: ErrorDescription(
              'cancelling reminders for archived medication',
            ),
          ),
        );
      }

      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      Error.throwWithStackTrace(e, st);
    }
  }
}
