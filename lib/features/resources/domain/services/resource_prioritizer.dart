// Deterministic Resource Center context-awareness.
//
// Framework-free, pure. Reuses the risk feature's already-computed
// [dominantDriver] (mirroring insights/domain/services/recommendation_prioritizer.dart's
// cross-feature composition pattern) to order self-care topics by relevance to
// the user's CURRENT environmental risk — it invents no new business logic, it
// only reads the existing driver signal and maps it onto the existing
// [ResourceTopic]s.
//
// On a Low-risk day (or with no estimate yet) the order stays calm and
// default — reordering by driver only kicks in once risk is actually elevated,
// matching the copy tone already established elsewhere ("Surfaced because risk
// is High in your area").

import 'package:fyp_foreseeme/features/resources/domain/models/resource_article.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/domain/services/risk_driver_service.dart';

/// The calm, default topic order shown with no elevated risk signal.
const List<ResourceTopic> kDefaultTopicOrder = [
  ResourceTopic.airQuality,
  ResourceTopic.lungs,
  ResourceTopic.asthma,
  ResourceTopic.heat,
];

/// Topic priority order for the current [estimate] — most relevant first.
///
/// Returns [kDefaultTopicOrder] when there is no estimate yet, or when the
/// risk level is Low (nothing to prioritize ahead of the calm default). On
/// Medium/High risk, the dominant environmental driver ([dominantDriver])
/// promotes its matching topic(s) to the front:
///  * air quality driver → air-quality guidance, then lungs, then asthma;
///  * heat driver → heat guidance first;
///  * humidity driver → no single matching self-care topic exists yet, so the
///    calm default order is kept (never force a mismatched category to the
///    top).
List<ResourceTopic> priorityTopicOrder(RiskEstimateModel? estimate) {
  if (estimate == null || estimate.riskLevel == RiskLevel.low) {
    return kDefaultTopicOrder;
  }
  return switch (dominantDriver(estimate).kind) {
    RiskDriverKind.airQuality => const [
      ResourceTopic.airQuality,
      ResourceTopic.lungs,
      ResourceTopic.asthma,
      ResourceTopic.heat,
    ],
    RiskDriverKind.heat => const [
      ResourceTopic.heat,
      ResourceTopic.airQuality,
      ResourceTopic.lungs,
      ResourceTopic.asthma,
    ],
    RiskDriverKind.humidity => kDefaultTopicOrder,
  };
}

/// Orders [articles] by [priorityOrder]'s topic ranking, preserving the
/// original relative order of articles that share a topic (stable sort) —
/// never re-ranking within a topic, only re-grouping topics.
List<ResourceArticle> orderArticlesByTopic(
  List<ResourceArticle> articles,
  List<ResourceTopic> priorityOrder,
) {
  final rank = {for (var i = 0; i < priorityOrder.length; i++) priorityOrder[i]: i};
  final indexed = articles.indexed.toList()
    ..sort((a, b) {
      final byTopic = (rank[a.$2.topic] ?? priorityOrder.length).compareTo(
        rank[b.$2.topic] ?? priorityOrder.length,
      );
      if (byTopic != 0) return byTopic;
      return a.$1.compareTo(b.$1);
    });
  return [for (final e in indexed) e.$2];
}

/// The single article to feature prominently: the first article (in original
/// list order) whose topic is the current top [priorityOrder] entry. Returns
/// `null` only when [articles] is empty.
ResourceArticle? featuredArticle(
  List<ResourceArticle> articles,
  List<ResourceTopic> priorityOrder,
) {
  if (articles.isEmpty) return null;
  for (final topic in priorityOrder) {
    for (final article in articles) {
      if (article.topic == topic) return article;
    }
  }
  return articles.first;
}
