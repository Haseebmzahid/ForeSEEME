import 'package:fyp_foreseeme/features/medication/domain/models/adherence_stats_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/daily_status.dart';

Iterable<AdherenceStatsModel> medicationStats(
  List<AdherenceStatsModel> stats,
) => stats.where((stat) => stat.medicationId != 'overall');

DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

DailyAdherenceStatus? statusOn(AdherenceStatsModel stat, DateTime date) {
  final matches = stat.last30DaysLog.where((day) => sameDay(day.date, date));
  return matches.isEmpty ? null : matches.first.status;
}
