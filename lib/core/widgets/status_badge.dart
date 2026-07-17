import 'package:flutter/material.dart';
import '../theme/foreseeme_theme.dart';
import '../theme/foreseeme_tokens.dart';
import '../../features/medication/domain/enums/medication_enums.dart';

/// Small status pill for a medication's adherence state.
///
/// Colour comes entirely from the ForeSeeMe design system's semantic tokens
/// (`success` / `error` / `warning`) — brightness-aware, never guessed — and is
/// always paired with an uppercase text label so state is never colour-only.
class StatusBadge extends StatelessWidget {
  final AdherenceStatus status;

  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final colors = context.fsmColors;

    final Color badgeColor = switch (status) {
      AdherenceStatus.taken => colors.success,
      AdherenceStatus.missed => context.fsmPalette.error,
      AdherenceStatus.pending => colors.warning,
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ForeSeeMeSpacing.md,
        vertical: 7.0,
      ),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(ForeSeeMeRadius.full),
        border: Border.all(
          color: badgeColor.withValues(alpha: 0.34),
          width: ForeSeeMeBorderWidth.thin,
        ),
      ),
      child: Text(
        status.name.toUpperCase(),
        style: context.fsmText.labelSmall?.copyWith(
          color: badgeColor,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
