import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';

/// Shared **recoverable error** surface.
///
/// One error language across the app: a calm centered panel with a glyph, a
/// title, a plain-language explanation, a Retry button, and an optional,
/// collapsed "technical details" disclosure — replacing the per-screen bespoke
/// "Couldn't load …" layouts.
///
/// This is strictly the **error** state (a load that failed and can be retried).
/// It is deliberately distinct from loading ([BrandLoading]/[AppSkeleton]),
/// connectivity loss ([OfflineState]), and empty ([EmptyState]) — never reuse it
/// for those. Classify offline separately (e.g. `isOfflineError`) before falling
/// back to this.
///
/// * **Theme-aware** — title/explanation/glyph tints come from the ForeSeeMe
///   design system for the ambient brightness (no hardcoded colours).
/// * **Accessible** — the title is a semantic header, the explanation reads as
///   text, and Retry / the details toggle are labelled buttons; the glyph is
///   excluded from semantics.
///
/// Pure presentation — no providers, repositories, or I/O. [onRetry] must invoke
/// the screen's existing refresh (e.g. `ref.invalidate(...)`).
class ErrorState extends StatelessWidget {
  final String title;
  final String explanation;

  /// Runs the caller's existing provider refresh. Presentation only.
  final VoidCallback onRetry;

  /// Optional developer-facing detail (e.g. the error's string form), shown
  /// behind a collapsed disclosure — never surfaced to users by default.
  final String? detail;

  final IconData icon;
  final String retryLabel;

  const ErrorState({
    super.key,
    required this.title,
    required this.explanation,
    required this.onRetry,
    this.detail,
    this.icon = Icons.error_outline_rounded,
    this.retryLabel = 'Retry',
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Icon(icon, size: 56, color: palette.textTertiary),
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
              explanation,
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: palette.textSecondary),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onRetry,
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
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(retryLabel),
            ),
            if (detail != null && detail!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              _TechnicalDetail(
                detail!.trim(),
                labelColor: palette.textTertiary,
                textColor: palette.textSecondary,
                borderColor: palette.outlineVariant,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Collapsed developer detail — hidden by default behind a labelled toggle.
class _TechnicalDetail extends StatefulWidget {
  final String detail;
  final Color labelColor;
  final Color textColor;
  final Color borderColor;

  const _TechnicalDetail(
    this.detail, {
    required this.labelColor,
    required this.textColor,
    required this.borderColor,
  });

  @override
  State<_TechnicalDetail> createState() => _TechnicalDetailState();
}

class _TechnicalDetailState extends State<_TechnicalDetail> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final caption = context.fsmText.bodySmall;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton.icon(
          onPressed: () => setState(() => _open = !_open),
          style: TextButton.styleFrom(
            foregroundColor: widget.labelColor,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: const Size(0, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: Icon(
            _open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
            size: 16,
          ),
          label: Text(
            _open ? 'Hide details' : 'Technical details',
            style: caption?.copyWith(color: widget.labelColor),
          ),
        ),
        // AnimatedSize smoothly grows/shrinks the panel as the detail reveals.
        AnimatedSize(
          duration:
              AppMotion.reduceMotion(context) ? Duration.zero : AppMotion.medium,
          curve: AppMotion.curve,
          alignment: Alignment.topCenter,
          child: _open
              ? Container(
                  constraints: const BoxConstraints(maxWidth: 340),
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(ForeSeeMeRadius.xs),
                    border: Border.all(color: widget.borderColor),
                  ),
                  child: SelectableText(
                    widget.detail,
                    textAlign: TextAlign.left,
                    style: caption?.copyWith(color: widget.textColor),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
