import '../../domain/models/risk_estimate_model.dart';
import '../../domain/repositories/risk_repository.dart';

/// In-memory [RiskRepository] for development and tests.
///
/// Returns deterministic sample data covering all three risk levels
/// (Low / Medium / High). Inject custom data via [seed]; unknown cities
/// resolve to `null` (mirroring "no estimate yet" from Firestore).
class FakeRiskRepository implements RiskRepository {
  FakeRiskRepository({Map<String, RiskEstimateModel>? seed})
    : _byCity = seed ?? _defaultSeed();

  final Map<String, RiskEstimateModel> _byCity;

  @override
  Future<RiskEstimateModel?> getLatestRiskForCity(String city) async {
    return _byCity[city];
  }

  static Map<String, RiskEstimateModel> _defaultSeed() {
    final generatedAt = DateTime.utc(2026, 6, 28);
    return {
      'Lahore': RiskEstimateModel(
        city: 'Lahore',
        riskLevel: RiskLevel.high,
        disease: 'Dengue',
        confidence: 0.91,
        temperature: 38.0,
        humidity: 65.0,
        aqi: 210.0,
        generatedAt: generatedAt,
        modelVersion: 'stub-0.0.0',
      ),
      'Karachi': RiskEstimateModel(
        city: 'Karachi',
        riskLevel: RiskLevel.medium,
        disease: 'Heat-Related Illness',
        confidence: 0.68,
        temperature: 33.0,
        humidity: 55.0,
        aqi: 120.0,
        generatedAt: generatedAt,
        modelVersion: 'stub-0.0.0',
      ),
      'Islamabad': RiskEstimateModel(
        city: 'Islamabad',
        riskLevel: RiskLevel.low,
        disease: 'Respiratory Illness',
        confidence: 0.55,
        temperature: 26.0,
        humidity: 45.0,
        aqi: 60.0,
        generatedAt: generatedAt,
        modelVersion: 'stub-0.0.0',
        lowConfidence: true,
      ),
    };
  }
}
