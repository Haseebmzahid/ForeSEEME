import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
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
    final palette = context.fsmPalette;
    final reportAsync = ref.watch(weeklyReportProvider);

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
        title: Text('Weekly Report', style: context.fsmText.titleLarge),
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

// ── Content ──────────────────────────────────────────────────────────────────

class _Content extends StatelessWidget {
  final WeeklyReport report;
  const _Content({required this.report});

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        ForeSeeMeSpacing.gutter,
        ForeSeeMeSpacing.sm,
        ForeSeeMeSpacing.gutter,
        ForeSeeMeSpacing.xxl,
      ),
      children: [
        AppReveal(child: _Header(weekOf: report.weekOf)),
        const SizedBox(height: ForeSeeMeSpacing.lg),
        AppReveal(
          delayMs: 60,
          child: _SectionCard(
            icon: Icons.public_rounded,
            iconColor: palette.info,
            section: report.riskSection,
          ),
        ),
        const SizedBox(height: ForeSeeMeSpacing.md),
        AppReveal(
          delayMs: 120,
          child: _SectionCard(
            icon: Icons.favorite_outline_rounded,
            iconColor: palette.tertiary,
            section: report.adherenceSection,
          ),
        ),
        if (report.recommendationSection != null) ...[
          const SizedBox(height: ForeSeeMeSpacing.md),
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
    final palette = context.fsmPalette;
    final text = context.fsmText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'WEEK OF ${_formatWeek(weekOf)}',
          style: text.labelSmall?.copyWith(letterSpacing: 1.2),
        ),
        const SizedBox(height: ForeSeeMeSpacing.xs),
        Text('Your weekly health report', style: text.headlineLarge),
        const SizedBox(height: ForeSeeMeSpacing.xs),
        Text(
          'A calm summary of your environment, your routine, and what may help.',
          style: text.bodyLarge?.copyWith(color: palette.textSecondary),
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
    final palette = context.fsmPalette;
    final text = context.fsmText;
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
                  borderRadius: BorderRadius.circular(ForeSeeMeRadius.sm),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: ForeSeeMeSpacing.md),
              Expanded(
                child: Text(
                  section.title,
                  style: text.titleMedium?.copyWith(fontSize: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: ForeSeeMeSpacing.md),
          Text(
            section.body,
            style: text.bodyLarge?.copyWith(color: palette.textPrimary),
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
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final accent = palette.secondary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(ForeSeeMeRadius.lg),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.health_and_safety_outlined, size: 18, color: accent),
              const SizedBox(width: ForeSeeMeSpacing.sm),
              Text(
                section.title,
                style: text.titleMedium?.copyWith(color: accent, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: ForeSeeMeSpacing.sm),
          Text(
            section.body,
            style: text.bodyLarge?.copyWith(color: palette.textPrimary),
          ),
          const SizedBox(height: ForeSeeMeSpacing.sm),
          Row(
            children: [
              Icon(Icons.verified_outlined, size: 13, color: palette.textTertiary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Source: $source',
                  style: text.bodySmall?.copyWith(color: palette.textTertiary),
                ),
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
      decoration: ForeSeeMeSurface.card(context, radius: ForeSeeMeRadius.lg),
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
      padding: EdgeInsets.fromLTRB(
        ForeSeeMeSpacing.gutter,
        ForeSeeMeSpacing.sm,
        ForeSeeMeSpacing.gutter,
        ForeSeeMeSpacing.xxl,
      ),
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
