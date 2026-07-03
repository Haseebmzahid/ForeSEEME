import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/risk_override.dart';
import '../../domain/repositories/risk_override_repository.dart';

/// Firestore implementation of [RiskOverrideRepository].
///
/// Reads/writes the top-level `overrides` collection, keyed by city
/// (`overrides/{city}`). Writes are gated by `firestore.rules` to an `admin`
/// custom claim; reads are allowed to any authenticated user so every risk
/// surface can honestly indicate an active override.
class FirestoreRiskOverrideRepository implements RiskOverrideRepository {
  final FirebaseFirestore _firestore;

  FirestoreRiskOverrideRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Top-level collection holding per-city manual overrides.
  static const String collectionPath = 'overrides';

  DocumentReference<Map<String, dynamic>> _doc(String city) =>
      _firestore.collection(collectionPath).doc(city);

  @override
  Future<RiskOverride?> getOverride(String city) async {
    final snapshot = await _doc(city).get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    return modelFromSnapshotData(data);
  }

  @override
  Future<void> setOverride(RiskOverride override) async {
    // Replace the city's override document wholesale so a new override never
    // inherits a stale `active`/`expiresAt` from a previous one.
    await _doc(override.city).set(override.toJson());
  }

  @override
  Future<void> clearOverride(String city) async {
    // Preserve the audit record; just mark it inactive.
    await _doc(city).set({'active': false}, SetOptions(merge: true));
  }

  /// Maps a raw Firestore document body to a [RiskOverride], tolerating a
  /// [Timestamp] for the date fields (in case a writer stores one instead of the
  /// contract's ISO-8601 string). Pure/static so parsing is unit-testable.
  static RiskOverride modelFromSnapshotData(Map<String, dynamic> data) {
    final normalised = Map<String, dynamic>.from(data);
    for (final key in const ['createdAt', 'expiresAt']) {
      final value = normalised[key];
      if (value is Timestamp) {
        normalised[key] = value.toDate().toUtc().toIso8601String();
      }
    }
    return RiskOverride.fromJson(normalised);
  }
}
