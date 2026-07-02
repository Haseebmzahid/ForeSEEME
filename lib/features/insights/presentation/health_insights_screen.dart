import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/app_design_v2.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/core/widgets/medical_disclaimer.dart';
import 'package:fyp_foreseeme/features/insights/presentation/adherence_insights_card.dart';
import 'package:fyp_foreseeme/features/insights/presentation/recommendations_card.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_card.dart';

/// A single, personalised **Health Insights** view (Sprint 4, Prompt 8).
///
/// Composes the existing risk, recommendation and adherence surfaces into one
/// non-diagnostic summary — it introduces **no new data sources**; each section
/// is an existing widget bound to its existing provider (`currentCityRiskProvider`,
/// `currentRecommendationProvider`, `adherenceInsightsProvider`). The content is
/// descriptive only and always carries the medical disclaimer below.
class HealthInsightsScreen extends ConsumerWidget {
  const HealthInsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColorsV2.shell,
      appBar: AppBar(
        backgroundColor: AppColorsV2.shell,
        elevation: 0,
        foregroundColor: AppColorsV2.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => context.pop(),
        ),
        title: Text('Health Insights', style: AppTextStylesV2.cardTitle),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          children: [
            // Sections fade + rise in on open, gently staggered (reduced-motion
            // aware via AppReveal). No layout change — only entrance motion.
            AppReveal(
              child: Text(
                'A calm, at-a-glance look at your environment, what may help, '
                'and how your routine is going.',
                style: AppTextStylesV2.body,
              ),
            ),
            const SizedBox(height: 20),

            AppReveal(
              delayMs: 70,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionLabel('ENVIRONMENTAL RISK'),
                  const SizedBox(height: 10),
                  const RiskCard(),
                ],
              ),
            ),
            const SizedBox(height: 22),

            AppReveal(
              delayMs: 140,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionLabel('WHAT MAY HELP'),
                  const SizedBox(height: 10),
                  const RecommendationsCard(),
                ],
              ),
            ),
            const SizedBox(height: 22),

            AppReveal(
              delayMs: 210,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionLabel('YOUR ROUTINE'),
                  const SizedBox(height: 10),
                  const AdherenceInsightsCard(),
                ],
              ),
            ),
            const SizedBox(height: 22),

            // Entry point to the Model Transparency page — how risk is produced
            // and its limits (Sprint 5, Prompt 7).
            const AppReveal(delayMs: 280, child: _TransparencyLink()),
            const SizedBox(height: 24),
          ],
              ),
            ),
            // Pinned non-diagnostic framing — always visible, consistent with
            // Risk Details and the alert inbox.
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: MedicalDisclaimer.banner(),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text, style: AppTextStylesV2.microLabel);
  }
}

/// Tappable row linking to the Model Transparency page — data provenance, label
/// methodology, and limits. Reinforces the honest-labelling story.
class _TransparencyLink extends StatelessWidget {
  const _TransparencyLink();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'How ForeSeeMe works — data, methodology and limits',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => context.push('/model-transparency'),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColorsV2.glassFill,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColorsV2.stroke),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: AppColorsV2.violet,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'How ForeSeeMe works',
                      style: AppTextStylesV2.body.copyWith(
                        color: AppColorsV2.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Data, label methodology, and honest limits',
                      style: AppTextStylesV2.caption,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppColorsV2.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
