import 'package:flutter/material.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_stats_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/daily_status.dart';
import 'package:fyp_foreseeme/features/medication/presentation/adherence_history_data.dart';
import 'package:fyp_foreseeme/features/medication/presentation/adherence_history_helpers.dart';

class CalendarStripWidget extends StatefulWidget {
  const CalendarStripWidget({super.key, required this.stats});

  final List<AdherenceStatsModel> stats;

  @override
  State<CalendarStripWidget> createState() => _CalendarStripWidgetState();
}

class _CalendarStripWidgetState extends State<CalendarStripWidget> {
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_controller.hasClients) return;
      _controller.animateTo(
        _controller.position.maxScrollExtent,
        duration: const Duration(milliseconds: 620),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final days = _aggregateDays();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 420),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: ForeSeeMeSurface.card(context, radius: ForeSeeMeRadius.md),
      child: SizedBox(
        height: 48,
        child: ListView.separated(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          itemCount: days.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (context, index) => _DayCircle(day: days[index]),
        ),
      ),
    );
  }

  List<DailyStatus> _aggregateDays() {
    final meds = medicationStats(widget.stats);
    if (meds.isEmpty) return const [];
    final first = meds.first.last30DaysLog;
    return [
      for (final day in first)
        DailyStatus(date: day.date, status: _statusForDate(day.date)),
    ];
  }

  DailyAdherenceStatus _statusForDate(DateTime date) {
    final statuses = <DailyAdherenceStatus>[];
    for (final stat in medicationStats(widget.stats)) {
      final status = statusOn(stat, date);
      if (status != null) statuses.add(status);
    }
    final scheduled = statuses
        .where((s) => s != DailyAdherenceStatus.noSchedule)
        .toList();
    if (scheduled.isEmpty) return DailyAdherenceStatus.noSchedule;
    if (scheduled.contains(DailyAdherenceStatus.skipped)) {
      return DailyAdherenceStatus.skipped;
    }
    if (scheduled.contains(DailyAdherenceStatus.pending)) {
      return DailyAdherenceStatus.pending;
    }
    return DailyAdherenceStatus.taken;
  }
}

class _DayCircle extends StatelessWidget {
  const _DayCircle({required this.day});

  final DailyStatus day;

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final today = DateTime.now();
    final isToday = sameDay(today, day.date);
    final fill = statusFill(context, day.status);

    // Filled states carry a solid semantic tone → use its on-colour; neutral
    // (no-schedule / pending) days sit on a surface tint → use a text tier.
    final Color textColor = switch (day.status) {
      DailyAdherenceStatus.taken => context.fsmColors.onSuccess,
      DailyAdherenceStatus.skipped => palette.onError,
      DailyAdherenceStatus.noSchedule => palette.textTertiary,
      DailyAdherenceStatus.pending => palette.textSecondary,
    };

    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: isToday
            ? Border.all(color: palette.textPrimary, width: 2)
            : null,
      ),
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: fill,
          border: day.status == DailyAdherenceStatus.pending
              ? Border.all(color: palette.outlineVariant)
              : null,
        ),
        child: Text(
          day.date.day.toString(),
          style: context.fsmText.labelSmall?.copyWith(
            color: textColor,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
