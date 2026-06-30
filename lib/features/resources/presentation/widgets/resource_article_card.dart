import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/app_design_v2.dart';
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
    final visual = ResourceTopicVisual.of(article.topic);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: AppColorsV2.glassFill,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColorsV2.stroke),
          ),
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
                      style: AppTextStylesV2.body.copyWith(
                        color: AppColorsV2.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Source: ${article.sourceName}',
                            style: AppTextStylesV2.caption.copyWith(
                              fontSize: 11,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (article.verified) ...[
                          Text(
                            ' · ',
                            style: AppTextStylesV2.caption.copyWith(
                              fontSize: 11,
                            ),
                          ),
                          const Icon(
                            Icons.verified_rounded,
                            size: 12,
                            color: AppColorsV2.teal,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            'verified',
                            style: AppTextStylesV2.caption.copyWith(
                              fontSize: 11,
                              color: AppColorsV2.teal,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColorsV2.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
