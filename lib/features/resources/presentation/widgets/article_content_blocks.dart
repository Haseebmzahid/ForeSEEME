import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/resource_article.dart';

/// Renders an article's [ArticleBlock] sequence with real reading structure —
/// section headings, body paragraphs, highlighted tips and warning callouts —
/// rather than a flat bullet list. Pure presentation over [ArticleBlock]
/// (already-cited content only; this widget invents no text).
class ArticleContentBlocks extends StatelessWidget {
  final List<ArticleBlock> blocks;
  final Color accent;

  const ArticleContentBlocks({
    super.key,
    required this.blocks,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final block in blocks)
          Padding(
            padding: const EdgeInsets.only(bottom: ForeSeeMeSpacing.md),
            child: _blockWidget(context, block),
          ),
      ],
    );
  }

  Widget _blockWidget(BuildContext context, ArticleBlock block) {
    final palette = context.fsmPalette;
    final text = context.fsmText;

    switch (block.kind) {
      case ArticleBlockKind.heading:
        return Padding(
          padding: const EdgeInsets.only(top: ForeSeeMeSpacing.sm),
          child: Text(
            block.text,
            style: text.titleMedium?.copyWith(color: palette.textPrimary),
          ),
        );

      case ArticleBlockKind.paragraph:
        return Text(
          block.text,
          style: text.bodyLarge?.copyWith(color: palette.textSecondary),
        );

      case ArticleBlockKind.tip:
        return _Callout(
          icon: Icons.lightbulb_outline_rounded,
          color: accent,
          text: block.text,
        );

      case ArticleBlockKind.warning:
        return _Callout(
          icon: Icons.priority_high_rounded,
          color: palette.error,
          text: block.text,
        );
    }
  }
}

class _Callout extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _Callout({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.all(ForeSeeMeSpacing.md),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(ForeSeeMeRadius.sm),
          border: Border.all(color: color.withValues(alpha: 0.32)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: ForeSeeMeSpacing.sm),
            Expanded(
              child: Text(
                text,
                style: context.fsmText.bodyMedium?.copyWith(
                  color: context.fsmPalette.textPrimary,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
