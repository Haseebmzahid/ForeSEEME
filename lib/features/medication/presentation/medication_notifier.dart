import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/local_notification_service.dart';
import '../domain/models/medication_model.dart';
import '../domain/repositories/medication_repository.dart';
import '../data/repositories/firestore_medication_repository.dart';

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

  /// Validates the form data, saves medication to Firestore,
  /// and schedules local notifications.
  Future<MedicationModel> addMedication(MedicationModel medication) async {
    state = const AsyncValue.loading();
    try {
      final repository = ref.read(medicationRepositoryProvider);

      // Save to Firestore
      final savedMedication = await repository.addMedication(medication);

      try {
        // Schedule local notifications after successful Firestore write.
        await _scheduleNotifications(savedMedication);
      } catch (e, st) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: e,
            stack: st,
            library: 'medication',
            context: ErrorDescription('scheduling medication notifications'),
          ),
        );
      }

      state = const AsyncValue.data(null);
      return savedMedication;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      Error.throwWithStackTrace(e, st);
    }
  }

  /// Triggers notification scheduling
  Future<void> _scheduleNotifications(MedicationModel medication) {
    return LocalNotificationService.scheduleMedicationRemindersForMedication(
      medication,
    );
  }
}
