// Pure-Dart model for the ForeSeeMe risk-data contract.
//
// This file is intentionally framework-free: it imports NO `package:flutter`
// and NO `cloud_firestore`. It mirrors the immutable-model conventions already
// used by the existing `auth` feature (`UserModel`), which serialises its
// `DateTime` as an ISO-8601 string rather than a Firestore `Timestamp`.
//
// The same shape is shared by three artifacts (see docs/RISK_SCHEMA.md):
//   1. The Pydantic `RiskEstimateResponse` (backend/app/schemas.py).
//   2. This Dart `RiskEstimateModel`.
//   3. The Firestore document `riskEstimates/{city}_{YYYY-MM-DD}`.

/// Disease-risk classification level for a city.
///
/// Serialises to the exact capitalised strings stored in Firestore and returned
/// by the backend (`"Low" | "Medium" | "High"`). Follows the enum + companion
/// extension pattern used by the medication feature's enums.
enum RiskLevel {
  low,
  medium,
  high;

  /// Serialises to the contract string (e.g. `RiskLevel.low` -> `"Low"`).
  String toJson() => switch (this) {
    RiskLevel.low => 'Low',
    RiskLevel.medium => 'Medium',
    RiskLevel.high => 'High',
  };
}

extension RiskLevelX on RiskLevel {
  /// Deserialises from a contract string. Returns [RiskLevel.low] as a safe
  /// default if the stored value is unrecognised, matching the defensive
  /// `fromJson` style used by the medication enums.
  static RiskLevel fromJson(String? value) {
    switch (value) {
      case 'Low':
        return RiskLevel.low;
      case 'Medium':
        return RiskLevel.medium;
      case 'High':
        return RiskLevel.high;
      default:
        return RiskLevel.low;
    }
  }
}

/// Immutable model for a per-city disease-risk estimate.
///
/// Firestore path: `riskEstimates/{docId}` where [docId] is the
/// `{city}_{YYYY-MM-DD}` composite (see [docId]). The app reads this collection
/// ONLY (ADR-001); it never calls the FastAPI `/predict` endpoint directly.
class RiskEstimateModel {
  /// Pakistani city this estimate was computed for, e.g. `"Lahore"`.
  final String city;

  /// Classified risk level for [disease] in [city].
  final RiskLevel riskLevel;

  /// Disease the estimate refers to, e.g. `"Dengue"`.
  final String disease;

  /// Model confidence in the classification, in the range `[0.0, 1.0]`.
  final double confidence;

  /// Temperature feature used for the estimate (degrees Celsius).
  final double temperature;

  /// Relative humidity feature used for the estimate (percent).
  final double humidity;

  /// Air-quality-index feature used for the estimate.
  final double aqi;

  /// When the estimate was generated, normalised to UTC.
  final DateTime generatedAt;

  /// Version string of the model that produced the estimate, e.g. `"rf-v1.2"`.
  final String modelVersion;

  /// True when [confidence] is below the backend's reliability threshold.
  /// Optional in the contract; defaults to `false`.
  final bool lowConfidence;

  const RiskEstimateModel({
    required this.city,
    required this.riskLevel,
    required this.disease,
    required this.confidence,
    required this.temperature,
    required this.humidity,
    required this.aqi,
    required this.generatedAt,
    required this.modelVersion,
    this.lowConfidence = false,
  });

  // ── Serialisation ──────────────────────────────────────────────────────────

  /// Deserialise from a Firestore document body / `/predict` JSON response.
  ///
  /// [generatedAt] is parsed from an ISO-8601 string and normalised to UTC so
  /// equality is stable regardless of the producer's local offset.
  factory RiskEstimateModel.fromJson(Map<String, dynamic> json) {
    return RiskEstimateModel(
      city: (json['city'] as String?) ?? '',
      riskLevel: RiskLevelX.fromJson(json['riskLevel'] as String?),
      disease: (json['disease'] as String?) ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.0,
      humidity: (json['humidity'] as num?)?.toDouble() ?? 0.0,
      aqi: (json['aqi'] as num?)?.toDouble() ?? 0.0,
      generatedAt: DateTime.parse(json['generatedAt'] as String).toUtc(),
      modelVersion: (json['modelVersion'] as String?) ?? '',
      lowConfidence: (json['lowConfidence'] as bool?) ?? false,
    );
  }

  /// Serialise to a contract-compatible map.
  ///
  /// [generatedAt] is written as a UTC ISO-8601 string (e.g.
  /// `"2026-06-28T00:00:00.000Z"`), matching the `UserModel` convention.
  Map<String, dynamic> toJson() {
    return {
      'city': city,
      'riskLevel': riskLevel.toJson(),
      'disease': disease,
      'confidence': confidence,
      'temperature': temperature,
      'humidity': humidity,
      'aqi': aqi,
      'generatedAt': generatedAt.toUtc().toIso8601String(),
      'modelVersion': modelVersion,
      'lowConfidence': lowConfidence,
    };
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// The Firestore document ID convention: `{city}_{YYYY-MM-DD}` derived from
  /// [city] and the UTC date part of [generatedAt] (see docs/RISK_SCHEMA.md).
  String get docId => '${city}_${_dateOnlyString(generatedAt.toUtc())}';

  /// Formats a [DateTime] to `"yyyy-MM-dd"`.
  static String _dateOnlyString(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  RiskEstimateModel copyWith({
    String? city,
    RiskLevel? riskLevel,
    String? disease,
    double? confidence,
    double? temperature,
    double? humidity,
    double? aqi,
    DateTime? generatedAt,
    String? modelVersion,
    bool? lowConfidence,
  }) {
    return RiskEstimateModel(
      city: city ?? this.city,
      riskLevel: riskLevel ?? this.riskLevel,
      disease: disease ?? this.disease,
      confidence: confidence ?? this.confidence,
      temperature: temperature ?? this.temperature,
      humidity: humidity ?? this.humidity,
      aqi: aqi ?? this.aqi,
      generatedAt: generatedAt ?? this.generatedAt,
      modelVersion: modelVersion ?? this.modelVersion,
      lowConfidence: lowConfidence ?? this.lowConfidence,
    );
  }

  @override
  String toString() =>
      'RiskEstimateModel(city: $city, disease: $disease, '
      'riskLevel: ${riskLevel.name}, confidence: $confidence, '
      'generatedAt: ${generatedAt.toUtc().toIso8601String()})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RiskEstimateModel &&
          other.city == city &&
          other.riskLevel == riskLevel &&
          other.disease == disease &&
          other.confidence == confidence &&
          other.temperature == temperature &&
          other.humidity == humidity &&
          other.aqi == aqi &&
          other.generatedAt == generatedAt &&
          other.modelVersion == modelVersion &&
          other.lowConfidence == lowConfidence;

  @override
  int get hashCode => Object.hash(
    city,
    riskLevel,
    disease,
    confidence,
    temperature,
    humidity,
    aqi,
    generatedAt,
    modelVersion,
    lowConfidence,
  );
}
