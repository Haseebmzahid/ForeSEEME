import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';

/// Shared meta-chip family for hospital surfaces (the list card AND the
/// detail sheet) — one recipe, so distance/rating/open-now never drift
/// between the two places they're shown. Every chip renders only when the
/// underlying data is present; none has a fabricated fallback.
class MetaChip extends StatelessWidget {
  final Color color;
  final IconData? icon;
  final String label;

  const MetaChip({super.key, required this.color, required this.label, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: icon == null ? 10 : 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(ForeSeeMeRadius.full),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: context.fsmText.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class DistanceChip extends StatelessWidget {
  final double distanceKm;
  const DistanceChip({super.key, required this.distanceKm});

  @override
  Widget build(BuildContext context) => MetaChip(
    color: context.fsmPalette.secondary,
    label: '${distanceKm.toStringAsFixed(1)} km',
  );
}

class RatingChip extends StatelessWidget {
  final double rating;
  final int? count;
  const RatingChip({super.key, required this.rating, this.count});

  @override
  Widget build(BuildContext context) {
    final label = count != null && count! > 0
        ? '${rating.toStringAsFixed(1)} (${count!})'
        : rating.toStringAsFixed(1);
    return Semantics(
      label: 'Rated $label out of 5',
      child: MetaChip(
        color: context.fsmColors.warning,
        icon: Icons.star_rounded,
        label: label,
      ),
    );
  }
}

class OpenNowChip extends StatelessWidget {
  final bool open;
  const OpenNowChip({super.key, required this.open});

  @override
  Widget build(BuildContext context) => MetaChip(
    color: open ? context.fsmColors.success : context.fsmPalette.textTertiary,
    icon: open ? Icons.schedule_rounded : Icons.schedule_outlined,
    label: open ? 'Open now' : 'Closed',
  );
}

/// Shared "Call" action — greyed out (never hidden) when the hospital has no
/// phone number, so its absence is visible rather than silently missing.
class CallActionButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;

  const CallActionButton({super.key, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: enabled ? 'Call this hospital' : 'No phone number available',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(11),
            child: Ink(
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                gradient: context.fsmColors.gradients.brand,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.call_rounded, size: 16, color: palette.onPrimary),
                  const SizedBox(width: 8),
                  Text(
                    'Call',
                    style: context.fsmText.bodyMedium?.copyWith(
                      color: palette.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared "Directions" action — always enabled (coordinates always exist).
class DirectionsActionButton extends StatelessWidget {
  final VoidCallback onTap;

  const DirectionsActionButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    return Semantics(
      button: true,
      label: 'Get directions',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: Ink(
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              color: palette.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: palette.outlineVariant),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.directions_rounded,
                  size: 16,
                  color: palette.textPrimary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Directions',
                  style: context.fsmText.bodyMedium?.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
