import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';

/// The visible **source citation** block shown at the end of every article:
/// the attributed authority plus a "View source" action. Every advisory in
/// this app must be a cited lookup (Rule 11) — this widget is the one place
/// that citation is rendered, reused by the article screen (previously
/// duplicated inline in the old bottom-sheet detail view).
class SourceCitationCard extends StatelessWidget {
  final String sourceName;
  final VoidCallback onOpenSource;

  const SourceCitationCard({
    super.key,
    required this.sourceName,
    required this.onOpenSource,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: ForeSeeMeSurface.card(context, radius: ForeSeeMeRadius.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_rounded, size: 15, color: palette.secondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Source: $sourceName',
                  style: text.bodySmall?.copyWith(color: palette.textSecondary),
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
                  borderRadius: BorderRadius.circular(ForeSeeMeRadius.xs),
                  side: BorderSide(color: palette.primary.withValues(alpha: 0.4)),
                ),
              ),
              icon: const Icon(Icons.open_in_new_rounded, size: 15),
              label: const Text('View source'),
            ),
          ),
        ],
      ),
    );
  }
}
