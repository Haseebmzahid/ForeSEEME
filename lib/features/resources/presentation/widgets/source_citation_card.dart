import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/resource_article.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/resource_center_style.dart';

/// The visible **source citation** at the end of every article: who published
/// the guidance, when they published it, when ForeSeeMe last checked the link,
/// and the way out to the full text.
///
/// Every advisory in this app must be a cited lookup (Rule 11) — this widget is
/// the one place that citation is rendered.
///
/// The catalogue stores a short original summary and links out rather than
/// reproducing a publisher's article, so this card carries the primary action:
/// **Read full guidance at WHO** (or whichever authority published it).
///
/// The two dates are deliberately separate. `Published` is the publisher's own
/// date and is omitted entirely when they do not state one; `Verified` is when
/// a ForeSeeMe curator last confirmed the source still serves that guidance.
/// Neither ever stands in for the other, and a missing date is shown as
/// missing rather than filled in.
class SourceCitationCard extends StatelessWidget {
  final ResourceArticle article;
  final ResourceCenterTheme theme;
  final VoidCallback onOpenSource;

  const SourceCitationCard({
    super.key,
    required this.article,
    required this.theme,
    required this.onOpenSource,
  });

  @override
  Widget build(BuildContext context) {
    final published = article.publishedAt;
    final verified = article.lastVerifiedAt;
    final provenance = <String>[
      if (published != null) 'Published ${formatResourceDate(published)}',
      if (verified != null) 'Verified ${formatResourceDate(verified)}',
    ].join(' · ');

    final action = article.isTrustedSource
        ? 'Read full guidance at ${article.authority.shortLabel}'
        : 'Read full guidance';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: theme.solidify(context, theme.glass),
        border: Border.all(color: theme.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            article.isTrustedSource ? 'VERIFIED SOURCE' : 'SOURCE',
            style: rcMono(context, size: 9, em: 0.2, color: theme.mono),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 5,
                height: 5,
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.accent,
                  boxShadow: [BoxShadow(color: theme.halo, blurRadius: 10)],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  article.sourceName,
                  style: rcBody(
                    context,
                    size: 12.5,
                    color: theme.dim,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
          if (provenance.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 15),
              child: Text(
                provenance,
                style: rcMono(
                  context,
                  size: 9,
                  em: 0.1,
                  color: theme.mono,
                  height: 1.6,
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Semantics(
            button: true,
            label: action,
            child: PressableScale(
              onTap: onOpenSource,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: theme.haloS,
                    border: Border.all(color: theme.accent),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          action,
                          textAlign: TextAlign.center,
                          style: rcMono(
                            context,
                            size: 11,
                            em: 0.06,
                            color: theme.fg,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.north_east_rounded,
                        size: 13,
                        color: theme.accent,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
