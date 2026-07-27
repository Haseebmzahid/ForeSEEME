import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';

/// Shared fail-closed view for any admin screen: shown whenever
/// [isAdminProvider] is `false` (or errors) rather than the screen's real
/// content. Extracted from the original admin-override screen (Sprint 5 P13)
/// so every admin module under [AdminShell] renders the same denial, instead
/// of each screen re-implementing it (Sprint M8.1).
class NotAuthorizedView extends StatelessWidget {
  const NotAuthorizedView({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ForeSeeMeSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 48,
              color: palette.textTertiary,
            ),
            const SizedBox(height: ForeSeeMeSpacing.md),
            Text(
              'Not authorized',
              style: text.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: ForeSeeMeSpacing.sm),
            Text(
              'This area is restricted to operators. If you believe this is an '
              'error, contact an administrator.',
              style: text.bodyLarge?.copyWith(color: palette.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
