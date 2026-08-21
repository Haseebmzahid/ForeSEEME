import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/features/resources/domain/models/resource_article.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/resource_center_style.dart';

/// Renders an article's [ArticleBlock]s in the Resource Center prototype's
/// reading material (`docs/Design/ForeSeeMe Resource Center.html`).
///
/// The prototype's article is prose plus a single boxed `KEY POINTS` list. The
/// stored content is richer — headings, paragraphs, tips and warnings — so the
/// mapping is: prose stays prose, a heading becomes a tracked mono rule, and a
/// **run** of tips or warnings is collected into one panel (`KEY POINTS` for
/// tips, `WHEN TO SEEK CARE` for warnings, which keeps the coral reserved for
/// escalation guidance rather than styling every aside the same). Grouping runs
/// rather than boxing each block one at a time is what makes the page read like
/// the prototype instead of a stack of callouts.
class ArticleContentBlocks extends StatelessWidget {
  const ArticleContentBlocks({
    super.key,
    required this.blocks,
    required this.theme,
  });

  final List<ArticleBlock> blocks;
  final ResourceCenterTheme theme;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    var i = 0;

    void gap() {
      if (children.isNotEmpty) children.add(const SizedBox(height: 14));
    }

    while (i < blocks.length) {
      final kind = blocks[i].kind;
      switch (kind) {
        case ArticleBlockKind.heading:
          gap();
          children.add(
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                blocks[i].text.toUpperCase(),
                style: rcMono(
                  context,
                  size: 9,
                  em: 0.22,
                  color: theme.mono,
                ),
              ),
            ),
          );
          i++;
        case ArticleBlockKind.paragraph:
          gap();
          children.add(
            Opacity(
              opacity: 0.9,
              child: Text(
                blocks[i].text,
                style: rcBody(
                  context,
                  size: 14.5,
                  color: theme.fg,
                  height: 1.68,
                ),
              ),
            ),
          );
          i++;
        case ArticleBlockKind.tip:
        case ArticleBlockKind.warning:
          final run = <String>[];
          while (i < blocks.length && blocks[i].kind == kind) {
            run.add(blocks[i].text);
            i++;
          }
          gap();
          children.add(
            _PointsPanel(
              theme: theme,
              label: kind == ArticleBlockKind.tip
                  ? 'KEY POINTS'
                  : 'WHEN TO SEEK CARE',
              accent: kind == ArticleBlockKind.tip
                  ? theme.accent
                  : theme.coral,
              points: run,
            ),
          );
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}

/// The prototype's boxed list: a tracked mono label over bulleted lines on a
/// hairline-rimmed glass panel.
class _PointsPanel extends StatelessWidget {
  const _PointsPanel({
    required this.theme,
    required this.label,
    required this.accent,
    required this.points,
  });

  final ResourceCenterTheme theme;
  final String label;
  final Color accent;
  final List<String> points;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: theme.solidify(context, theme.glass),
        border: Border.all(
          color: accent == theme.coral
              ? accent.withValues(alpha: 0.34)
              : theme.line,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: rcMono(
              context,
              size: 9,
              em: 0.2,
              color: accent == theme.coral ? accent : theme.mono,
            ),
          ),
          for (final point in points) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 4,
                  height: 4,
                  margin: const EdgeInsets.only(top: 8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Opacity(
                    opacity: 0.88,
                    child: Text(
                      point,
                      style: rcBody(
                        context,
                        size: 13.5,
                        color: theme.fg,
                        height: 1.55,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
