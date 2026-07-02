import 'package:flutter_test/flutter_test.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_attributions.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';

/// A document body matching the backend's additive `attributions` object.
Map<String, dynamic> attributionsJson() => {
  'method': 'tree_path_contributions',
  'modelVersion': 'rf-1.0.0',
  'disease': 'dengue',
  'predictedClass': 'Medium',
  'baseValue': 0.333624,
  'topContributors': [
    {
      'feature': 'temperature',
      'contribution': 0.435698,
      'magnitude': 0.435698,
      'direction': 'increases',
      'value': 32.6,
    },
    {
      'feature': 'humidity',
      'contribution': -0.069265,
      'magnitude': 0.069265,
      'direction': 'decreases',
      'value': 76.0,
    },
  ],
  'confidenceRationale': {
    'confidence': 0.5599,
    'predictedClass': 'Medium',
    'runnerUpClass': 'High',
    'runnerUpConfidence': 0.4199,
    'margin': 0.14,
    'agreement': 0.585,
    'strength': 'weak',
    'lowConfidence': false,
  },
};

Map<String, dynamic> estimateJson({bool withAttributions = true}) => {
  'city': 'Lahore',
  'riskLevel': 'Medium',
  'disease': 'Dengue',
  'confidence': 0.5599,
  'temperature': 32.6,
  'humidity': 76.0,
  'aqi': 113.0,
  'generatedAt': '2026-07-02T00:00:00.000Z',
  'modelVersion': 'rf-1.0.0',
  'lowConfidence': false,
  if (withAttributions) 'attributions': attributionsJson(),
};

void main() {
  group('RiskAttributions.fromJson', () {
    test('parses the full additive payload', () {
      final a = RiskAttributions.fromJson(attributionsJson());

      expect(a.method, 'tree_path_contributions');
      expect(a.modelVersion, 'rf-1.0.0');
      expect(a.predictedClass, 'Medium');
      expect(a.topContributors, hasLength(2));
      expect(a.topContributors.first.feature, 'temperature');
      expect(a.topContributors.first.direction, ContributionDirection.increases);
      expect(a.topContributors[1].direction, ContributionDirection.decreases);
      expect(a.confidenceRationale.strength, ConfidenceStrength.weak);
      expect(a.confidenceRationale.runnerUpClass, 'High');
    });

    test('round-trips through toJson losslessly', () {
      final a = RiskAttributions.fromJson(attributionsJson());
      final restored = RiskAttributions.fromJson(a.toJson());
      expect(restored, a);
    });

    test('tolerates a missing contributors list and rationale defensively', () {
      final a = RiskAttributions.fromJson({
        'method': 'tree_path_contributions',
        'modelVersion': 'rf-1.0.0',
        'disease': 'dengue',
        'predictedClass': 'Low',
        'baseValue': 0.5,
      });
      expect(a.topContributors, isEmpty);
      // Missing rationale defaults to the most cautious framing.
      expect(a.confidenceRationale.strength, ConfidenceStrength.weak);
      expect(a.confidenceRationale.lowConfidence, isTrue);
    });

    test('enum parsing defaults defensively on unknown values', () {
      expect(ContributionDirection.fromJson('sideways'), ContributionDirection.increases);
      expect(ContributionDirection.fromJson(null), ContributionDirection.increases);
      expect(ConfidenceStrength.fromJson('mega'), ConfidenceStrength.weak);
      expect(ConfidenceStrength.fromJson(null), ConfidenceStrength.weak);
    });
  });

  group('RiskEstimateModel additive attributions', () {
    test('new document parses the attributions', () {
      final model = RiskEstimateModel.fromJson(estimateJson());
      expect(model.attributions, isNotNull);
      expect(model.attributions!.topContributors, hasLength(2));
      expect(model.attributions!.predictedClass, model.riskLevel.toJson());
    });

    test('legacy document without attributions parses to null (backward compat)', () {
      final model = RiskEstimateModel.fromJson(
        estimateJson(withAttributions: false),
      );
      expect(model.attributions, isNull);
      // Frozen fields are unaffected.
      expect(model.city, 'Lahore');
      expect(model.riskLevel, RiskLevel.medium);
      expect(model.confidence, 0.5599);
    });

    test('round-trips with attributions losslessly', () {
      final original = RiskEstimateModel.fromJson(estimateJson());
      final restored = RiskEstimateModel.fromJson(original.toJson());
      expect(restored, original);
      expect(restored.hashCode, original.hashCode);
    });

    test('toJson omits the attributions key when absent (exact legacy shape)', () {
      final model = RiskEstimateModel.fromJson(
        estimateJson(withAttributions: false),
      );
      expect(model.toJson().containsKey('attributions'), isFalse);
    });

    test('equality accounts for attributions', () {
      final withAttr = RiskEstimateModel.fromJson(estimateJson());
      final withoutAttr = RiskEstimateModel.fromJson(
        estimateJson(withAttributions: false),
      );
      expect(withAttr, isNot(withoutAttr));
    });
  });
}
