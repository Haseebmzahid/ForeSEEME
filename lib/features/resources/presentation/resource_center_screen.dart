import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/resource_article.dart';
import 'package:fyp_foreseeme/features/resources/presentation/resources_providers.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/article_detail_sheet.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/emergency_card.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/nearby_hospitals_entry.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/resource_article_card.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';

/// Health Resource Center (Sprint 3, Prompt 5): one-tap emergency dial plus
/// verified, sourced self-care guides. Content is static (no backend); dialing
/// and source links go through [launcherServiceProvider].
class ResourceCenterScreen extends ConsumerWidget {
  const ResourceCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final articles = ref.watch(resourceArticlesProvider);
    final contact = ref.watch(emergencyContactProvider);
    // Nearby hospitals are surfaced prominently when the user's city risk is High.
    final isHighRisk =
        ref.watch(currentCityRiskProvider).value?.riskLevel == RiskLevel.high;

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
                const SizedBox(height: 18),
                EmergencyCard(
                  contact: contact,
                  onCall: () => _dial(context, ref, contact.number),
                ),
                // High risk: lift the hospitals entry to the top, prominently.
                if (isHighRisk) ...[
                  const SizedBox(height: 14),
                  NearbyHospitalsEntry(prominent: true, onTap: openHospitals),
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
                for (final article in articles)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ResourceArticleCard(
                      article: article,
                      onTap: () => _openArticle(context, ref, article),
                    ),
                  ),
                // Otherwise a calm teaser at the bottom.
                if (!isHighRisk) ...[
                  const SizedBox(height: 6),
                  NearbyHospitalsEntry(prominent: false, onTap: openHospitals),
                ],
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

  void _openArticle(
    BuildContext context,
    WidgetRef ref,
    ResourceArticle article,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ArticleDetailSheet(
        article: article,
        onOpenSource: () => ref
            .read(launcherServiceProvider)
            .openExternalUrl(article.sourceUrl),
      ),
    );
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
