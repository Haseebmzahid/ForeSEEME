import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/core/widgets/medical_disclaimer.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/resource_article.dart';
import 'package:fyp_foreseeme/features/resources/presentation/article_bookmark_provider.dart';
import 'package:fyp_foreseeme/features/resources/presentation/resource_field_state.dart';
import 'package:fyp_foreseeme/features/resources/presentation/resources_providers.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/article_content_blocks.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/resource_center_chrome.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/resource_center_style.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/source_citation_card.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';

/// Full-screen reading experience for one [ResourceArticle], implemented from
/// the prototype's `ARTICLE DETAIL` state
/// (`docs/Design/ForeSeeMe Resource Center.html`).
///
/// The prototype opens the article as an overlay that grows out of the card the
/// user pushed; production keeps it a **routed** push (`/resources/article/:id`)
/// so back navigation is a real stack pop, and the card's own lift ([RcLift])
/// plus the router's scale-and-fade transition carry the same "it grew from
/// there" reading.
///
/// Everything the screen already did is kept — real heading / paragraph / tip /
/// warning structure, reading progress, the contextual "why you are seeing
/// this" line, the visible source citation, bookmarking, share and the
/// persistent non-diagnostic framing. What changed is the material.
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
    final estimate = ref.watch(currentCityRiskProvider).asData?.value;
    final theme = ResourceCenterTheme.of(
      context,
      energy: resourceFieldEnergy(estimate),
    );
    final pad = rcPad(context);

    return Scaffold(
      backgroundColor: theme.bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [theme.bg2, theme.bg],
                  stops: const [0.0, 0.4],
                ),
              ),
            ),
          ),
          if (article == null)
            _MissingArticle(theme: theme, pad: pad)
          else
            NotificationListener<ScrollNotification>(
              onNotification: (n) {
                _onScroll(n);
                return false;
              },
              child: _ArticleBody(article: article, theme: theme, pad: pad),
            ),
          // The prototype has no progress indicator; this one predates it and
          // is a real reading affordance, so it is kept — reduced to a hairline
          // at the very top edge rather than an app-bar rule, which the
          // prototype's chrome-less header has no room for.
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: SafeArea(
              bottom: false,
              child: _ReadingProgressBar(theme: theme, progress: _progress),
            ),
          ),
        ],
      ),
    );
  }
}

/// The tracked provenance line under the headline.
///
/// Each segment is only printed when it is genuinely known: the publisher badge
/// only for a recognised authority whose content has been checked, the
/// publication date only when the publisher states one, the verification date
/// only when a curator actually confirmed the source. A resource with none of
/// them prints its reading estimate and nothing else — never a placeholder, and
/// never a date stood in for another.
String _articleMeta(ResourceArticle article) {
  final parts = <String>[
    if (article.isTrustedSource) article.authority.shortLabel,
    if (article.isTrustedSource) 'VERIFIED SOURCE',
    '${article.readingMinutes} MIN READ',
  ];
  return parts.join(' · ');
}

class _ReadingProgressBar extends StatelessWidget {
  const _ReadingProgressBar({required this.theme, required this.progress});

  final ResourceCenterTheme theme;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 2,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: progress,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.accent,
              boxShadow: [BoxShadow(color: theme.halo, blurRadius: 8)],
            ),
          ),
        ),
      ),
    );
  }
}

class _ArticleBody extends ConsumerWidget {
  const _ArticleBody({
    required this.article,
    required this.theme,
    required this.pad,
  });

  final ResourceArticle article;
  final ResourceCenterTheme theme;
  final double pad;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final relevant = ref.watch(
      isTopicContextuallyRelevantProvider(article.topic),
    );
    final city = ref.watch(currentCityRiskProvider).asData?.value?.city;
    final related = ref
        .watch(orderedResourceArticlesProvider)
        .where((a) => a.id != article.id)
        .take(3)
        .toList();
    final catColor = resourceCatColor(theme, article.topic);
    // This screen is pushed inside `AppShell`, whose `extendBody: true` reports
    // the floating nav bar's height as the bottom inset. Reserve that plus the
    // prototype's own breathing room — never both the inset and a hardcoded
    // bar height.
    final bottomInset = 24 + MediaQuery.paddingOf(context).bottom;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _ArticleHeader(article: article, theme: theme, pad: pad),
        Transform.translate(
          offset: const Offset(0, -14),
          child: Padding(
            padding: EdgeInsets.fromLTRB(pad, 0, pad, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  resourceCatLabel(article.topic),
                  style: rcMono(context, size: 9, em: 0.24, color: catColor),
                ),
                const SizedBox(height: 12),
                Semantics(
                  header: true,
                  child: Text(
                    article.title,
                    style: rcDisplay(
                      context,
                      size: 27,
                      em: -0.025,
                      color: theme.fg,
                      height: 1.16,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _articleMeta(article),
                  style: rcMono(
                    context,
                    size: 9,
                    em: 0.12,
                    color: theme.mono,
                    height: 1.7,
                  ),
                ),
                const SizedBox(height: 18),
                _ReasonCard(
                  theme: theme,
                  text: relevant
                      ? 'Shown because your current environmental risk is '
                            'elevated in ${city ?? 'your area'}.'
                      : article.summary,
                ),
                const SizedBox(height: 18),
                ArticleContentBlocks(blocks: article.content, theme: theme),
                const SizedBox(height: 18),
                SourceCitationCard(
                  article: article,
                  theme: theme,
                  onOpenSource: () => ref
                      .read(launcherServiceProvider)
                      .openExternalUrl(article.sourceUrl),
                ),
              ],
            ),
          ),
        ),
        if (related.isNotEmpty)
          _RelatedRail(theme: theme, pad: pad, articles: related),
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 20, pad, 0),
          child: const MedicalDisclaimer.banner(),
        ),
        SizedBox(height: bottomInset),
      ],
    );
  }
}

/// The 190px header: the category's art, a halo, the floating field object, a
/// fade into the page, and the chrome-less controls.
class _ArticleHeader extends StatefulWidget {
  const _ArticleHeader({
    required this.article,
    required this.theme,
    required this.pad,
  });

  final ResourceArticle article;
  final ResourceCenterTheme theme;
  final double pad;

  @override
  State<_ArticleHeader> createState() => _ArticleHeaderState();
}

class _ArticleHeaderState extends State<_ArticleHeader>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  double _t = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `animation: float 10s` on the header's object. Reduced motion keeps the
    // object and drops the drift.
    if (_ticker == null && !AppMotion.reduceMotion(context)) {
      _ticker = createTicker((elapsed) {
        setState(() {
          _t = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
        });
      })..start();
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final top = MediaQuery.paddingOf(context).top;
    // `0%,100% { translateY(-7px) } 50% { translateY(9px) }` over 10s.
    final drift = -7 + 16 * (1 - math.cos((_t / 10 % 1) * 2 * math.pi)) / 2;

    return SizedBox(
      height: 190 + top,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ResourceArtLayer(
              art: resourceArtFor(widget.article.topic),
              theme: theme,
            ),
          ),
          // `left:50%;top:-30px;width:220;height:220` halo.
          Positioned(
            left: 0,
            right: 0,
            top: -30 + top,
            height: 220,
            child: Center(
              child: SizedBox(
                width: 220,
                height: 220,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: theme.bloom(theme.halo),
                  ),
                ),
              ),
            ),
          ),
          // `left:50%;top:34px;width:96;height:96` — the field object, smaller.
          Positioned(
            left: 0,
            right: 0,
            top: 34 + top + drift,
            height: 96,
            child: Center(
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: theme.sphere,
                  boxShadow: [
                    BoxShadow(color: theme.halo, blurRadius: 40),
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: theme.isDark ? 0.4 : 0.14,
                      ),
                      blurRadius: 40,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // `linear-gradient(180deg, transparent 40%, var(--bg2))`.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [theme.bg2.withValues(alpha: 0), theme.bg2],
                    stops: const [0.4, 1.0],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: widget.pad,
            right: widget.pad,
            top: 12 + top,
            child: Row(
              children: [
                _GlassCircleButton(
                  theme: theme,
                  tooltip: 'Back',
                  icon: Icons.arrow_back_rounded,
                  onTap: () => context.pop(),
                ),
                const Spacer(),
                _BookmarkAction(theme: theme, articleId: widget.article.id),
                const SizedBox(width: 8),
                _ShareAction(theme: theme, article: widget.article),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The prototype's chrome-less control: a 44px glass disc on the header art.
class _GlassCircleButton extends StatelessWidget {
  const _GlassCircleButton({
    required this.theme,
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final ResourceCenterTheme theme;
  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ClipOval(
            child: BackdropFilter(
              filter: rcBlur(context),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.solidify(context, theme.glass),
                  border: Border.all(color: theme.line),
                ),
                child: Icon(icon, size: 18, color: theme.fg),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The prototype's "why you are seeing this" strip.
class _ReasonCard extends StatelessWidget {
  const _ReasonCard({required this.theme, required this.text});

  final ResourceCenterTheme theme;
  final String text;

  @override
  Widget build(BuildContext context) {
    return RcGlass(
      theme: theme,
      radius: 16,
      blur: 18,
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 5,
            height: 5,
            margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.accent,
              boxShadow: [BoxShadow(color: theme.halo, blurRadius: 10)],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: rcBody(
                context,
                size: 11.5,
                color: theme.dim,
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `RELATED IN THE FIELD`.
class _RelatedRail extends StatelessWidget {
  const _RelatedRail({
    required this.theme,
    required this.pad,
    required this.articles,
  });

  final ResourceCenterTheme theme;
  final double pad;
  final List<ResourceArticle> articles;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 8, pad, 0),
          child: Text(
            'RELATED IN THE FIELD',
            style: rcMono(context, size: 9, em: 0.22, color: theme.mono),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 108,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.fromLTRB(pad, 0, pad, 4),
            itemCount: articles.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final article = articles[i];
              return SizedBox(
                width: 180,
                child: Semantics(
                  button: true,
                  label: '${resourceCatLabel(article.topic)}. ${article.title}',
                  child: PressableScale(
                    onTap: () => context
                        .push('/resources/article/${article.id}'),
                    child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                      child: RcGlass(
                        theme: theme,
                        radius: 18,
                        fill: theme.card,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: ResourceArtLayer(
                                art: resourceArtFor(article.topic),
                                theme: theme,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    resourceCatLabel(article.topic),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: rcMono(
                                      context,
                                      size: 8,
                                      em: 0.18,
                                      color: resourceCatColor(
                                        theme,
                                        article.topic,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Flexible(
                                    child: Text(
                                      article.title,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: rcDisplay(
                                        context,
                                        size: 13.5,
                                        color: theme.fg,
                                        height: 1.28,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MissingArticle extends StatelessWidget {
  const _MissingArticle({required this.theme, required this.pad});

  final ResourceCenterTheme theme;
  final double pad;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: pad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _GlassCircleButton(
              theme: theme,
              tooltip: 'Back',
              icon: Icons.arrow_back_rounded,
              onTap: () => context.pop(),
            ),
            const SizedBox(height: 24),
            Text(
              'Guide not found',
              style: rcDisplay(context, size: 21, color: theme.fg),
            ),
            const SizedBox(height: 10),
            Text(
              'This self-care guide is no longer available.',
              style: rcBody(context, size: 12.5, color: theme.dim, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookmarkAction extends ConsumerWidget {
  const _BookmarkAction({required this.theme, required this.articleId});

  final ResourceCenterTheme theme;
  final String articleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarked = ref.watch(
      bookmarkedArticleIdsProvider.select((ids) => ids.contains(articleId)),
    );
    return _GlassCircleButton(
      theme: theme,
      tooltip: bookmarked ? 'Remove bookmark' : 'Bookmark this guide',
      icon: bookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
      onTap: () =>
          ref.read(bookmarkedArticleIdsProvider.notifier).toggle(articleId),
    );
  }
}

class _ShareAction extends ConsumerWidget {
  const _ShareAction({required this.theme, required this.article});

  final ResourceCenterTheme theme;
  final ResourceArticle article;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _GlassCircleButton(
      theme: theme,
      tooltip: 'Share',
      icon: Icons.ios_share_rounded,
      onTap: () => ref
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
