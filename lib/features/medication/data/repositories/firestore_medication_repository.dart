import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/repositories/medication_repository.dart';
import '../../domain/models/medication_model.dart';

/// Firestore implementation of [MedicationRepository].
class FirestoreMedicationRepository implements MedicationRepository {
  final FirebaseFirestore _firestore;

  FirestoreMedicationRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference _medicationsRef(String uid) =>
      _firestore.collection('users').doc(uid).collection('medications');

  @override
  Future<MedicationModel> addMedication(MedicationModel medication) async {
    if (medication.uid.isEmpty) {
      throw ArgumentError('Cannot save medication without a user ID.');
    }

    // If the model already has an ID, use it; otherwise create a new auto-ID ref.
    final docRef = medication.id.isNotEmpty
        ? _medicationsRef(medication.uid).doc(medication.id)
        : _medicationsRef(medication.uid).doc();

    final medicationWithId = medication.copyWith(id: docRef.id);
    await docRef.set(medicationWithId.toJson());
    return medicationWithId;
  }

  @override
  Stream<List<MedicationModel>> getMedications(String uid) {
    // Returns a real-time stream so the check-in screen auto-updates
    return _medicationsRef(uid).snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return MedicationModel.fromJson(
          doc.id,
          doc.data() as Map<String, dynamic>,
        );
      }).toList();
    });
  }

  @override
  Future<void> updateMedication(MedicationModel medication) async {
    await _medicationsRef(
      medication.uid,
    ).doc(medication.id).update(medication.toJson());
  }

  @override
  Future<void> deleteMedication(String uid, String medicationId) async {
    await _medicationsRef(uid).doc(medicationId).delete();
  }

  @override
  Future<void> deactivateMedication(String uid, String medicationId) async {
    await _medicationsRef(uid).doc(medicationId).update({'isActive': false});
  }
}
