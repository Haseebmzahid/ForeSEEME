import 'package:flutter/material.dart';
import '../theme/foreseeme_theme.dart';
import '../theme/foreseeme_tokens.dart';

/// Compact centered "no data" block (icon + title + subtitle).
///
/// All colour and type come from the ForeSeeMe design system, resolved for the
/// ambient brightness — no hardcoded colours.
class EmptyStateWidget extends StatelessWidget {
  final String title;
  final String subTitle;
  final IconData icon;

  const EmptyStateWidget({
    super.key,
    required this.title,
    required this.subTitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: ForeSeeMeSpacing.gutter),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 72,
            color: palette.primary.withValues(alpha: 0.42),
          ),
          const SizedBox(height: ForeSeeMeSpacing.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: text.titleLarge?.copyWith(color: palette.textPrimary),
          ),
          const SizedBox(height: ForeSeeMeSpacing.sm),
          Text(
            subTitle,
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}
