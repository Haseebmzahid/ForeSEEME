import '../../../risk/domain/models/risk_attributions.dart';

const diseaseNames = {
  'dengue': 'Dengue',
  'smog': 'Smog',
  'influenza': 'Influenza',
};

/// Valid independent predictions only. Missing/invalid entries never become Low.
class DiseaseRiskEstimate {
  final String disease;
  final String riskLevel;
  final double confidence;
  final Map<String, double> probabilities;
  final String modelVersion;
  final DateTime generatedAt;
  final bool lowConfidence;
  final RiskAttributions? attributions;

  const DiseaseRiskEstimate({
    required this.disease,
    required this.riskLevel,
    required this.confidence,
    required this.probabilities,
    required this.modelVersion,
    required this.generatedAt,
    required this.lowConfidence,
    this.attributions,
  });

  String get displayName => diseaseNames[disease]!;

  @override
  bool operator ==(Object other) =>
      other is DiseaseRiskEstimate &&
      other.disease == disease &&
      other.riskLevel == riskLevel &&
      other.confidence == confidence &&
      other.modelVersion == modelVersion &&
      other.generatedAt == generatedAt &&
      other.lowConfidence == lowConfidence &&
      other.attributions == attributions &&
      const [
        'Low',
        'Medium',
        'High',
      ].every((key) => other.probabilities[key] == probabilities[key]);

  @override
  int get hashCode => Object.hash(
    disease,
    riskLevel,
    confidence,
    modelVersion,
    generatedAt,
    lowConfidence,
    attributions,
    probabilities['Low'],
    probabilities['Medium'],
    probabilities['High'],
  );

  static DiseaseRiskEstimate? tryParse(
    Object? raw, {
    required String modelVersion,
    required DateTime generatedAt,
  }) {
    if (raw is! Map || raw['status'] != 'available') return null;
    final disease = raw['disease'];
    final level = raw['riskLevel'];
    final confidence = raw['confidence'];
    final probabilities = raw['probabilities'];
    final timestamp = raw['generatedAt'];
    final time = timestamp is String
        ? DateTime.tryParse(timestamp)?.toUtc()
        : null;
    const levels = ['Low', 'Medium', 'High'];
    if (!diseaseNames.containsKey(disease) ||
        !levels.contains(level) ||
        confidence is! num ||
        !confidence.isFinite ||
        confidence < 0 ||
        confidence > 1 ||
        raw['modelVersion'] != modelVersion ||
        modelVersion.isEmpty ||
        time != generatedAt.toUtc() ||
        raw['lowConfidence'] is! bool ||
        probabilities is! Map ||
        probabilities.length != 3) {
      return null;
    }
    final values = <String, double>{};
    for (final key in levels) {
      final value = probabilities[key];
      if (value is! num || !value.isFinite || value < 0 || value > 1) {
        return null;
      }
      values[key] = value.toDouble();
    }
    if ((values.values.reduce((a, b) => a + b) - 1).abs() > 0.00001 ||
        (values[level]! - confidence).abs() > 0.00001 ||
        values.values.any((v) => v > confidence + 0.00001)) {
      return null;
    }
    RiskAttributions? attribution;
    final a = raw['attributions'];
    if (a is Map<String, dynamic> &&
        _validAttribution(a) &&
        a['disease'] == disease &&
        a['predictedClass'] == level &&
        a['modelVersion'] == modelVersion) {
      try {
        final parsed = RiskAttributions.fromJson(a);
        if ((parsed.confidenceRationale.confidence - confidence).abs() <=
                0.0001 &&
            parsed.topContributors.every(
              (c) =>
                  c.feature.isNotEmpty &&
                  c.value.isFinite &&
                  c.contribution.isFinite &&
                  c.magnitude.isFinite,
            )) {
          attribution = parsed;
        }
      } catch (_) {
        // A malformed explanation does not invalidate a valid classification.
      }
    }
    return DiseaseRiskEstimate(
      disease: disease as String,
      riskLevel: level as String,
      confidence: confidence.toDouble(),
      probabilities: Map.unmodifiable(values),
      modelVersion: modelVersion,
      generatedAt: time!,
      lowConfidence: raw['lowConfidence'] as bool,
      attributions: attribution,
    );
  }

  static bool _validAttribution(Map<String, dynamic> a) {
    final contributors = a['topContributors'];
    final rationale = a['confidenceRationale'];
    if (a['method'] != 'tree_path_contributions' ||
        contributors is! List ||
        contributors.isEmpty ||
        rationale is! Map ||
        rationale['confidence'] is! num ||
        !(rationale['confidence'] as num).isFinite) {
      return false;
    }
    return contributors.every(
      (c) =>
          c is Map &&
          c['feature'] is String &&
          (c['feature'] as String).isNotEmpty &&
          const ['increases', 'decreases'].contains(c['direction']) &&
          const [
            'value',
            'contribution',
            'magnitude',
          ].every((key) => c[key] is num && (c[key] as num).isFinite),
    );
  }

  static List<DiseaseRiskEstimate> parseDocument(Map<String, dynamic> json) {
    final raw = json['diseaseEstimates'];
    final version = json['modelVersion'];
    final timestamp = json['generatedAt'];
    final time = timestamp is String ? DateTime.tryParse(timestamp) : null;
    if (raw is! List || version is! String || time == null) return const [];
    final result = <String, DiseaseRiskEstimate>{};
    final duplicates = <String>{};
    for (final value in raw) {
      final parsed = tryParse(value, modelVersion: version, generatedAt: time);
      if (parsed == null) continue;
      if (result.containsKey(parsed.disease)) {
        duplicates.add(parsed.disease);
      }
      result[parsed.disease] = parsed;
    }
    for (final key in duplicates) {
      result.remove(key);
    }
    return List.unmodifiable(result.values);
  }

  Map<String, dynamic> toJson() => {
    'disease': disease,
    'displayName': displayName,
    'status': 'available',
    'riskLevel': riskLevel,
    'confidence': confidence,
    'probabilities': probabilities,
    'modelVersion': modelVersion,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'lowConfidence': lowConfidence,
    if (attributions != null) 'attributions': attributions!.toJson(),
  };
}
