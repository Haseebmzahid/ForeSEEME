import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';

Map<String, dynamic> independent(
  String disease,
  String level, {
  DateTime? at,
}) => {
  'disease': disease,
  'status': 'available',
  'riskLevel': level,
  'confidence': .8,
  'probabilities': {
    for (final key in ['Low', 'Medium', 'High']) key: key == level ? .8 : .1,
  },
  'modelVersion': 'rf-1.0.0',
  'lowConfidence': false,
  'generatedAt': (at ?? DateTime.utc(2026, 11, 1)).toIso8601String(),
};

Map<String, dynamic> document({
  String city = 'Lahore',
  DateTime? at,
  bool legacy = false,
}) => {
  'city': city,
  'riskLevel': 'High',
  'disease': 'Smog',
  'confidence': .8,
  'temperature': 25,
  'humidity': 50,
  'aqi': 100,
  'generatedAt': (at ?? DateTime.utc(2026, 11, 1)).toIso8601String(),
  'modelVersion': 'rf-1.0.0',
  if (!legacy)
    'diseaseEstimates': [
      independent('dengue', 'Medium', at: at),
      independent('smog', 'High', at: at),
      independent('influenza', 'Low', at: at),
    ],
};

RiskEstimateModel estimate({
  String city = 'Lahore',
  DateTime? at,
  bool legacy = false,
}) => RiskEstimateModel.fromJson(document(city: city, at: at, legacy: legacy));
