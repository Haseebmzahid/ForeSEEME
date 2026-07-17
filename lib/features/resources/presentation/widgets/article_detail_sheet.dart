import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
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
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final visual = ResourceTopicVisual.of(context, article.topic);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, controller) => Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: ForeSeeMeSurface.stroke(context)),
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
                  color: palette.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(ForeSeeMeRadius.full),
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
                Expanded(child: Text(article.title, style: text.titleLarge)),
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
                        style: text.bodyMedium?.copyWith(
                          color: palette.textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            // Source citation block.
            Container(
              padding: const EdgeInsets.all(14),
              decoration: ForeSeeMeSurface.card(
                context,
                radius: ForeSeeMeRadius.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.verified_rounded,
                        size: 15,
                        color: palette.secondary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Source: ${article.sourceName}',
                          style: text.bodySmall?.copyWith(
                            color: palette.textSecondary,
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
                        foregroundColor: palette.primary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            ForeSeeMeRadius.xs,
                          ),
                          side: BorderSide(
                            color: palette.primary.withValues(alpha: 0.4),
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
              style: text.bodySmall?.copyWith(
                color: palette.textTertiary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
