import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/widgets/medical_disclaimer.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/resource_article.dart';
import 'package:fyp_foreseeme/features/resources/presentation/article_bookmark_provider.dart';
import 'package:fyp_foreseeme/features/resources/presentation/resources_providers.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/category_chip_row.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/emergency_card.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/featured_article_card.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/nearby_hospitals_entry.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/resource_article_card.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';

/// Health Resource Center: one-tap emergency dial, a context-aware featured
/// guide, browsable categories, and verified self-care guides. Content is
/// static (no backend); dialing, sharing and source links go through injected
/// services. Guides open in a routed [ArticleScreen], not a sheet.
class ResourceCenterScreen extends ConsumerStatefulWidget {
  const ResourceCenterScreen({super.key});

  @override
  ConsumerState<ResourceCenterScreen> createState() =>
      _ResourceCenterScreenState();
}

class _ResourceCenterScreenState extends ConsumerState<ResourceCenterScreen> {
  ResourceTopic? _selectedTopic;

  @override
  Widget build(BuildContext context) {
    final articles = ref.watch(orderedResourceArticlesProvider);
    final featured = ref.watch(featuredResourceArticleProvider);
    final contact = ref.watch(emergencyContactProvider);
    final bookmarks = ref.watch(bookmarkedArticleIdsProvider);
    // Nearby hospitals are surfaced prominently when the user's city risk is High.
    final isHighRisk =
        ref.watch(currentCityRiskProvider).value?.riskLevel == RiskLevel.high;

    final topics = articles.map((a) => a.topic).toSet().toList();
    final visibleArticles = _selectedTopic == null
        ? articles
        : articles.where((a) => a.topic == _selectedTopic).toList();

    void openHospitals() => context.push('/nearby-hospitals');

    final palette = context.fsmPalette;
    final text = context.fsmText;

    return Scaffold(
      backgroundColor: palette.background,
      body: Stack(
        children: [
          const Positioned.fill(child: _Background()),
          SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
              children: [
                Semantics(
                  header: true,
                  child: Text('Resource Center', style: text.titleLarge),
                ),
                const SizedBox(height: 4),
                Text(
                  'Verified guidance & emergency help',
                  style: text.bodyMedium?.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'PREPAREDNESS',
                  style: text.labelSmall?.copyWith(
                    letterSpacing: 1.2,
                    color: palette.textTertiary,
                  ),
                ),
                const SizedBox(height: 12),
                EmergencyCard(
                  contact: contact,
                  onCall: () => _dial(context, ref, contact.number),
                ),
                const SizedBox(height: 12),
                // One cohesive Preparedness block: the same risk signal used
                // everywhere else (isHighRisk) simply lifts the tone here too —
                // no second business rule.
                NearbyHospitalsEntry(prominent: isHighRisk, onTap: openHospitals),
                if (featured != null && _selectedTopic == null) ...[
                  const SizedBox(height: 22),
                  FeaturedArticleCard(
                    article: featured,
                    onTap: () => _openArticle(context, featured),
                  ),
                ],
                const SizedBox(height: 22),
                Text(
                  'SELF-CARE GUIDES',
                  style: text.labelSmall?.copyWith(
                    letterSpacing: 1.2,
                    color: palette.textTertiary,
                  ),
                ),
                const SizedBox(height: 12),
                CategoryChipRow(
                  topics: topics,
                  selected: _selectedTopic,
                  onSelected: (topic) => setState(() => _selectedTopic = topic),
                ),
                const SizedBox(height: 14),
                for (final article in visibleArticles)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ResourceArticleCard(
                      article: article,
                      bookmarked: bookmarks.contains(article.id),
                      onTap: () => _openArticle(context, article),
                    ),
                  ),
                const SizedBox(height: 22),
                const MedicalDisclaimer.inline(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _dial(BuildContext context, WidgetRef ref, String number) async {
    final launched = await ref.read(launcherServiceProvider).dialPhone(number);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the dialer.')),
      );
    }
  }

  void _openArticle(BuildContext context, ResourceArticle article) {
    context.push('/resources/article/${article.id}');
  }
}

class _Background extends StatelessWidget {
  const _Background();

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-0.8, -0.9),
          radius: 1.2,
          colors: [
            palette.secondary.withValues(alpha: 0.10),
            palette.background,
          ],
          stops: const [0.0, 0.6],
        ),
      ),
    );
  }
}
