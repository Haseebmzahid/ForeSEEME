import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fyp_foreseeme/core/theme/app_design_v2.dart';
import 'package:fyp_foreseeme/features/insights/domain/models/adherence_insights.dart';
import 'package:fyp_foreseeme/features/insights/presentation/insights_providers.dart';

/// Dashboard card surfacing **supportive** adherence insights (Prompt 7).
///
/// Pure presentation: it only watches [adherenceInsightsProvider] and renders the
/// computed [AdherenceInsights]. Deliberately encouraging — it shows streaks and
/// strengths and a gentle nudge, never a grade, percentage score, or blame. On
/// error it hides so a transient failure never breaks the dashboard.
class AdherenceInsightsCard extends ConsumerWidget {
  const AdherenceInsightsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adherenceInsightsProvider);

    return async.when(
      loading: () => const _CardShell(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(8),
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColorsV2.teal),
                strokeWidth: 2,
              ),
            ),
          ),
        ),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (insights) => _InsightsContent(insights: insights),
    );
  }
}

class _InsightsContent extends StatelessWidget {
  final AdherenceInsights insights;
  const _InsightsContent({required this.insights});

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.favorite_outline_rounded,
                size: 18,
                color: AppColorsV2.teal,
              ),
              const SizedBox(width: 8),
              Text('ADHERENCE INSIGHTS', style: AppTextStylesV2.microLabel),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            insights.headline,
            style: AppTextStylesV2.cardTitle.copyWith(fontSize: 17),
          ),
          const SizedBox(height: 6),
          Text(insights.supportiveMessage, style: AppTextStylesV2.body),
          if (insights.hasData) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _StatChip(
                  icon: Icons.local_fire_department_outlined,
                  label: 'Current streak',
                  value: _days(insights.currentStreakDays),
                ),
                _StatChip(
                  icon: Icons.emoji_events_outlined,
                  label: 'Best streak',
                  value: _days(insights.longestStreakDays),
                ),
                _StatChip(
                  icon: Icons.check_circle_outline_rounded,
                  label: 'Doses taken',
                  value: '${insights.takenCount}',
                ),
                if (insights.strongestBucket != null)
                  _StatChip(
                    icon: Icons.wb_sunny_outlined,
                    label: 'Most consistent',
                    value: insights.strongestBucket!.label,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _days(int n) => n == 1 ? '1 day' : '$n days';
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColorsV2.shellRaised.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColorsV2.strokeSoft),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColorsV2.teal),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppTextStylesV2.caption.copyWith(fontSize: 10),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                style: AppTextStylesV2.body.copyWith(
                  color: AppColorsV2.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shared glass shell matching the Sprint 3 v2 surfaces.
class _CardShell extends StatelessWidget {
  final Widget child;
  const _CardShell({required this.child});

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
