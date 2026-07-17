import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/resource_article.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/resource_visuals.dart';

/// A self-care guide row: topic icon, title, and a visible **source citation**
/// (`Source: … · verified`). Tapping opens the full article.
class ResourceArticleCard extends StatelessWidget {
  final ResourceArticle article;
  final VoidCallback onTap;

  const ResourceArticleCard({
    super.key,
    required this.article,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final visual = ResourceTopicVisual.of(context, article.topic);
    final caption = text.bodySmall?.copyWith(
      fontSize: 11,
      color: palette.textTertiary,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ForeSeeMeRadius.md),
        child: Ink(
          padding: const EdgeInsets.all(15),
          decoration: ForeSeeMeSurface.card(context, radius: ForeSeeMeRadius.md),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: visual.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(visual.icon, color: visual.color, size: 20),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      article.title,
                      style: text.bodyMedium?.copyWith(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Source: ${article.sourceName}',
                            style: caption,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (article.verified) ...[
                          Text(' · ', style: caption),
                          Icon(
                            Icons.verified_rounded,
                            size: 12,
                            color: palette.secondary,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            'verified',
                            style: caption?.copyWith(color: palette.secondary),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: palette.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
