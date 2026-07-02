import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/app_design_v2.dart';

/// Shared, reusable **non-diagnostic medical disclaimer** (Sprint 5, Prompt 3).
///
/// ForeSeeMe surfaces *environmental* risk estimates — never a clinical
/// diagnosis. This component states that, in one consistent voice, wherever
/// risk, insights, recommendations, or alerts are shown, so no screen can imply
/// medical advice. It replaces the per-screen bespoke disclaimer that previously
/// lived only on Health Insights.
///
/// Pure presentation (Design System v2): no providers, repositories, or I/O.
/// **Accessible** — an information icon paired with text (never colour alone),
/// merged into a single "Disclaimer: …" group for screen readers. The text tone
/// is [AppColorsV2.textTertiary] (not the faintest tier) so the safety framing
/// stays legible on the dark shell.
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
          ? _banner(text)
          : _inline(text),
    );
  }

  Widget _banner(String text) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColorsV2.shellRaised.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColorsV2.strokeSoft),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.info_outline_rounded,
          size: 16,
          color: AppColorsV2.textTertiary,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: AppTextStylesV2.caption.copyWith(height: 1.5)),
        ),
      ],
    ),
  );

  Widget _inline(String text) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(
        Icons.info_outline_rounded,
        size: 14,
        color: AppColorsV2.textTertiary,
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: AppTextStylesV2.caption.copyWith(height: 1.45),
        ),
      ),
    ],
  );
}

enum _DisclaimerVariant { banner, inline }
