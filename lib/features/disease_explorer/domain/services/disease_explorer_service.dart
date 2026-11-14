import '../../../risk/domain/models/risk_estimate_model.dart';
import '../models/disease_risk_estimate.dart';

class DiseaseExplorerService {
  static DiseaseRiskEstimate? estimate(
    RiskEstimateModel? document,
    String disease,
  ) {
    if (document == null) return null;
    for (final entry in document.diseaseEstimates) {
      if (entry.disease == disease) return entry;
    }
    return null;
  }

  /// Only recorded independent estimates; never falls back to dominant history.
  static List<DiseaseRiskEstimate> history(
    List<RiskEstimateModel> documents,
    String city,
    String disease,
  ) {
    final byTime = <DateTime, DiseaseRiskEstimate>{};
    for (final document in documents.where((d) => d.city == city)) {
      final entry = estimate(document, disease);
      if (entry != null) byTime[entry.generatedAt] = entry;
    }
    return List.unmodifiable(
      byTime.values.toList()
        ..sort((a, b) => a.generatedAt.compareTo(b.generatedAt)),
    );
  }
}
