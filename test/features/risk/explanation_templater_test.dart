import 'package:flutter_test/flutter_test.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_attributions.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/domain/services/explanation_templater.dart';

/// A representative confidence rationale with a chosen [strength] and a clean
/// agreement value (so the templated percentage is exact).
ConfidenceRationale rationale({
  ConfidenceStrength strength = ConfidenceStrength.moderate,
  double agreement = 0.60,
  String predicted = 'Medium',
  String runnerUp = 'High',
  bool lowConfidence = false,
}) => ConfidenceRationale(
  confidence: 0.56,
  predictedClass: predicted,
  runnerUpClass: runnerUp,
  runnerUpConfidence: 0.42,
  margin: 0.14,
  agreement: agreement,
  strength: strength,
  lowConfidence: lowConfidence,
);

RiskAttributions attributions({
  List<FeatureContribution>? contributors,
  ConfidenceRationale? conf,
}) => RiskAttributions(
  method: 'tree_path_contributions',
  modelVersion: 'rf-1.0.0',
  disease: 'dengue',
  predictedClass: 'Medium',
  baseValue: 0.33,
  topContributors:
      contributors ??
      const [
        FeatureContribution(
          feature: 'temperature',
          contribution: 0.44,
          magnitude: 0.44,
          direction: ContributionDirection.increases,
          value: 32.6,
        ),
        FeatureContribution(
          feature: 'humidity_lag1',
          contribution: -0.07,
          magnitude: 0.07,
          direction: ContributionDirection.decreases,
          value: 76.0,
        ),
      ],
  confidenceRationale: conf ?? rationale(),
);

RiskEstimateModel estimate({RiskAttributions? attr}) => RiskEstimateModel(
  city: 'Lahore',
  riskLevel: RiskLevel.medium,
  disease: 'Dengue',
  confidence: 0.56,
  temperature: 32.6,
  humidity: 76.0,
  aqi: 113.0,
  generatedAt: DateTime.utc(2026, 7, 2),
  modelVersion: 'rf-1.0.0',
  attributions: attr,
);

void main() {
  group('ExplanationTemplater.build', () {
    test('returns null when the estimate has no attributions', () {
      expect(ExplanationTemplater.build(estimate(attr: null)), isNull);
    });

    test('lead names the disease and city', () {
      final view = ExplanationTemplater.build(estimate(attr: attributions()))!;
      expect(view.title, 'Why this estimate?');
      expect(view.lead, contains('Dengue'));
      expect(view.lead, contains('Lahore'));
    });

    test('preserves the backend driver order (no re-ranking)', () {
      final view = ExplanationTemplater.build(estimate(attr: attributions()))!;
      expect(view.drivers.map((d) => d.label).toList(), [
        'Temperature',
        'Humidity (previous week)',
      ]);
    });

    test('maps an increasing driver to the "pushed higher" template', () {
      final view = ExplanationTemplater.build(estimate(attr: attributions()))!;
      final temp = view.drivers.first;
      expect(temp.direction, ContributionDirection.increases);
      expect(temp.sentence, 'Temperature, measured 32.6°C, pushed this estimate higher.');
    });

    test('maps a decreasing driver to the "pulled lower" template', () {
      final view = ExplanationTemplater.build(estimate(attr: attributions()))!;
      final hum = view.drivers[1];
      expect(hum.direction, ContributionDirection.decreases);
      expect(
        hum.sentence,
        'Humidity (previous week), measured 76%, pulled this estimate lower.',
      );
    });

    test('is deterministic — identical input yields identical copy', () {
      final a = ExplanationTemplater.build(estimate(attr: attributions()))!;
      final b = ExplanationTemplater.build(estimate(attr: attributions()))!;
      expect(a.lead, b.lead);
      expect(a.confidenceSentence, b.confidenceSentence);
      expect(
        a.drivers.map((d) => d.sentence).toList(),
        b.drivers.map((d) => d.sentence).toList(),
      );
    });
  });

  group('ExplanationTemplater.featureLabel', () {
    test('raw same-week features', () {
      expect(ExplanationTemplater.featureLabel('temperature'), 'Temperature');
      expect(ExplanationTemplater.featureLabel('humidity'), 'Humidity');
      expect(ExplanationTemplater.featureLabel('precipitation'), 'Rainfall');
      expect(ExplanationTemplater.featureLabel('us_aqi'), 'Air quality (AQI)');
    });

    test('lag features name the earlier week', () {
      expect(
        ExplanationTemplater.featureLabel('humidity_lag1'),
        'Humidity (previous week)',
      );
      expect(
        ExplanationTemplater.featureLabel('humidity_lag2'),
        'Humidity (2 weeks earlier)',
      );
    });

    test('rolling and anomaly features', () {
      expect(
        ExplanationTemplater.featureLabel('humidity_roll3'),
        'Humidity (3-week average)',
      );
      expect(
        ExplanationTemplater.featureLabel('temperature_anomaly'),
        'Temperature (vs seasonal normal)',
      );
    });

    test('cyclical, city one-hot, and unknown keys', () {
      expect(ExplanationTemplater.featureLabel('week_sin'), 'Time of year');
      expect(ExplanationTemplater.featureLabel('city_Lahore'), 'City (Lahore)');
      // Unknown key degrades to a titleised label rather than crashing.
      expect(ExplanationTemplater.featureLabel('some_new_signal'), 'Some New Signal');
    });
  });

  group('ExplanationTemplater confidence sentence', () {
    String sentenceFor(ConfidenceStrength s, {double agreement = 0.60}) {
      final view = ExplanationTemplater.build(
        estimate(attr: attributions(conf: rationale(strength: s, agreement: agreement))),
      )!;
      return view.confidenceSentence;
    }

    test('strong', () {
      final s = sentenceFor(ConfidenceStrength.strong, agreement: 0.90);
      expect(s, startsWith('Confidence is strong'));
      expect(s, contains('Medium'));
      expect(s, contains('High'));
      expect(s, contains('90%'));
    });

    test('moderate', () {
      final s = sentenceFor(ConfidenceStrength.moderate, agreement: 0.60);
      expect(s, startsWith('Confidence is moderate'));
      expect(s, contains('60%'));
    });

    test('weak advises extra caution', () {
      final s = sentenceFor(ConfidenceStrength.weak, agreement: 0.40);
      expect(s, startsWith('Confidence is limited'));
      expect(s, contains('40%'));
      expect(s, contains('caution'));
    });
  });
}
