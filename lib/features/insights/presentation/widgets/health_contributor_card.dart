import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/features/insights/domain/models/health_intelligence.dart';

/// An expandable **health contributor** card (Sprint M-EHI, Section 3).
///
/// Pure presentation over a [HealthContributor]: a titled factor with a
/// qualitative status pill and a "because" line, expanding on tap to reveal an
/// optional detail line and a "Learn more" link to an existing in-app route.
/// It renders only stored/computed data — never a medical claim. The alert
/// [shellBranchRoutes] handling mirrors the app's existing deep-link rules so a
/// tab route is reached with `go()` and a stacked route with `push()`.
class HealthContributorCard extends StatefulWidget {
  const HealthContributorCard({super.key, required this.contributor});

  final HealthContributor contributor;

  /// Bottom-nav tab roots must be reached with `go()` (they are branches of the
  /// root StatefulShellRoute) — mirrors `AlertDeepLinkRouter.shellBranchRoutes`.
  static const Set<String> _shellBranchRoutes = {'/resources'};

  @override
  State<HealthContributorCard> createState() => _HealthContributorCardState();
}

class _HealthContributorCardState extends State<HealthContributorCard> {
  bool _expanded = false;

  bool get _canExpand =>
      widget.contributor.detail != null ||
      widget.contributor.learnMoreRoute != null;

  void _toggle() {
    if (!_canExpand) return;
    HapticFeedback.selectionClick();
    setState(() => _expanded = !_expanded);
  }

  (Color, IconData) _statusVisual(BuildContext context) {
    final colors = context.fsmColors;
    final palette = context.fsmPalette;
    return switch (widget.contributor.status) {
      ContributorStatus.excellent => (colors.success, Icons.check_circle_rounded),
      ContributorStatus.good => (colors.success, Icons.check_circle_outline_rounded),
      ContributorStatus.moderate => (colors.warning, Icons.remove_circle_outline_rounded),
      ContributorStatus.attention => (palette.error, Icons.error_outline_rounded),
      ContributorStatus.unavailable => (palette.textTertiary, Icons.help_outline_rounded),
      ContributorStatus.comingSoon => (palette.secondary, Icons.hourglass_empty_rounded),
    };
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final c = widget.contributor;
    final (statusColor, statusIcon) = _statusVisual(context);

    return Semantics(
      container: true,
      label:
          '${c.title}: ${c.status.label}. ${c.because}'
          '${c.detail != null ? ' ${c.detail}' : ''}',
      child: ExcludeSemantics(
        child: PressableScale(
          onTap: _toggle,
          child: AnimatedContainer(
            duration: AppMotion.medium,
            curve: AppMotion.curve,
            padding: const EdgeInsets.all(16),
            decoration: ForeSeeMeSurface.card(
              context,
              radius: ForeSeeMeRadius.md,
              borderColor: c.isComingSoon
                  ? null
                  : statusColor.withValues(alpha: 0.28),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(ForeSeeMeRadius.sm),
                      ),
                      child: Icon(statusIcon, size: 20, color: statusColor),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.title,
                            style: text.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            c.status.label,
                            style: text.labelSmall?.copyWith(
                              color: statusColor,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_canExpand)
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
                        duration: AppMotion.medium,
                        curve: AppMotion.curve,
                        child: Icon(
                          Icons.expand_more_rounded,
                          color: palette.textTertiary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  c.because,
                  style: text.bodyMedium?.copyWith(
                    color: palette.textSecondary,
                    height: 1.4,
                  ),
                ),
                // Expanded detail + learn-more, animated open/closed.
                AnimatedSize(
                  duration: AppMotion.medium,
                  curve: AppMotion.curve,
                  alignment: Alignment.topLeft,
                  child: _expanded
                      ? _ExpandedBody(contributor: c)
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExpandedBody extends StatelessWidget {
  const _ExpandedBody({required this.contributor});

  final HealthContributor contributor;

  void _openLearnMore(BuildContext context, String route) {
    if (HealthContributorCard._shellBranchRoutes.contains(route)) {
      context.go(route);
    } else {
      context.push(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final c = contributor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (c.detail != null) ...[
          const SizedBox(height: 10),
          Text(
            c.detail!,
            style: text.bodySmall?.copyWith(
              color: palette.textTertiary,
              height: 1.4,
            ),
          ),
        ],
        if (c.learnMoreRoute != null && c.learnMoreLabel != null) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _openLearnMore(context, c.learnMoreRoute!),
              icon: const Icon(Icons.menu_book_outlined, size: 16),
              label: Text(c.learnMoreLabel!),
              style: TextButton.styleFrom(
                foregroundColor: palette.primary,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: const Size(0, 44),
                tapTargetSize: MaterialTapTargetSize.padded,
                textStyle: text.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
