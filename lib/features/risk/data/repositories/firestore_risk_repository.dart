import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/risk_estimate_model.dart';
import '../../domain/repositories/risk_repository.dart';

/// Firestore implementation of [RiskRepository].
///
/// Reads (never writes) the top-level `riskEstimates` collection; the collection
/// is populated exclusively by the scheduled backend job (ADR-001 / ADR-002).
class FirestoreRiskRepository implements RiskRepository {
  final FirebaseFirestore _firestore;

  FirestoreRiskRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Top-level collection holding per-city risk estimates.
  static const String collectionPath = 'riskEstimates';

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(collectionPath);

  @override
  Future<RiskEstimateModel?> getLatestRiskForCity(String city) async {
    // Latest estimate = highest `generatedAt` for the city. `generatedAt` is an
    // ISO-8601 UTC string (frozen contract), which sorts correctly as a string.
    //
    // Offline behaviour: `get()` uses the default `Source.serverAndCache`, and
    // Firestore's local persistence is enabled by default on mobile — so when
    // the device is offline this transparently returns the last cached estimate
    // (a `data` state). It only throws when offline *and* nothing is cached for
    // the query, which surfaces upstream as an `AsyncError` (offline/error UI).
    final snapshot = await _collection
        .where('city', isEqualTo: city)
        .orderBy('generatedAt', descending: true)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;
    return modelFromSnapshotData(snapshot.docs.first.data());
  }

  @override
  Future<List<RiskEstimateModel>> getRiskHistory(
    String city, {
    int weeks = 6,
  }) async {
    // Trailing window: the [weeks] most recent estimates for the city, newest
    // first. Same read shape as [getLatestRiskForCity] (city equality +
    // generatedAt order), so it uses the same composite index; purely additive
    // and read-only — it never touches the batch job's write path.
    final snapshot = await _collection
        .where('city', isEqualTo: city)
        .orderBy('generatedAt', descending: true)
        .limit(weeks)
        .get();

    return snapshot.docs
        .map((doc) => modelFromSnapshotData(doc.data()))
        .toList();
  }

  @override
  Future<List<RiskEstimateModel>> getLatestRiskAllCities(
    List<String> cities,
  ) async {
    // Latest-per-city via parallel single-city reads (each uses the same
    // composite index). Exact and bounded (one query per city), avoiding an
    // unbounded collection scan. Cities without an estimate drop out.
    final results = await Future.wait(cities.map(getLatestRiskForCity));
    return results.whereType<RiskEstimateModel>().toList();
  }

  /// Maps a raw Firestore document body to a [RiskEstimateModel].
  ///
  /// Normalises `generatedAt` so a Firestore [Timestamp] (if a writer stores one
  /// instead of the contract's ISO-8601 string) still parses, keeping the model
  /// framework-free. Extracted as a pure, static function so document parsing is
  /// unit-testable without a live Firestore.
  static RiskEstimateModel modelFromSnapshotData(Map<String, dynamic> data) {
    final normalised = Map<String, dynamic>.from(data);
    final generatedAt = normalised['generatedAt'];
    if (generatedAt is Timestamp) {
      normalised['generatedAt'] = generatedAt
          .toDate()
          .toUtc()
          .toIso8601String();
    }
    return RiskEstimateModel.fromJson(normalised);
  }
}
