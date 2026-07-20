import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fyp_foreseeme/core/services/launcher_service.dart';
import 'package:fyp_foreseeme/core/services/share_service.dart';
import 'package:fyp_foreseeme/features/resources/data/repositories/static_resource_repository.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/emergency_contact.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/resource_article.dart';
import 'package:fyp_foreseeme/features/resources/domain/repositories/resource_repository.dart';
import 'package:fyp_foreseeme/features/resources/domain/services/resource_prioritizer.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';

/// Concrete [ResourceRepository]. Depends on the abstract type so tests/dev can
/// override it with a fake library (mirrors `riskRepositoryProvider`).
final resourceRepositoryProvider = Provider<ResourceRepository>((ref) {
  return const StaticResourceRepository();
});

/// The curated self-care guides, in their stored (unordered) form.
final resourceArticlesProvider = Provider<List<ResourceArticle>>((ref) {
  return ref.watch(resourceRepositoryProvider).articles();
});

/// The primary emergency contact (Rescue 1122).
final emergencyContactProvider = Provider<EmergencyContact>((ref) {
  return ref.watch(resourceRepositoryProvider).emergencyContact();
});

/// External launcher (dialer / browser). Overridable with a fake in tests so the
/// `tel:` intent can be asserted without a device.
final launcherServiceProvider = Provider<LauncherService>((ref) {
  return const UrlLauncherService();
});

/// Platform share sheet. Overridable with a fake in tests so the shared text
/// can be asserted without a device.
final shareServiceProvider = Provider<ShareService>((ref) {
  return const SharePlusShareService();
});

/// Topic priority order for the current user's city risk (Goal 2: context
/// awareness) — composed at the provider level from the existing
/// [currentCityRiskProvider] read, exactly as [ResourceCenterScreen] already
/// does for its `isHighRisk` check. Resolves to the calm default while risk is
/// still loading, so callers never flash a reorder.
final resourceTopicOrderProvider = Provider<List<ResourceTopic>>((ref) {
  final estimate = ref.watch(currentCityRiskProvider).asData?.value;
  return priorityTopicOrder(estimate);
});

/// The curated self-care guides, reordered by [resourceTopicOrderProvider].
final orderedResourceArticlesProvider = Provider<List<ResourceArticle>>((ref) {
  final articles = ref.watch(resourceArticlesProvider);
  final order = ref.watch(resourceTopicOrderProvider);
  return orderArticlesByTopic(articles, order);
});

/// The single article to feature prominently at the top of the Resource
/// Center, per [resourceTopicOrderProvider]. `null` only when there is no
/// content at all.
final featuredResourceArticleProvider = Provider<ResourceArticle?>((ref) {
  final articles = ref.watch(resourceArticlesProvider);
  final order = ref.watch(resourceTopicOrderProvider);
  return featuredArticle(articles, order);
});

/// Looks up one article by [id] for the routed article screen. `null` when the
/// id does not match any curated article (the screen renders its empty state).
final articleByIdProvider = Provider.family<ResourceArticle?, String>((
  ref,
  id,
) {
  final articles = ref.watch(resourceArticlesProvider);
  for (final article in articles) {
    if (article.id == id) return article;
  }
  return null;
});

/// True when [topic] is the current top-priority topic AND risk is actually
/// elevated (Medium/High) — the honest condition for showing "prioritized for
/// your current risk" on an article, mirroring the calm-by-default rule
/// already used for the nearby-hospitals prominence.
final isTopicContextuallyRelevantProvider = Provider.family<bool, ResourceTopic>((
  ref,
  topic,
) {
  final estimate = ref.watch(currentCityRiskProvider).asData?.value;
  if (estimate == null || estimate.riskLevel == RiskLevel.low) return false;
  final order = ref.watch(resourceTopicOrderProvider);
  return order.isNotEmpty && order.first == topic;
});
