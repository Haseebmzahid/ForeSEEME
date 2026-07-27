// Pure-Dart model for the ML model status shown on the System Monitoring
// Dashboard (Sprint M8.1, SDS FR8.1 "View ML Model Status").
//
// Framework-free, mirroring [RiskEstimateModel]. Deliberately NOT sourced from
// the backend's `GET /health` — the app never calls the FastAPI service
// directly for anything risk-related (ADR-001, GOLDEN_RULES §4). Instead this
// is derived from the most recently written `riskEstimates` document, which the
// app already reads: whichever model version produced the latest estimate is,
// in practice, the currently deployed one.

/// The model version and recency of the most recent risk computation, across
/// all cities.
class ModelStatus {
  /// The `modelVersion` string stamped on the most recent estimate, e.g.
  /// `"rf-1.0.0"`.
  final String version;

  /// When that estimate was generated (UTC) — doubles as "last run time" for
  /// the risk-computation job from the model's point of view.
  final DateTime generatedAt;

  const ModelStatus({required this.version, required this.generatedAt});
}
