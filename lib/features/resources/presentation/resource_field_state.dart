import 'package:fyp_foreseeme/features/resources/domain/models/resource_article.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/resource_center_style.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/domain/services/risk_driver_service.dart';

/// The Resource Center field's **reactive copy**, derived from the one risk
/// signal the app already computes.
///
/// The prototype switches its `[data-energy]` state, context line and weighting
/// caption from a scenario picker. Production derives all three here — purely,
/// and only from values that already exist: [currentCityRiskProvider]'s
/// estimate and the topic order [priorityTopicOrder] already produces. Nothing
/// in this file invents a reading, a threshold or a claim.

/// The field's energy for [estimate].
///
/// No estimate at all is the prototype's `neutral` (a grey field, honestly
/// signalling "nothing measured"); Low is `calm`; Medium lifts to `elevated`;
/// High to `high`. This is the same Low/Medium/High split every other surface
/// already reacts to — not a second business rule.
ResourceEnergy resourceFieldEnergy(RiskEstimateModel? estimate) {
  if (estimate == null) return ResourceEnergy.neutral;
  return switch (estimate.riskLevel) {
    RiskLevel.low => ResourceEnergy.calm,
    RiskLevel.medium => ResourceEnergy.elevated,
    RiskLevel.high => ResourceEnergy.high,
  };
}

/// True when the environmental signal is genuinely raised — the condition that
/// turns the contextual rail from `EXPLORE` into `RELEVANT FOR YOU`, matching
/// `isTopicContextuallyRelevantProvider`'s own rule.
bool resourceSignalElevated(RiskEstimateModel? estimate) =>
    estimate != null && estimate.riskLevel != RiskLevel.low;

/// The pill under the field object.
///
/// With no estimate it reports exactly that. With one, it names the dominant
/// driver and the city the estimate is for — both already computed, both real.
String resourceContextLine(RiskEstimateModel? estimate) {
  if (estimate == null) return 'NO ENVIRONMENTAL SIGNAL';
  final city = estimate.city.toUpperCase();
  if (!resourceSignalElevated(estimate)) {
    return 'CONDITIONS WITHIN TYPICAL RANGE · $city';
  }
  final driver = dominantDriver(estimate);
  return '${driver.label.toUpperCase()} ${driver.value} · $city';
}

/// The right-hand channel caption: which topic the catalogue is currently
/// weighted toward, or `BALANCED WEIGHTING` when nothing is promoting one.
String resourceFieldLabel(
  RiskEstimateModel? estimate,
  List<ResourceTopic> topicOrder,
) {
  if (!resourceSignalElevated(estimate) || topicOrder.isEmpty) {
    return 'BALANCED WEIGHTING';
  }
  return '${resourceCatLabel(topicOrder.first)} WEIGHTING';
}

/// The card meta line — the prototype's `4 MIN · SOURCE`, carrying the reading
/// estimate for ForeSeeMe's own summary and the publisher's short badge.
///
/// Restrained by design: the badge is `WHO`, not a full organisation name and
/// not a verification flourish. A resource whose publisher is not a recognised
/// authority prints no badge at all rather than borrowing the look of one.
String resourceMetaLine(ResourceArticle article) {
  final minutes = '${article.readingMinutes} MIN';
  if (!article.isTrustedSource) return minutes;
  return '$minutes · ${article.authority.shortLabel}';
}
