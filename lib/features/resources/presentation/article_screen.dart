import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/core/widgets/empty_state.dart';
import 'package:fyp_foreseeme/core/widgets/medical_disclaimer.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/resource_article.dart';
import 'package:fyp_foreseeme/features/resources/presentation/article_bookmark_provider.dart';
import 'package:fyp_foreseeme/features/resources/presentation/resources_providers.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/article_content_blocks.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/resource_visuals.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/source_citation_card.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';

/// Full-screen reading experience for one [ResourceArticle] (Goal 3/5): real
/// heading/paragraph/tip/warning structure, a reading-progress indicator, a
/// contextual "prioritized for your current risk" chip when it genuinely
/// applies, the visible source citation, bookmarking, and share — all routed
/// (`/resources/article/:id`) so back navigation is a real stack pop, not a
/// dismissed sheet.
class ArticleScreen extends ConsumerStatefulWidget {
  final String articleId;

  const ArticleScreen({super.key, required this.articleId});

  @override
  ConsumerState<ArticleScreen> createState() => _ArticleScreenState();
}

class _ArticleScreenState extends ConsumerState<ArticleScreen> {
  double _progress = 0;

  void _onScroll(ScrollNotification notification) {
    final max = notification.metrics.maxScrollExtent;
    final next = max <= 0
        ? 1.0
        : (notification.metrics.pixels / max).clamp(0.0, 1.0);
    if ((next - _progress).abs() >= 0.01) setState(() => _progress = next);
  }

  @override
  Widget build(BuildContext context) {
    final article = ref.watch(articleByIdProvider(widget.articleId));
    final palette = context.fsmPalette;

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        foregroundColor: palette.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => context.pop(),
        ),
        actions: article == null
            ? null
            : [
                _BookmarkAction(articleId: article.id),
                _ShareAction(article: article),
                const SizedBox(width: 4),
              ],
        bottom: article == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: _ReadingProgressBar(progress: _progress),
              ),
      ),
      body: SafeArea(
        top: false,
        child: article == null
            ? const EmptyState(
                icon: Icons.menu_book_outlined,
                title: 'Guide not found',
                description: 'This self-care guide is no longer available.',
              )
            : Column(
                children: [
                  Expanded(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (n) {
                        _onScroll(n);
                        return false;
                      },
                      child: _ArticleBody(article: article),
                    ),
                  ),
                  // Persistent non-diagnostic framing — always visible while
                  // reading, matching Risk Details / Health Intelligence /
                  // Model Transparency's detail-screen convention (never
                  // scrolled away with the content).
                  const Padding(
                    padding: EdgeInsets.fromLTRB(
                      ForeSeeMeSpacing.gutter,
                      ForeSeeMeSpacing.sm,
                      ForeSeeMeSpacing.gutter,
                      ForeSeeMeSpacing.lg,
                    ),
                    child: MedicalDisclaimer.banner(),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ReadingProgressBar extends StatelessWidget {
  final double progress;
  const _ReadingProgressBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    return SizedBox(
      height: 3,
      child: Stack(
        children: [
          Container(color: palette.outlineVariant.withValues(alpha: 0.5)),
          AnimatedFractionallySizedBox(
            duration: AppMotion.fast,
            curve: AppMotion.curve,
            widthFactor: progress,
            alignment: Alignment.centerLeft,
            child: Container(color: palette.secondary),
          ),
        ],
      ),
    );
  }
}

class _ArticleBody extends ConsumerWidget {
  final ResourceArticle article;
  const _ArticleBody({required this.article});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final visual = ResourceTopicVisual.of(context, article.topic);
    final relevant = ref.watch(isTopicContextuallyRelevantProvider(article.topic));
    final city = ref.watch(currentCityRiskProvider).asData?.value?.city;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: visual.color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(visual.icon, color: visual.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${article.readingMinutes} min read',
                style: text.labelMedium?.copyWith(color: palette.textTertiary),
              ),
            ),
          ],
        ),
        const SizedBox(height: ForeSeeMeSpacing.lg),
        Semantics(
          header: true,
          child: Text(article.title, style: text.headlineSmall),
        ),
        const SizedBox(height: ForeSeeMeSpacing.sm),
        Text(
          article.summary,
          style: text.bodyLarge?.copyWith(color: palette.textSecondary),
        ),
        if (relevant) ...[
          const SizedBox(height: ForeSeeMeSpacing.md),
          _ContextualRelevanceChip(city: city),
        ],
        const SizedBox(height: ForeSeeMeSpacing.xxl),
        ArticleContentBlocks(blocks: article.content, accent: visual.color),
        const SizedBox(height: ForeSeeMeSpacing.sm),
        SourceCitationCard(
          sourceName: article.sourceName,
          onOpenSource: () =>
              ref.read(launcherServiceProvider).openExternalUrl(article.sourceUrl),
        ),
      ],
    );
  }
}

class _ContextualRelevanceChip extends StatelessWidget {
  final String? city;
  const _ContextualRelevanceChip({required this.city});

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final accent = context.fsmColors.warning;
    final place = city ?? 'your area';
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(ForeSeeMeRadius.full),
          border: Border.all(color: accent.withValues(alpha: 0.32)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bolt_rounded, size: 15, color: accent),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Prioritized — matches today’s risk in $place',
                style: context.fsmText.labelSmall?.copyWith(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookmarkAction extends ConsumerWidget {
  final String articleId;
  const _BookmarkAction({required this.articleId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarked = ref.watch(
      bookmarkedArticleIdsProvider.select((ids) => ids.contains(articleId)),
    );
    return IconButton(
      icon: Icon(
        bookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
      ),
      tooltip: bookmarked ? 'Remove bookmark' : 'Bookmark this guide',
      onPressed: () =>
          ref.read(bookmarkedArticleIdsProvider.notifier).toggle(articleId),
    );
  }
}

class _ShareAction extends ConsumerWidget {
  final ResourceArticle article;
  const _ShareAction({required this.article});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: const Icon(Icons.ios_share_rounded),
      tooltip: 'Share',
      onPressed: () => ref
          .read(shareServiceProvider)
          .shareText(
            '${article.title}\n\n${article.summary}\n\n'
            'Source: ${article.sourceName} — ${article.sourceUrl}\n\n'
            'Shared from ForeSeeMe',
            subject: article.title,
          ),
    );
  }
}
