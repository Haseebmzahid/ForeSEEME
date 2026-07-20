import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/resource_article.dart';
import 'package:fyp_foreseeme/features/resources/presentation/resources_providers.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/resource_visuals.dart';

/// The Resource Center's hero card (Goal 1/2): the one guide surfaced above
/// everything else. Its eyebrow label tells the truth about *why* it's
/// featured — "Prioritized · matches today's risk" when the current dominant
/// risk driver genuinely picked it (via [isTopicContextuallyRelevantProvider]),
/// or a calm "Editor's pick" otherwise. Never claims relevance it doesn't have.
class FeaturedArticleCard extends ConsumerWidget {
  final ResourceArticle article;
  final VoidCallback onTap;

  const FeaturedArticleCard({
    super.key,
    required this.article,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final visual = ResourceTopicVisual.of(context, article.topic);
    final relevant = ref.watch(isTopicContextuallyRelevantProvider(article.topic));

    return AppReveal(
      child: Semantics(
        button: true,
        label: 'Featured guide: ${article.title}',
        child: PressableScale(
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(ForeSeeMeSpacing.lg),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(ForeSeeMeRadius.lg),
              gradient: LinearGradient(
                colors: [
                  visual.color.withValues(alpha: 0.20),
                  ForeSeeMeSurface.fill(context),
                ],
                begin: const Alignment(-0.9, -1),
                end: const Alignment(0.9, 1),
              ),
              border: Border.all(color: visual.color.withValues(alpha: 0.34)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Eyebrow(relevant: relevant, color: visual.color),
                    const Spacer(),
                    Icon(visual.icon, color: visual.color, size: 20),
                  ],
                ),
                const SizedBox(height: ForeSeeMeSpacing.md),
                Text(
                  article.title,
                  style: text.titleLarge?.copyWith(color: palette.textPrimary),
                ),
                const SizedBox(height: 6),
                Text(
                  article.summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(color: palette.textSecondary),
                ),
                const SizedBox(height: ForeSeeMeSpacing.md),
                Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 14,
                      color: palette.textTertiary,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${article.readingMinutes} min read',
                      style: text.labelSmall?.copyWith(color: palette.textTertiary),
                    ),
                    const Spacer(),
                    Text(
                      'Read guide →',
                      style: text.labelMedium?.copyWith(
                        color: visual.color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  final bool relevant;
  final Color color;
  const _Eyebrow({required this.relevant, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(ForeSeeMeRadius.full),
      ),
      child: Text(
        relevant ? 'PRIORITIZED FOR TODAY' : "EDITOR'S PICK",
        style: context.fsmText.labelSmall?.copyWith(
          color: color,
          letterSpacing: 1.0,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
