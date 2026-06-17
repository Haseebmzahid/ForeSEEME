import 'package:fyp_foreseeme/features/medication/domain/models/adherence_stats_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/daily_status.dart';

Iterable<AdherenceStatsModel> medicationStats(
  List<AdherenceStatsModel> stats,
) => stats.where((stat) => stat.medicationId != 'overall');

DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

List<DateTime> last7Days() {
  final today = dateOnly(DateTime.now());
  return List.generate(7, (i) => today.subtract(Duration(days: 6 - i)));
}

String weekdayLabel(DateTime date) => switch (date.weekday) {
  DateTime.monday => 'Mon',
  DateTime.tuesday => 'Tue',
  DateTime.wednesday => 'Wed',
  DateTime.thursday => 'Thu',
  DateTime.friday => 'Fri',
  DateTime.saturday => 'Sat',
  _ => 'Sun',
};

DailyAdherenceStatus? statusOn(AdherenceStatsModel stat, DateTime date) {
  final matches = stat.last30DaysLog.where((day) => sameDay(day.date, date));
  return matches.isEmpty ? null : matches.first.status;
}

List<DayCounts> weeklyCounts(List<AdherenceStatsModel> stats) {
  return last7Days().map((date) {
    var taken = 0;
    var skipped = 0;
    for (final stat in medicationStats(stats)) {
      switch (statusOn(stat, date)) {
        case DailyAdherenceStatus.taken:
          taken++;
          break;
        case DailyAdherenceStatus.skipped:
          skipped++;
          break;
        case DailyAdherenceStatus.pending:
        case DailyAdherenceStatus.noSchedule:
        case null:
          break;
      }
    }
    return DayCounts(taken: taken, skipped: skipped);
  }).toList();
}

class DayCounts {
  const DayCounts({required this.taken, required this.skipped});
  final int taken;
  final int skipped;
  int get total => taken + skipped;
}
