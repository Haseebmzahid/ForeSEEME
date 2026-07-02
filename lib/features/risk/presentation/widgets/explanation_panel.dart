import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fyp_foreseeme/core/theme/app_design_v2.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_attributions.dart';
import 'package:fyp_foreseeme/features/risk/domain/services/explanation_templater.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/confidence_explanation.dart';

/// The "Why this prediction?" trust surface (Sprint 5, Prompt 6).
///
/// Renders the genuine, model-derived top drivers and the confidence rationale
/// for the current city's estimate, in plain language. Pure presentation: it
/// reads the deterministically-templated [currentCityExplanationProvider] and
/// only formats/visualises it — no recomputation, no generated text (ADR-001;
/// the backend is the single source of truth).
///
/// Degrades gracefully: estimates produced before the explainability layer carry
/// no attributions, so the provider yields `null` and an honest
/// "explanation unavailable" note is shown instead of a fabricated one.
class ExplanationPanel extends ConsumerWidget {
  const ExplanationPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(currentCityExplanationProvider);
    return _PanelShell(
      child: view == null ? const _Unavailable() : _Explanation(view: view),
    );
  }
}

// ── Populated explanation ────────────────────────────────────────────────────

class _Explanation extends StatelessWidget {
  final ExplanationView view;
  const _Explanation({required this.view});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.psychology_outlined,
              size: 18,
              color: AppColorsV2.violet,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                view.title,
                style: AppTextStylesV2.cardTitle.copyWith(fontSize: 16),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(view.lead, style: AppTextStylesV2.body),
        const SizedBox(height: 14),
        for (final driver in view.drivers) ...[
          _DriverRow(driver: driver),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 2),
        const Divider(height: 1, color: AppColorsV2.stroke),
        const SizedBox(height: 14),
        ConfidenceExplanation(
          strength: view.strength,
          sentence: view.confidenceSentence,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(
              Icons.auto_awesome_outlined,
              size: 12,
              color: AppColorsV2.textFaint,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                view.provenanceNote,
                style: AppTextStylesV2.caption.copyWith(
                  color: AppColorsV2.textFaint,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A single driver line: a direction arrow (icon shape, not colour alone), the
/// human feature label, and the measured value. The full plain-language sentence
/// is the Semantics label so screen readers announce the whole thing.
class _DriverRow extends StatelessWidget {
  final ExplanationDriver driver;
  const _DriverRow({required this.driver});

  @override
  Widget build(BuildContext context) {
    final increases = driver.direction == ContributionDirection.increases;
    final color = increases ? AppColorsV2.riskHigh : AppColorsV2.riskLow;
    final icon = increases
        ? Icons.arrow_upward_rounded
        : Icons.arrow_downward_rounded;

    return Semantics(
      label: driver.sentence,
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              driver.label,
              style: AppTextStylesV2.body.copyWith(
                color: AppColorsV2.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (driver.valueText.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              driver.valueText,
              style: AppTextStylesV2.caption.copyWith(
                color: AppColorsV2.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Graceful unavailable state (pre-explainability estimates) ────────────────

class _Unavailable extends StatelessWidget {
  const _Unavailable();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'A detailed explanation is not available for this estimate.',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: AppColorsV2.textTertiary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ExplanationTemplater.title,
                  style: AppTextStylesV2.cardTitle.copyWith(fontSize: 16),
                ),
                const SizedBox(height: 6),
                Text(
                  "A detailed explanation isn't available for this estimate yet. "
                  'Newer weekly estimates include the drivers behind the risk.',
                  style: AppTextStylesV2.body,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared glass shell (matches the Risk Details cards) ──────────────────────

class _PanelShell extends StatelessWidget {
  final Widget child;
  const _PanelShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColorsV2.glassFill,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColorsV2.stroke),
      ),
      child: child,
    );
  }
}
