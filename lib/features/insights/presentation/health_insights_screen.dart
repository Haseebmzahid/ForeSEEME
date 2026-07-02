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
