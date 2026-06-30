import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fyp_foreseeme/core/theme/app_design_v2.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/resource_article.dart';
import 'package:fyp_foreseeme/features/resources/presentation/resources_providers.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/article_detail_sheet.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/emergency_card.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/resource_article_card.dart';

/// Health Resource Center (Sprint 3, Prompt 5): one-tap emergency dial plus
/// verified, sourced self-care guides. Content is static (no backend); dialing
/// and source links go through [launcherServiceProvider].
class ResourceCenterScreen extends ConsumerWidget {
  const ResourceCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final articles = ref.watch(resourceArticlesProvider);
    final contact = ref.watch(emergencyContactProvider);

    return Scaffold(
      backgroundColor: AppColorsV2.shell,
      body: Stack(
        children: [
          const Positioned.fill(child: _Background()),
          SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
              children: [
                Text('Resource Center', style: AppTextStylesV2.cardTitle),
                const SizedBox(height: 4),
                Text(
                  'Verified guidance & emergency help',
                  style: AppTextStylesV2.body,
                ),
                const SizedBox(height: 18),
                EmergencyCard(
                  contact: contact,
                  onCall: () => _dial(context, ref, contact.number),
                ),
                const SizedBox(height: 22),
                Text('SELF-CARE GUIDES', style: AppTextStylesV2.microLabel),
                const SizedBox(height: 12),
                for (final article in articles)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ResourceArticleCard(
                      article: article,
                      onTap: () => _openArticle(context, ref, article),
                    ),
                  ),
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
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.8, -0.9),
          radius: 1.2,
          colors: [Color(0x1A2FD4C2), AppColorsV2.shell],
          stops: [0.0, 0.6],
        ),
      ),
    );
  }
}
