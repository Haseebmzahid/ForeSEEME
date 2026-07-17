import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';

/// Shared, reusable **non-diagnostic medical disclaimer**.
///
/// ForeSeeMe surfaces *environmental* risk estimates — never a clinical
/// diagnosis. This component states that, in one consistent voice, wherever
/// risk, insights, recommendations, or alerts are shown, so no screen can imply
/// medical advice.
///
/// Pure presentation. Colour and type come from the ForeSeeMe design system,
/// resolved for the ambient brightness. **Accessible** — an information icon
/// paired with text (never colour alone), merged into a single "Disclaimer: …"
/// group for screen readers. The body copy uses the palette's *secondary* text
/// tone (not a faint tier) so the safety framing stays legible in light and dark.
///
/// Two variants:
/// * [MedicalDisclaimer.banner] — a full panel for screen footers (risk details,
///   insights, alert inbox).
/// * [MedicalDisclaimer.inline] — a compact one-liner for dense surfaces
///   (dashboard, onboarding).
class MedicalDisclaimer extends StatelessWidget {
  const MedicalDisclaimer.banner({super.key, this.message})
    : _variant = _DisclaimerVariant.banner;

  const MedicalDisclaimer.inline({super.key, this.message})
    : _variant = _DisclaimerVariant.inline;

  final _DisclaimerVariant _variant;

  /// Optional copy override. Defaults to [standardText] (banner) or [shortText]
  /// (inline). Callers rarely override — one voice is the point.
  final String? message;

  /// Canonical, non-diagnostic framing shown by the banner variant.
  static const String standardText =
      'ForeSeeMe shows environmental risk estimates based on weather and '
      'air-quality data — not a medical diagnosis or personal medical advice. '
      'Always consult a qualified healthcare professional about your health. '
      'In an emergency, call Rescue 1122.';

  /// Short framing for dense / inline surfaces.
  static const String shortText =
      'Environmental risk estimate — not a medical diagnosis or personal '
      'medical advice.';

  @override
  Widget build(BuildContext context) {
    final text =
        message ??
        (_variant == _DisclaimerVariant.banner ? standardText : shortText);

    // Read as a single labelled group; the icon is decorative.
    return Semantics(
      container: true,
      label: 'Disclaimer: $text',
      excludeSemantics: true,
      child: _variant == _DisclaimerVariant.banner
          ? _banner(context, text)
          : _inline(context, text),
    );
  }

  Widget _banner(BuildContext context, String text) {
    final palette = context.fsmPalette;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(ForeSeeMeRadius.sm),
        border: Border.all(color: palette.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: palette.textTertiary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: context.fsmText.bodySmall?.copyWith(
                color: palette.textSecondary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _inline(BuildContext context, String text) {
    final palette = context.fsmPalette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline_rounded,
          size: 14,
          color: palette.textTertiary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: context.fsmText.bodySmall?.copyWith(
              color: palette.textSecondary,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

enum _DisclaimerVariant { banner, inline }
