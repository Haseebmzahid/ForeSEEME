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
}
