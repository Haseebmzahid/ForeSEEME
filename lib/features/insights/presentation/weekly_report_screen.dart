import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/app_design_v2.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/core/widgets/app_skeleton.dart';
import 'package:fyp_foreseeme/core/widgets/error_state.dart';
import 'package:fyp_foreseeme/core/widgets/medical_disclaimer.dart';
import 'package:fyp_foreseeme/core/widgets/offline_state.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/insights/domain/models/weekly_report.dart';
import 'package:fyp_foreseeme/features/insights/presentation/insights_providers.dart';

/// Weekly Health Report screen (Sprint 5, Prompt 8).
///
/// A calm, proactive digest that ties the week's environmental risk, the user's
/// adherence, and a cited recommendation into one non-diagnostic touchpoint.
/// Pure presentation: it composes nothing itself — it renders the
/// [weeklyReportProvider], which combines existing signals via the deterministic
/// [composeWeeklyReport]. The medical disclaimer is always present.
class WeeklyReportScreen extends ConsumerWidget {
  const WeeklyReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(weeklyReportProvider);

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
        title: Text('Weekly Report', style: AppTextStylesV2.cardTitle),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: AppMotion.stateSwitcher(
                context,
                reportAsync.when(
                  loading: () => const _ReportSkeleton(),
                  error: (error, _) {
                    void retry() {
                      ref.invalidate(userCityProvider);
                      ref.invalidate(weeklyReportProvider);
                    }

                    return isOfflineError(error)
                        ? OfflineState(onRetry: retry)
                        : ErrorState(
                            title: "Couldn't load your weekly report",
                            explanation:
                                'Something went wrong loading this. Please try '
                                'again.',
                            onRetry: retry,
                            detail: '$error',
                          );
                  },
                  data: (report) => _Content(report: report),
                ),
              ),
            ),
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

// ── Content ──────────────────────────────────────────────────────────────────

class _Content extends StatelessWidget {
  final WeeklyReport report;
  const _Content({required this.report});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        AppReveal(child: _Header(weekOf: report.weekOf)),
        const SizedBox(height: 18),
        AppReveal(
          delayMs: 60,
          child: _SectionCard(
            icon: Icons.public_rounded,
            iconColor: AppColorsV2.blue,
            section: report.riskSection,
          ),
        ),
        const SizedBox(height: 16),
        AppReveal(
          delayMs: 120,
          child: _SectionCard(
            icon: Icons.favorite_outline_rounded,
            iconColor: AppColorsV2.violet,
            section: report.adherenceSection,
          ),
        ),
        if (report.recommendationSection != null) ...[
          const SizedBox(height: 16),
          AppReveal(
            delayMs: 180,
            child: _RecommendationCard(
              section: report.recommendationSection!,
              source: report.recommendation!.source,
            ),
          ),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final DateTime weekOf;
  const _Header({required this.weekOf});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('WEEK OF ${_formatWeek(weekOf)}', style: AppTextStylesV2.microLabel),
        const SizedBox(height: 6),
        Text(
          'Your weekly health report',
          style: AppTextStylesV2.headline.copyWith(fontSize: 22),
        ),
        const SizedBox(height: 6),
        Text(
          'A calm summary of your environment, your routine, and what may help.',
          style: AppTextStylesV2.body,
        ),
      ],
    );
  }

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _formatWeek(DateTime d) =>
      '${_months[d.month - 1]} ${d.day}, ${d.year}';
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final WeeklyReportSection section;

  const _SectionCard({
    required this.icon,
    required this.iconColor,
    required this.section,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  section.title,
                  style: AppTextStylesV2.cardTitle.copyWith(fontSize: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            section.body,
            style: AppTextStylesV2.body.copyWith(
              color: AppColorsV2.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Cited-guidance card — always shows its source (the advisory is a looked-up
/// entry, never generated).
class _RecommendationCard extends StatelessWidget {
  final WeeklyReportSection section;
  final String source;

  const _RecommendationCard({required this.section, required this.source});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColorsV2.teal.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColorsV2.teal.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.health_and_safety_outlined,
                size: 18,
                color: AppColorsV2.teal,
              ),
              const SizedBox(width: 8),
              Text(
                section.title,
                style: AppTextStylesV2.cardTitle.copyWith(
                  color: AppColorsV2.teal,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            section.body,
            style: AppTextStylesV2.body.copyWith(color: AppColorsV2.textPrimary),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.verified_outlined,
                size: 13,
                color: AppColorsV2.textTertiary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Source: $source', style: AppTextStylesV2.caption),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Shared shell + skeleton ──────────────────────────────────────────────────

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

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

class _ReportSkeleton extends StatelessWidget {
  const _ReportSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      physics: NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: AppSkeleton(
        child: Column(
          children: [
            SkeletonBox(height: 70),
            SizedBox(height: 18),
            SkeletonBox(height: 120),
            SizedBox(height: 16),
            SkeletonBox(height: 120),
            SizedBox(height: 16),
            SkeletonBox(height: 130),
          ],
        ),
      ),
    );
  }
}
