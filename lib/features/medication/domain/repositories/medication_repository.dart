import '../models/medication_model.dart';

/// Abstract interface for Medication data operations.
/// Defines pure data operations without business logic.
abstract class MedicationRepository {
  /// Adds a new medication for a user.
  Future<MedicationModel> addMedication(MedicationModel medication);

  /// Retrieves a real-time stream of all medications for a user.
  Stream<List<MedicationModel>> getMedications(String uid);

  /// Updates an existing medication.
  Future<void> updateMedication(MedicationModel medication);

  /// Deletes a medication permanently.
  Future<void> deleteMedication(String uid, String medicationId);

  /// Deactivates a medication instead of deleting it.
  Future<void> deactivateMedication(String uid, String medicationId);
}
