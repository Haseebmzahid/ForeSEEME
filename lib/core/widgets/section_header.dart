import 'package:flutter/material.dart';
import '../theme/foreseeme_theme.dart';
import '../theme/foreseeme_tokens.dart';

/// Shared section header: a tinted icon chip followed by a title.
///
/// The accent (chip fill, border, icon, and dark-mode glow) is the design
/// system's `secondary` tone, and the title uses the palette's primary text
/// colour — all brightness-aware, none hardcoded.
class SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const SectionHeader({super.key, required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final isDark = palette.isDark;
    final accent = palette.secondary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ForeSeeMeSpacing.gutter,
        ForeSeeMeSpacing.md,
        ForeSeeMeSpacing.gutter,
        ForeSeeMeSpacing.sm,
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: isDark ? 0.14 : 0.08),
              border: Border.all(
                color: accent.withValues(alpha: isDark ? 0.24 : 0.15),
              ),
              boxShadow: isDark
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.15),
                        blurRadius: 10,
                        spreadRadius: -2,
                      ),
                    ]
                  : const [],
            ),
            child: Icon(icon, color: accent, size: 16),
          ),
          const SizedBox(width: ForeSeeMeSpacing.sm),
          Text(
            title,
            style: context.fsmText.titleLarge?.copyWith(
              color: palette.textPrimary,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// The lighter sibling of [SectionHeader]: a small icon + uppercase
/// micro-caps label, no chip/circle background. For compact section framing
/// inside dense reading/list screens (Health Intelligence, Resource Center)
/// where [SectionHeader]'s larger icon-chip treatment would be too heavy.
///
/// One shared definition — previously reinvented per-screen (a private
/// `_SectionHeader` in Health Intelligence, a hand-rolled icon-less label in
/// the Resource Center); both now render identically from here.
class EyebrowHeader extends StatelessWidget {
  final String label;
  final IconData icon;

  const EyebrowHeader({super.key, required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    return Row(
      children: [
        Icon(icon, size: 16, color: palette.textTertiary),
        const SizedBox(width: 8),
        Text(
          label,
          style: context.fsmText.labelSmall?.copyWith(letterSpacing: 1.2),
        ),
      ],
    );
  }
}
