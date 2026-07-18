import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/medication/domain/enums/medication_enums.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_journey_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_stats_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/medication_model.dart';
import 'package:fyp_foreseeme/features/medication/presentation/achievement_badges_widget.dart';
import 'package:fyp_foreseeme/features/medication/presentation/adherence_hero_card.dart';
import 'package:fyp_foreseeme/features/medication/presentation/insight_cards_widget.dart';
import 'package:fyp_foreseeme/features/medication/presentation/medication_adherence_card.dart';
import 'package:fyp_foreseeme/features/medication/presentation/medication_journey_level_card.dart';
import 'package:fyp_foreseeme/features/medication/presentation/milestone_celebration_overlay.dart';
import 'package:fyp_foreseeme/features/medication/presentation/todays_mission_card.dart';
import 'package:fyp_foreseeme/features/medication/presentation/weekly_journey_timeline.dart';
import 'package:fyp_foreseeme/features/medication/presentation/weekly_reflection_card.dart';
import 'package:fyp_foreseeme/features/medication/presentation/widgets/day_journey_detail_sheet.dart';
import 'package:fyp_foreseeme/features/medication/presentation/widgets/medication_detail_sheet.dart';

// ── Fixtures ─────────────────────────────────────────────────────────────────

AdherenceStatsModel _stat({
  String medicationId = 'overall',
  String name = 'Overall',
  double weeklyRate = 0.9,
  int currentStreak = 4,
  int longestStreak = 6,
}) => AdherenceStatsModel(
  medicationId: medicationId,
  medicationName: name,
  dosage: '2 puffs',
  weeklyRate: weeklyRate,
  currentStreak: currentStreak,
  longestStreak: longestStreak,
  last30DaysLog: const [],
  last7DaysTakenCount: 6,
  last7DaysSkippedCount: 1,
);

MedicationModel _medication({bool isActive = true}) => MedicationModel(
  id: 'm1',
  uid: 'u1',
  name: 'Ventolin',
  dosage: '2 puffs',
  type: MedicationType.pill,
  frequency: MedicationFrequency.twiceDaily,
  reminderTimes: const ['09:00', '21:00'],
  isActive: isActive,
  createdAt: DateTime(2026, 1, 1),
);

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

DayJourneyCard _dayCard({
  DateTime? date,
  String weekdayLabel = 'Wednesday',
  bool isToday = false,
  DayJourneyStatus status = DayJourneyStatus.perfectDay,
  DoseCompletionState morning = DoseCompletionState.taken,
  DoseCompletionState evening = DoseCompletionState.taken,
  int completedDoses = 2,
  int totalDoses = 2,
  int missedDoses = 0,
  int adherencePercent = 100,
  String supportingMessage = 'Great work! You completed every medication today.',
}) => DayJourneyCard(
  date: date ?? DateTime(2026, 6, 30),
  weekdayLabel: weekdayLabel,
  isToday: isToday,
  status: status,
  morning: morning,
  evening: evening,
  completedDoses: completedDoses,
  totalDoses: totalDoses,
  missedDoses: missedDoses,
  adherencePercent: adherencePercent,
  supportingMessage: supportingMessage,
);

TodaysMission _mission({
  MissionState state = MissionState.pending,
  String title = 'Take your Ventolin',
  String message = 'Reward: maintain your 5-day streak.',
  String? medicationName = 'Ventolin',
  String? rawDeadlineTime = '21:00',
  int currentStreak = 5,
}) => TodaysMission(
  state: state,
  title: title,
  message: message,
  medicationName: medicationName,
  rawDeadlineTime: rawDeadlineTime,
  currentStreak: currentStreak,
);

void main() {
  group('AdherenceHeroCard', () {
    testWidgets('renders the story headline, message, and percent', (tester) async {
      const story = HeroStory(
        tone: HeroTone.excellent,
        emoji: '🏆',
        headline: 'Amazing work!',
        message: "You've maintained 92% adherence this week.",
      );
      await tester.pumpWidget(
        _host(AdherenceHeroCard(stats: [_stat(weeklyRate: 0.92)], story: story)),
      );
      await tester.pump(const Duration(milliseconds: 950)); // let the counter settle

      expect(find.text('Amazing work!'), findsOneWidget);
      expect(find.text("You've maintained 92% adherence this week."), findsOneWidget);
      expect(find.text('92%'), findsOneWidget);
    });
  });

  group('MedicationJourneyLevelCard', () {
    testWidgets('shows the current level and remaining percent to the next', (tester) async {
      await tester.pumpWidget(
        _host(
          const MedicationJourneyLevelCard(
            level: MedicationLevel.consistent,
            levelProgress: 0.5,
            percentToNextLevel: 10,
          ),
        ),
      );

      expect(find.text('Consistent'), findsOneWidget);
      expect(find.text('10% to Healthy Routine'), findsOneWidget);
    });

    testWidgets('the top level shows no "next" text', (tester) async {
      await tester.pumpWidget(
        _host(
          const MedicationJourneyLevelCard(
            level: MedicationLevel.asthmaChampion,
            levelProgress: 1.0,
            percentToNextLevel: 0,
          ),
        ),
      );

      expect(find.text('Asthma Champion'), findsOneWidget);
      expect(find.text("You've reached the top level"), findsOneWidget);
    });
  });

  group('AchievementBadgesWidget', () {
    testWidgets('shows the unlocked count and every badge, locked or not', (tester) async {
      final achievements = [
        const Achievement(id: 'a', emoji: '🔥', title: 'First Check-In', description: '', unlocked: true),
        const Achievement(id: 'b', emoji: '⭐', title: 'Perfect Week', description: '', unlocked: false),
      ];
      await tester.pumpWidget(_host(AchievementBadgesWidget(achievements: achievements)));
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('1/2'), findsOneWidget);
      expect(find.text('First Check-In'), findsOneWidget);
      expect(find.text('Perfect Week'), findsOneWidget);
    });
  });

  group('WeeklyReflectionCard', () {
    testWidgets('renders adherence, delta, streak, missed doses, best day, and attention', (tester) async {
      const reflection = WeeklyReflection(
        adherencePercent: 91,
        comparedToLastWeek: 8,
        longestStreak: 6,
        missedDoses: 2,
        bestDay: 'Wednesday',
        needsAttention: 'Evening medications',
      );
      await tester.pumpWidget(_host(const WeeklyReflectionCard(reflection: reflection)));
      await tester.pump(const Duration(milliseconds: 950));

      expect(find.text('This Week'), findsOneWidget);
      expect(find.text('91%'), findsOneWidget);
      expect(find.text('+8%'), findsOneWidget);
      expect(find.text('6 days'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Wednesday'), findsOneWidget);
      expect(find.text('Evening medications'), findsOneWidget);
    });

    testWidgets('a decline renders without a plus sign, framed neutrally', (tester) async {
      const reflection = WeeklyReflection(
        adherencePercent: 60,
        comparedToLastWeek: -8,
        longestStreak: 2,
        missedDoses: 4,
        bestDay: null,
        needsAttention: null,
      );
      await tester.pumpWidget(_host(const WeeklyReflectionCard(reflection: reflection)));
      await tester.pump(const Duration(milliseconds: 950));

      expect(find.text('-8%'), findsOneWidget);
      expect(find.text('Not enough data yet'), findsOneWidget);
      expect(find.text('Nothing — great job!'), findsOneWidget);
    });
  });

  group('InsightCardsWidget', () {
    testWidgets('renders each insight title and message', (tester) async {
      const insights = [
        InsightCard(emoji: '✨', title: 'Excellent consistency', message: "You haven't missed a dose in 6 days."),
      ];
      await tester.pumpWidget(_host(const InsightCardsWidget(insights: insights)));

      expect(find.text('Insights'), findsOneWidget);
      expect(find.text('Excellent consistency'), findsOneWidget);
      expect(find.text("You haven't missed a dose in 6 days."), findsOneWidget);
    });

    testWidgets('renders nothing when there are no insights', (tester) async {
      await tester.pumpWidget(_host(const InsightCardsWidget(insights: [])));
      expect(find.text('Insights'), findsNothing);
    });
  });

  group('MedicationAdherenceCard — performance tier (Feature 6)', () {
    testWidgets('shows an Excellent pill at high adherence', (tester) async {
      await tester.pumpWidget(_host(MedicationAdherenceCard(stat: _stat(weeklyRate: 0.95))));
      expect(find.text('Excellent'), findsOneWidget);
    });

    testWidgets('shows a Needs Attention pill at low adherence', (tester) async {
      await tester.pumpWidget(_host(MedicationAdherenceCard(stat: _stat(weeklyRate: 0.5))));
      expect(find.text('Needs Attention'), findsOneWidget);
    });
  });

  group('MilestoneCelebrationOverlay', () {
    testWidgets('renders the milestone and dismisses on tap', (tester) async {
      var dismissed = false;
      const milestone = Milestone(
        type: MilestoneType.levelUp,
        isMajor: true,
        emoji: '🌳',
        title: 'New Level Unlocked!',
        message: "You've reached Healthy Routine.",
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                MilestoneCelebrationOverlay(
                  milestone: milestone,
                  onDismiss: () => dismissed = true,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('New Level Unlocked!'), findsOneWidget);
      expect(find.text("You've reached Healthy Routine."), findsOneWidget);

      await tester.tap(find.text('Nice!'));
      await tester.pump();
      expect(dismissed, isTrue);
    });
  });

  group('MedicationDetailSheet — mini dashboard (Feature 9)', () {
    testWidgets('shows current adherence, next reminder, and streak when stat is provided', (tester) async {
      await tester.pumpWidget(
        _host(
          MedicationDetailSheet(
            medication: _medication(),
            stat: _stat(weeklyRate: 0.94, currentStreak: 8),
            onEdit: () {},
            onArchive: () {},
          ),
        ),
      );

      expect(find.text('94%'), findsOneWidget);
      expect(find.text('8 Days'), findsOneWidget);
      expect(find.text('Current Adherence'), findsOneWidget);
      expect(find.text('Next Reminder'), findsOneWidget);
      expect(find.text('Current Streak'), findsOneWidget);
    });

    testWidgets('omits the mini dashboard entirely when stat is null', (tester) async {
      await tester.pumpWidget(
        _host(
          MedicationDetailSheet(
            medication: _medication(),
            onEdit: () {},
            onArchive: () {},
          ),
        ),
      );

      expect(find.text('Current Adherence'), findsNothing);
      expect(find.text('Next Reminder'), findsNothing);
      expect(find.text('Current Streak'), findsNothing);
    });
  });

  group('WeeklyJourneyTimeline', () {
    testWidgets('renders all 7 day tiles with their weekday and status', (tester) async {
      // Wide enough that the lazy horizontal ListView builds all 7 tiles
      // (132dp + 12dp spacing each) without needing to scroll.
      tester.view.physicalSize = const Size(1400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final days = [
        for (var i = 0; i < 7; i++)
          _dayCard(
            weekdayLabel: 'Day$i',
            status: DayJourneyStatus.buildingHabit,
            completedDoses: 1,
            totalDoses: 2,
          ),
      ];
      await tester.pumpWidget(_host(WeeklyJourneyTimeline(days: days)));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text("This Week's Journey"), findsOneWidget);
      for (var i = 0; i < 7; i++) {
        expect(find.text('Day$i'), findsOneWidget);
      }
      expect(find.text('1/2 completed'), findsNWidgets(7));
    });

    testWidgets('marks today with a highlight badge', (tester) async {
      final days = [
        _dayCard(weekdayLabel: 'Mon', isToday: false),
        _dayCard(weekdayLabel: 'Tue', isToday: true),
      ];
      await tester.pumpWidget(_host(WeeklyJourneyTimeline(days: days)));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Now'), findsOneWidget);
    });

    testWidgets('tapping a day opens its detail sheet', (tester) async {
      final days = [
        _dayCard(
          weekdayLabel: 'Wednesday',
          status: DayJourneyStatus.perfectDay,
        ),
      ];
      await tester.pumpWidget(_host(WeeklyJourneyTimeline(days: days)));
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.text('Wednesday'));
      await tester.pumpAndSettle();

      expect(find.byType(DayJourneyDetailSheet), findsOneWidget);
      expect(find.text('Perfect Day'), findsWidgets);
    });

    testWidgets('renders nothing for an empty timeline', (tester) async {
      await tester.pumpWidget(_host(const WeeklyJourneyTimeline(days: [])));
      expect(find.text("This Week's Journey"), findsNothing);
    });
  });

  group('DayJourneyDetailSheet', () {
    testWidgets('shows morning/evening outcomes, adherence, and doses', (tester) async {
      final day = _dayCard(
        status: DayJourneyStatus.greatProgress,
        morning: DoseCompletionState.taken,
        evening: DoseCompletionState.missed,
        completedDoses: 1,
        totalDoses: 2,
        missedDoses: 1,
        adherencePercent: 50,
        supportingMessage:
            'You missed your evening medication. Tomorrow is another opportunity.',
      );
      await tester.pumpWidget(_host(DayJourneyDetailSheet(day: day)));

      expect(find.text('Great Progress'), findsOneWidget);
      expect(find.text('Morning Medication'), findsOneWidget);
      expect(find.text('Evening Medication'), findsOneWidget);
      expect(find.text('Taken'), findsOneWidget);
      expect(find.text('Missed'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      expect(
        find.text('You missed your evening medication. Tomorrow is another opportunity.'),
        findsOneWidget,
      );
    });

    testWidgets('tapping Got it dismisses the sheet', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => DayJourneyDetailSheet(day: _dayCard()),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(DayJourneyDetailSheet), findsOneWidget);

      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(find.byType(DayJourneyDetailSheet), findsNothing);
    });
  });

  group('TodaysMissionCard', () {
    testWidgets('pending shows the target medication and deadline', (tester) async {
      await tester.pumpWidget(
        _host(
          TodaysMissionCard(
            mission: _mission(
              state: MissionState.pending,
              title: 'Take your Ventolin',
              message: 'Reward: maintain your 5-day streak.',
              rawDeadlineTime: '21:00',
            ),
          ),
        ),
      );

      expect(find.text("Today's Mission"), findsOneWidget);
      expect(find.text('Take your Ventolin'), findsOneWidget);
      expect(find.text('Before 9:00 PM'), findsOneWidget);
      expect(find.text('Reward: maintain your 5-day streak.'), findsOneWidget);
    });

    testWidgets('allComplete celebrates without a deadline chip', (tester) async {
      await tester.pumpWidget(
        _host(
          TodaysMissionCard(
            mission: _mission(
              state: MissionState.allComplete,
              title: 'Mission Complete!',
              message: 'Great job! See you tomorrow.',
              medicationName: null,
              rawDeadlineTime: null,
            ),
          ),
        ),
      );

      expect(find.text('Mission Complete!'), findsOneWidget);
      expect(find.text('Great job! See you tomorrow.'), findsOneWidget);
      expect(find.textContaining('Before'), findsNothing);
    });

    testWidgets('dayOver and noMedications render their own supportive copy', (tester) async {
      await tester.pumpWidget(
        _host(
          TodaysMissionCard(
            mission: _mission(
              state: MissionState.dayOver,
              title: "Today's mission is behind you",
              message: 'Tomorrow is a fresh start.',
              medicationName: null,
              rawDeadlineTime: null,
            ),
          ),
        ),
      );
      expect(find.text('Tomorrow is a fresh start.'), findsOneWidget);

      await tester.pumpWidget(
        _host(
          TodaysMissionCard(
            mission: _mission(
              state: MissionState.noMedications,
              title: 'No medications scheduled today',
              message: 'Enjoy your day.',
              medicationName: null,
              rawDeadlineTime: null,
              currentStreak: 0,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('No medications scheduled today'), findsOneWidget);
    });
  });
}
