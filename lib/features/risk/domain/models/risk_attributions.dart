// Pure-Dart models for the ADDITIVE explainability payload on a risk estimate.
//
// This file is framework-free (no `package:flutter`, no `cloud_firestore`),
// mirroring `risk_estimate_model.dart`. It is the Dart mirror of the backend
// `attributions` object (Sprint 5, Prompt 5 — see docs/RISK_SCHEMA.md), which is
// an EXACT, additive decomposition of the model's own probability. These models
// only carry and expose those stored values; they never recompute, re-rank, or
// reinterpret them (the backend is the single source of truth). `topContributors`
// is already ranked by the backend and is consumed in the order given.
//
// The whole payload is OPTIONAL: documents written before Sprint 5 do not carry
// it, so `RiskEstimateModel.attributions` is nullable and every reader must
// tolerate its absence.

/// Whether a feature pushed the predicted-class probability up or down.
///
/// Mirrors the backend `direction` string. The enum is icon-free (the widget
/// maps it to an icon), keeping this domain model framework-free.
enum ContributionDirection {
  increases,
  decreases;

  /// Defensive parse — an unknown/absent value defaults to [increases] so the
  /// UI never crashes on an unexpected payload.
  static ContributionDirection fromJson(String? value) =>
      value == 'decreases'
      ? ContributionDirection.decreases
      : ContributionDirection.increases;

  String toJson() => name;
}

/// Qualitative confidence bucket, derived by the backend from the margin and
/// tree agreement. Presentation only labels/icons it — it is never recomputed here.
enum ConfidenceStrength {
  strong,
  moderate,
  weak;

  /// Defensive parse — an unknown/absent value defaults to [weak] (the most
  /// cautious framing).
  static ConfidenceStrength fromJson(String? value) => switch (value) {
    'strong' => ConfidenceStrength.strong,
    'moderate' => ConfidenceStrength.moderate,
    _ => ConfidenceStrength.weak,
  };

  String toJson() => name;
}

/// One feature's genuine, signed contribution to the predicted risk class.
///
/// [contribution] is the exact additive increment the backend attributed to this
/// feature; [magnitude] is its absolute value (the backend's ranking key);
/// [value] is the real-unit feature value the model saw.
class FeatureContribution {
  final String feature;
  final double contribution;
  final double magnitude;
  final ContributionDirection direction;
  final double value;

  const FeatureContribution({
    required this.feature,
    required this.contribution,
    required this.magnitude,
    required this.direction,
    required this.value,
  });

  factory FeatureContribution.fromJson(Map<String, dynamic> json) {
    return FeatureContribution(
      feature: (json['feature'] as String?) ?? '',
      contribution: (json['contribution'] as num?)?.toDouble() ?? 0.0,
      magnitude: (json['magnitude'] as num?)?.toDouble() ?? 0.0,
      direction: ContributionDirection.fromJson(json['direction'] as String?),
      value: (json['value'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
    'feature': feature,
    'contribution': contribution,
    'magnitude': magnitude,
    'direction': direction.toJson(),
    'value': value,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FeatureContribution &&
          other.feature == feature &&
          other.contribution == contribution &&
          other.magnitude == magnitude &&
          other.direction == direction &&
          other.value == value;

  @override
  int get hashCode =>
      Object.hash(feature, contribution, magnitude, direction, value);
}

/// Why confidence is high or low — the backend's class-distribution rationale.
class ConfidenceRationale {
  final double confidence;
  final String predictedClass;
  final String runnerUpClass;
  final double runnerUpConfidence;
  final double margin;
  final double agreement;
  final ConfidenceStrength strength;
  final bool lowConfidence;

  const ConfidenceRationale({
    required this.confidence,
    required this.predictedClass,
    required this.runnerUpClass,
    required this.runnerUpConfidence,
    required this.margin,
    required this.agreement,
    required this.strength,
    required this.lowConfidence,
  });

  factory ConfidenceRationale.fromJson(Map<String, dynamic> json) {
    return ConfidenceRationale(
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      predictedClass: (json['predictedClass'] as String?) ?? '',
      runnerUpClass: (json['runnerUpClass'] as String?) ?? '',
      runnerUpConfidence: (json['runnerUpConfidence'] as num?)?.toDouble() ?? 0.0,
      margin: (json['margin'] as num?)?.toDouble() ?? 0.0,
      agreement: (json['agreement'] as num?)?.toDouble() ?? 0.0,
      strength: ConfidenceStrength.fromJson(json['strength'] as String?),
      lowConfidence: (json['lowConfidence'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'confidence': confidence,
    'predictedClass': predictedClass,
    'runnerUpClass': runnerUpClass,
    'runnerUpConfidence': runnerUpConfidence,
    'margin': margin,
    'agreement': agreement,
    'strength': strength.toJson(),
    'lowConfidence': lowConfidence,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConfidenceRationale &&
          other.confidence == confidence &&
          other.predictedClass == predictedClass &&
          other.runnerUpClass == runnerUpClass &&
          other.runnerUpConfidence == runnerUpConfidence &&
          other.margin == margin &&
          other.agreement == agreement &&
          other.strength == strength &&
          other.lowConfidence == lowConfidence;

  @override
  int get hashCode => Object.hash(
    confidence,
    predictedClass,
    runnerUpClass,
    runnerUpConfidence,
    margin,
    agreement,
    strength,
    lowConfidence,
  );
}

/// The genuine, model-derived explanation stored on a risk estimate.
///
/// A faithful mirror of the backend `attributions` object. Additive & optional
/// (see file header). Readers render [topContributors] in the given (ranked)
/// order and never re-order or re-derive them.
class RiskAttributions {
  final String method;
  final String modelVersion;
  final String disease;
  final String predictedClass;
  final double baseValue;
  final List<FeatureContribution> topContributors;
  final ConfidenceRationale confidenceRationale;

  const RiskAttributions({
    required this.method,
    required this.modelVersion,
    required this.disease,
    required this.predictedClass,
    required this.baseValue,
    required this.topContributors,
    required this.confidenceRationale,
  });

  factory RiskAttributions.fromJson(Map<String, dynamic> json) {
    final contributors = (json['topContributors'] as List<dynamic>?)
        ?.whereType<Map<String, dynamic>>()
        .map(FeatureContribution.fromJson)
        .toList(growable: false);
    final rationale = json['confidenceRationale'];
    return RiskAttributions(
      method: (json['method'] as String?) ?? '',
      modelVersion: (json['modelVersion'] as String?) ?? '',
      disease: (json['disease'] as String?) ?? '',
      predictedClass: (json['predictedClass'] as String?) ?? '',
      baseValue: (json['baseValue'] as num?)?.toDouble() ?? 0.0,
      topContributors: contributors ?? const [],
      confidenceRationale: rationale is Map<String, dynamic>
          ? ConfidenceRationale.fromJson(rationale)
          : const ConfidenceRationale(
              confidence: 0.0,
              predictedClass: '',
              runnerUpClass: '',
              runnerUpConfidence: 0.0,
              margin: 0.0,
              agreement: 0.0,
              strength: ConfidenceStrength.weak,
              lowConfidence: true,
            ),
    );
  }

  Map<String, dynamic> toJson() => {
    'method': method,
    'modelVersion': modelVersion,
    'disease': disease,
    'predictedClass': predictedClass,
    'baseValue': baseValue,
    'topContributors': topContributors.map((c) => c.toJson()).toList(),
    'confidenceRationale': confidenceRationale.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RiskAttributions &&
          other.method == method &&
          other.modelVersion == modelVersion &&
          other.disease == disease &&
          other.predictedClass == predictedClass &&
          other.baseValue == baseValue &&
          _listEquals(other.topContributors, topContributors) &&
          other.confidenceRationale == confidenceRationale;

  @override
  int get hashCode => Object.hash(
    method,
    modelVersion,
    disease,
    predictedClass,
    baseValue,
    Object.hashAll(topContributors),
    confidenceRationale,
  );
}

/// Order-sensitive value equality for a list (pure Dart; avoids importing
/// `package:flutter/foundation.dart` to keep this model framework-free).
bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
