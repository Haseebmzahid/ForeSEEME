import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_journey_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_stats_model.dart';
import 'package:fyp_foreseeme/features/medication/presentation/achievement_badges_widget.dart';
import 'package:fyp_foreseeme/features/medication/presentation/adherence_analytics_provider.dart';
import 'package:fyp_foreseeme/features/medication/presentation/adherence_hero_card.dart';
import 'package:fyp_foreseeme/features/medication/presentation/adherence_history_data.dart';
import 'package:fyp_foreseeme/features/medication/presentation/adherence_history_helpers.dart';
import 'package:fyp_foreseeme/features/medication/presentation/adherence_journey_provider.dart';
import 'package:fyp_foreseeme/features/medication/presentation/calendar_strip_widget.dart';
import 'package:fyp_foreseeme/features/medication/presentation/insight_cards_widget.dart';
import 'package:fyp_foreseeme/features/medication/presentation/medication_adherence_card.dart';
import 'package:fyp_foreseeme/features/medication/presentation/medication_journey_level_card.dart';
import 'package:fyp_foreseeme/features/medication/presentation/milestone_celebration_overlay.dart';
import 'package:fyp_foreseeme/features/medication/presentation/milestone_celebration_provider.dart';
import 'package:fyp_foreseeme/features/medication/presentation/todays_mission_card.dart';
import 'package:fyp_foreseeme/features/medication/presentation/weekly_journey_timeline.dart';
import 'package:fyp_foreseeme/features/medication/presentation/weekly_reflection_card.dart';

class AdherenceHistoryScreen extends ConsumerWidget {
  const AdherenceHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(authStateProvider).value?.uid ?? '';
    final journeyAsync = ref.watch(adherenceJourneyProvider(uid));

    // Feature 7: whenever a fresh journey arrives, check it for a
    // celebration-worthy milestone (at most one shown per computation).
    ref.listen(adherenceJourneyProvider(uid), (previous, next) {
      next.whenData(
        (journey) =>
            ref.read(milestoneCelebrationProvider.notifier).checkJourney(journey),
      );
    });

    final palette = context.fsmPalette;
    final milestone = ref.watch(milestoneCelebrationProvider);

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        foregroundColor: palette.textPrimary,
        title: Text('Adherence Journey', style: context.fsmText.titleLarge),
      ),
      body: Stack(
        children: [
          journeyAsync.when(
            loading: () => const DashboardLoading(),
            error: (error, _) => CenterDashboardMessage(message: error.toString()),
            data: (journey) {
              final stats = ref.watch(adherenceAnalyticsProvider(uid)).value ?? const [];
              return _DashboardContent(stats: stats, journey: journey);
            },
          ),
          if (milestone != null)
            MilestoneCelebrationOverlay(
              milestone: milestone,
              onDismiss: () =>
                  ref.read(milestoneCelebrationProvider.notifier).dismiss(),
            ),
        ],
      ),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({required this.stats, required this.journey});

  final List<AdherenceStatsModel> stats;
  final AdherenceJourneyModel journey;

  @override
  Widget build(BuildContext context) {
    final meds = medicationStats(stats).toList();
    if (stats.isEmpty || meds.isEmpty) {
      return const CenterDashboardMessage(showIcon: true);
    }

    final children = <Widget>[
      AdherenceHeroCard(stats: stats, story: journey.hero),
      MedicationJourneyLevelCard(
        level: journey.level,
        levelProgress: journey.levelProgress,
        percentToNextLevel: journey.percentToNextLevel,
      ),
      TodaysMissionCard(mission: journey.todaysMission),
      AchievementBadgesWidget(achievements: journey.achievements),
      WeeklyJourneyTimeline(days: journey.weeklyTimeline),
      CalendarStripWidget(stats: stats),
      WeeklyReflectionCard(reflection: journey.reflection),
      InsightCardsWidget(insights: journey.insights),
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
