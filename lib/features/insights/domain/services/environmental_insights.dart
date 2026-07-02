// Environmental insights derived from the model's GENUINE attributions
// (Sprint 5, Prompt 10). Framework-free, pure, deterministic.
//
// This is a natural extension of the Phase-3 explainability: it takes the stored
// `RiskAttributions` (the exact model-derived drivers, Prompt 5) and surfaces the
// *environmental* factors that most shaped the current estimate — reusing the
// same human labels as the "Why this prediction?" panel so the two never drift.
// It recomputes nothing; it filters and formats stored data only.

import 'package:fyp_foreseeme/features/risk/domain/models/risk_attributions.dart';
import 'package:fyp_foreseeme/features/risk/domain/services/explanation_templater.dart';

/// Feature keys that are NOT environmental factors (identity/time encodings and
/// the data-availability flag) — excluded from the environmental view.
bool isEnvironmentalFeature(String key) =>
    !key.startsWith('city_') &&
    key != 'week_sin' &&
    key != 'week_cos' &&
    key != 'aqi_available';

/// One environmental factor that shaped the estimate (a genuine attribution).
class EnvironmentalDriver {
  final String feature;
  final String label;
  final ContributionDirection direction;
  final double magnitude;

  const EnvironmentalDriver({
    required this.feature,
    required this.label,
    required this.direction,
    required this.magnitude,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EnvironmentalDriver &&
          other.feature == feature &&
          other.label == label &&
          other.direction == direction &&
          other.magnitude == magnitude;

  @override
  int get hashCode => Object.hash(feature, label, direction, magnitude);
}

/// The top [limit] ENVIRONMENTAL drivers from [attributions], in the backend's
/// ranked (by magnitude) order — never re-ranked. Returns an empty list when
/// there are no attributions (a pre-Sprint-5 estimate).
List<EnvironmentalDriver> deriveEnvironmentalDrivers(
  RiskAttributions? attributions, {
  int limit = 3,
}) {
  if (attributions == null) return const [];
  return attributions.topContributors
      .where((c) => isEnvironmentalFeature(c.feature))
      .take(limit)
      .map(
        (c) => EnvironmentalDriver(
          feature: c.feature,
          label: ExplanationTemplater.featureLabel(c.feature),
          direction: c.direction,
          magnitude: c.magnitude,
        ),
      )
      .toList(growable: false);
}
