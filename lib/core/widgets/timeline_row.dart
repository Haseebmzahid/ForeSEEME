import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';

/// One chapter of a vertical timeline: a coloured icon dot, a connector line
/// down to the next entry (omitted on the last row), and an eyebrow/title/
/// subtitle stack. Domain-agnostic — callers map their own status/marker enum
/// to an (icon, color) pair before building this, so the visual stays reusable
/// across features (Explainable Health Intelligence's daily timeline, the
/// Geospatial activity timeline) without duplicating the connector-line layout.
class TimelineRow extends StatelessWidget {
  const TimelineRow({
    super.key,
    this.eyebrow,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.color,
    required this.isLast,
    this.onTap,
  });

  /// Small label above the title, e.g. "Morning" or a relative time. Omitted
  /// when `null` (the caller is grouping rows under its own section headers).
  final String? eyebrow;
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color color;
  final bool isLast;

  /// When set, the row becomes an accessible tap target (e.g. "open on map").
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;

    final row = IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: palette.outlineVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (eyebrow != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        eyebrow!,
                        style: text.labelSmall?.copyWith(
                          color: palette.textTertiary,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  Text(
                    title,
                    style: text.bodyLarge?.copyWith(color: palette.textPrimary),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: text.bodySmall?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return row;

    return Semantics(
      button: true,
      label: '${eyebrow ?? ''} $title ${subtitle ?? ''}'.trim(),
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(borderRadius: BorderRadius.circular(12), onTap: onTap, child: row),
        ),
      ),
    );
  }
}
