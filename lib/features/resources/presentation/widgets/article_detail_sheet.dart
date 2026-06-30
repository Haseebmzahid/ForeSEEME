import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/app_design_v2.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/resource_article.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/resource_visuals.dart';

/// Full article view shown as a bottom sheet: title, body points, and a visible
/// **source citation** with a "View source" action. Pure widget — [onOpenSource]
/// is injected so it is testable without a launcher.
class ArticleDetailSheet extends StatelessWidget {
  final ResourceArticle article;
  final VoidCallback onOpenSource;

  const ArticleDetailSheet({
    super.key,
    required this.article,
    required this.onOpenSource,
  });

  @override
  Widget build(BuildContext context) {
    final visual = ResourceTopicVisual.of(article.topic);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, controller) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF141028).withValues(alpha: 0.98),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: AppColorsV2.stroke),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: visual.color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(visual.icon, color: visual.color),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Text(article.title, style: AppTextStylesV2.cardTitle),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (final point in article.body)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: visual.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        point,
                        style: AppTextStylesV2.body.copyWith(height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            // Source citation block.
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColorsV2.glassFill,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColorsV2.stroke),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.verified_rounded,
                        size: 15,
                        color: AppColorsV2.teal,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Source: ${article.sourceName}',
                          style: AppTextStylesV2.caption.copyWith(
                            color: AppColorsV2.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: onOpenSource,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColorsV2.teal,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                            color: AppColorsV2.teal.withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.open_in_new_rounded, size: 15),
                      label: const Text('View source'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'General guidance, not a substitute for professional medical '
              'advice. In an emergency, call Rescue 1122.',
              style: AppTextStylesV2.caption.copyWith(
                color: AppColorsV2.textFaint,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
