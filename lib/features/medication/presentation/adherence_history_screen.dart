import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_stats_model.dart';
import 'package:fyp_foreseeme/features/medication/presentation/adherence_analytics_provider.dart';
import 'package:fyp_foreseeme/features/medication/presentation/adherence_hero_card.dart';
import 'package:fyp_foreseeme/features/medication/presentation/adherence_history_data.dart';
import 'package:fyp_foreseeme/features/medication/presentation/adherence_history_helpers.dart';
import 'package:fyp_foreseeme/features/medication/presentation/calendar_strip_widget.dart';
import 'package:fyp_foreseeme/features/medication/presentation/medication_adherence_card.dart';
import 'package:fyp_foreseeme/features/medication/presentation/weekly_bar_chart_widget.dart';

class AdherenceHistoryScreen extends ConsumerWidget {
  const AdherenceHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(authStateProvider).value?.uid ?? '';
    final analyticsAsync = ref.watch(adherenceAnalyticsProvider(uid));

    final palette = context.fsmPalette;

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        foregroundColor: palette.textPrimary,
        title: Text('Adherence History', style: context.fsmText.titleLarge),
      ),
      body: analyticsAsync.when(
        loading: () => const DashboardLoading(),
        error: (error, _) => CenterDashboardMessage(message: error.toString()),
        data: (stats) => _DashboardContent(stats: stats),
      ),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({required this.stats});

  final List<AdherenceStatsModel> stats;

  @override
  Widget build(BuildContext context) {
    final meds = medicationStats(stats).toList();
    if (stats.isEmpty || meds.isEmpty) {
      return const CenterDashboardMessage(showIcon: true);
    }

    final children = <Widget>[
      AdherenceHeroCard(stats: stats),
      WeeklyBarChartWidget(stats: stats),
      CalendarStripWidget(stats: stats),
      ...meds.map((stat) => MedicationAdherenceCard(stat: stat)),
    ];

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 104),
      itemCount: children.length,
      separatorBuilder: (_, _) => const SizedBox(height: 18),
      itemBuilder: (context, index) {
        final delay = index < 3 ? index * 100 : 300 + ((index - 3) * 150);
        return StaggeredReveal(
          delay: Duration(milliseconds: delay),
          child: children[index],
        );
      },
    );
  }
}
