import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';

/// Shared "no data" surface.
///
/// One empty-state language across the app: a calm centered panel with a glyph
/// (or a custom [illustration]), a title, a description, and an optional CTA —
/// replacing the per-screen bespoke "No … yet" layouts.
///
/// This is strictly the **empty** state (a successful load that returned no
/// rows). It is deliberately distinct from loading ([BrandLoading]/[AppSkeleton]),
/// connectivity loss ([OfflineState]), and server errors — never reuse it for
/// those.
///
/// * **Theme-aware** — title, description, and glyph tints come from the
///   ForeSeeMe design system for the ambient brightness (no hardcoded colours).
/// * **Accessible** — the title is a semantic header, the description reads as
///   text, and the CTA is a labelled button; the decorative glyph/illustration is
///   excluded from semantics.
///
/// Pure presentation — no providers, repositories, or I/O. Wire [onAction] to an
/// existing navigation/refresh callback when a CTA is needed.
class EmptyState extends StatelessWidget {
  /// Default glyph, shown when no [illustration] is supplied.
  final IconData icon;

  final String title;
  final String description;

  /// Optional CTA label. Renders a button only when paired with [onAction].
  final String? actionLabel;

  /// Optional CTA callback (existing navigation/refresh — presentation only).
  final VoidCallback? onAction;

  /// Optional custom illustration shown instead of the [icon] glyph.
  final Widget? illustration;

  /// Glyph size (logical px). Smaller values suit tighter panels.
  final double iconSize;

  /// Outer padding around the centered content.
  final EdgeInsetsGeometry padding;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
    this.illustration,
    this.iconSize = 56,
    this.padding = const EdgeInsets.all(32),
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;

    final hasAction = actionLabel != null && onAction != null;

    return Center(
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: illustration ??
                  Icon(icon, size: iconSize, color: palette.textTertiary),
            ),
            const SizedBox(height: 18),
            Semantics(
              header: true,
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: text.titleMedium?.copyWith(color: palette.textPrimary),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: palette.textSecondary),
            ),
            if (hasAction) ...[
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(
                  foregroundColor: palette.primary,
                  side: BorderSide(
                    color: palette.primary.withValues(alpha: 0.45),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ForeSeeMeRadius.sm),
                  ),
                ),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
