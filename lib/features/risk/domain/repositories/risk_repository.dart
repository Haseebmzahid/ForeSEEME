import '../models/risk_estimate_model.dart';

/// Abstract interface for risk-data read operations.
///
/// Defines pure data operations without business logic, mirroring
/// [MedicationRepository] / [AuthRepository]. Per ADR-001 the app reads risk
/// ONLY from the Firestore `riskEstimates` collection — this interface never
/// exposes the internal FastAPI `/predict` endpoint.
abstract class RiskRepository {
  /// Returns the most recent [RiskEstimateModel] for [city], or `null` if no
  /// estimate exists for that city.
  Future<RiskEstimateModel?> getLatestRiskForCity(String city);

  /// Returns up to [weeks] most-recent estimates for [city], newest first.
  ///
  /// Additive read for the trend indicator (Sprint 3, Prompt 3): it only reads
  /// the same `riskEstimates` collection and never touches the write path. May
  /// return fewer than [weeks] (or an empty list) when little history exists.
  Future<List<RiskEstimateModel>> getRiskHistory(String city, {int weeks});

  /// Returns the latest estimate for each of [cities] that has one.
  ///
  /// Additive read for the national risk map (Sprint 3, Prompt 4): latest-per-
  /// city, read-only. Cities without an estimate are simply omitted, so the
  /// result has at most `cities.length` entries (order not guaranteed).
  Future<List<RiskEstimateModel>> getLatestRiskAllCities(List<String> cities);
}
