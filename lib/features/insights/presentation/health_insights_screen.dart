import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/core/widgets/medical_disclaimer.dart';
import 'package:fyp_foreseeme/features/insights/presentation/adherence_insights_card.dart';
import 'package:fyp_foreseeme/features/insights/presentation/environmental_insights_card.dart';
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
    final palette = context.fsmPalette;
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        foregroundColor: palette.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => context.pop(),
        ),
        title: Text('Health Insights', style: context.fsmText.titleLarge),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  ForeSeeMeSpacing.gutter,
                  ForeSeeMeSpacing.sm,
                  ForeSeeMeSpacing.gutter,
                  ForeSeeMeSpacing.gutter,
                ),
                children: [
                  // Sections fade + rise in on open, gently staggered (reduced-motion
                  // aware via AppReveal). No layout change — only entrance motion.
                  AppReveal(
                    child: Text(
                      'A calm, at-a-glance look at your environment, what may help, '
                      'and how your routine is going.',
                      style: context.fsmText.bodyLarge?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: ForeSeeMeSpacing.gutter),

                  AppReveal(
                    delayMs: 70,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionLabel('ENVIRONMENTAL RISK'),
                        const SizedBox(height: ForeSeeMeSpacing.md),
                        const RiskCard(),
                      ],
                    ),
                  ),
                  const SizedBox(height: ForeSeeMeSpacing.xxl),

                  // Genuine environmental drivers (from attributions) + most-relevant
                  // cited guidance first (Sprint 5, Prompt 10). Hides itself when there
                  // is no estimate/attributions, so no empty section shows.
                  const AppReveal(delayMs: 120, child: EnvironmentalInsightsCard()),
                  const SizedBox(height: ForeSeeMeSpacing.xxl),

                  AppReveal(
                    delayMs: 160,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionLabel('WHAT MAY HELP'),
                        const SizedBox(height: ForeSeeMeSpacing.md),
                        const RecommendationsCard(),
                      ],
                    ),
                  ),
                  const SizedBox(height: ForeSeeMeSpacing.xxl),

                  AppReveal(
                    delayMs: 210,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionLabel('YOUR ROUTINE'),
                        const SizedBox(height: ForeSeeMeSpacing.md),
                        const AdherenceInsightsCard(),
                      ],
                    ),
                  ),
                  const SizedBox(height: ForeSeeMeSpacing.xxl),

                  // Entry point to the proactive Weekly Health Report (Sprint 5,
                  // Prompt 8) — also delivered via the alert channel.
                  AppReveal(
                    delayMs: 260,
                    child: _NavLink(
                      icon: Icons.calendar_month_rounded,
                      iconColor: palette.secondary,
                      title: "This week's report",
                      subtitle: 'Your risk, routine and cited guidance',
                      route: '/weekly-report',
                    ),
                  ),
                  const SizedBox(height: ForeSeeMeSpacing.lg),

                  // Entry point to the Model Transparency page — how risk is produced
                  // and its limits (Sprint 5, Prompt 7).
                  AppReveal(
                    delayMs: 300,
                    child: _NavLink(
                      icon: Icons.info_outline_rounded,
                      iconColor: palette.tertiary,
                      title: 'How ForeSeeMe works',
                      subtitle: 'Data, label methodology, and honest limits',
                      route: '/model-transparency',
                    ),
                  ),
                  const SizedBox(height: ForeSeeMeSpacing.xxl),
                ],
              ),
            ),
            // Pinned non-diagnostic framing — always visible, consistent with
            // Risk Details and the alert inbox.
            const Padding(
              padding: EdgeInsets.fromLTRB(
                ForeSeeMeSpacing.gutter,
                ForeSeeMeSpacing.sm,
                ForeSeeMeSpacing.gutter,
                ForeSeeMeSpacing.lg,
              ),
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
    return Text(
      text,
      style: context.fsmText.labelSmall?.copyWith(letterSpacing: 1.2),
    );
  }
}

/// A tappable navigation row (glass card) used for the insights sub-pages —
/// the weekly report and the model transparency page.
class _NavLink extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String route;

  const _NavLink({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    return Semantics(
      button: true,
      label: '$title — $subtitle',
      child: InkWell(
        borderRadius: BorderRadius.circular(ForeSeeMeRadius.lg),
        onTap: () => context.push(route),
        child: Container(
          padding: const EdgeInsets.all(ForeSeeMeSpacing.lg),
          decoration: BoxDecoration(
            color: palette.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(ForeSeeMeRadius.lg),
            border: Border.all(color: palette.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: ForeSeeMeSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: text.bodyLarge?.copyWith(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: text.bodySmall?.copyWith(color: palette.textTertiary),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: palette.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
