import 'package:fyp_foreseeme/features/medication/domain/enums/medication_enums.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_log_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_stats_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/daily_status.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/medication_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/repositories/adherence_log_repository.dart';
import 'package:fyp_foreseeme/features/medication/domain/repositories/medication_repository.dart';

class AdherenceAnalyticsService {
  final AdherenceLogRepository adherenceLogRepository;
  final MedicationRepository medicationRepository;

  const AdherenceAnalyticsService({
    required this.adherenceLogRepository,
    required this.medicationRepository,
  });

  Future<List<AdherenceStatsModel>> computeStats(String uid) async {
    if (uid.isEmpty) return const [];

    final today = _dateOnly(DateTime.now());
    final startDate = today.subtract(const Duration(days: 29));

    final results = await Future.wait([
      medicationRepository.getMedications(uid).first,
      adherenceLogRepository.getLogsForDateRange(uid, startDate, today).first,
    ]);

    final medications =
        (results[0] as List<MedicationModel>)
            .where((medication) => medication.isActive)
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    final logs = results[1] as List<AdherenceLogModel>;

    if (medications.isEmpty) return const [];

    final logsByMedicationAndDate = _groupLogsByMedicationAndDate(logs);
    final stats = <AdherenceStatsModel>[];

    var overallTaken = 0;
    var overallSkipped = 0;
    var overallScheduled = 0;

    for (final medication in medications) {
      final medicationStats = _computeMedicationStats(
        medication: medication,
        logsByDate: logsByMedicationAndDate[medication.id] ?? const {},
        startDate: startDate,
        today: today,
      );

      overallTaken += medicationStats._last7ScheduledTakenCount;
      overallSkipped += medicationStats.model.last7DaysSkippedCount;
      overallScheduled += medicationStats._last7ScheduledDoseCount;
      stats.add(medicationStats.model);
    }

    final overallWeeklyRate = overallScheduled == 0
        ? 0.0
        : overallTaken / overallScheduled;

    return [
      AdherenceStatsModel(
        medicationId: 'overall',
        medicationName: 'Overall',
        dosage: '',
        weeklyRate: overallWeeklyRate.clamp(0.0, 1.0),
        currentStreak: 0,
        longestStreak: 0,
        last30DaysLog: const [],
        last7DaysTakenCount: overallTaken,
        last7DaysSkippedCount: overallSkipped,
      ),
      ...stats,
    ];
  }

  _MedicationStatsResult _computeMedicationStats({
    required MedicationModel medication,
    required Map<DateTime, List<AdherenceLogModel>> logsByDate,
    required DateTime startDate,
    required DateTime today,
  }) {
    final last30DaysLog = <DailyStatus>[];
    final createdDate = _dateOnly(medication.createdAt);

    var longestStreak = 0;
    var runningStreak = 0;
    var last7TakenCount = 0;
    var last7SkippedCount = 0;
    var last7ScheduledDoseCount = 0;
    var last7ScheduledTakenCount = 0;

    for (var i = 0; i < 30; i++) {
      final date = startDate.add(Duration(days: i));
      final dayLogs = logsByDate[date] ?? const [];
      final status = _statusForDate(
        medication: medication,
        date: date,
        today: today,
        createdDate: createdDate,
        logs: dayLogs,
      );

      last30DaysLog.add(DailyStatus(date: date, status: status));

      if (status == DailyAdherenceStatus.taken) {
        runningStreak++;
        if (runningStreak > longestStreak) longestStreak = runningStreak;
      } else if (status == DailyAdherenceStatus.skipped) {
        runningStreak = 0;
      }

      if (_isWithinLast7Days(date, today) && _isScheduled(date, createdDate)) {
        final scheduledDoses = _scheduledDoseCount(medication);
        final takenDoses = _takenDoseCount(dayLogs, scheduledDoses);
        final skippedDoses = _skippedDoseCount(
          logs: dayLogs,
          scheduledDoses: scheduledDoses,
          takenDoses: takenDoses,
          date: date,
          today: today,
        );

        last7ScheduledDoseCount += scheduledDoses;
        last7ScheduledTakenCount += takenDoses;
        last7TakenCount += takenDoses;
        last7SkippedCount += skippedDoses;
      }
    }

    final weeklyRate = last7ScheduledDoseCount == 0
        ? 0.0
        : last7ScheduledTakenCount / last7ScheduledDoseCount;

    return _MedicationStatsResult(
      model: AdherenceStatsModel(
        medicationId: medication.id,
        medicationName: medication.name,
        dosage: medication.dosage,
        weeklyRate: weeklyRate.clamp(0.0, 1.0),
        currentStreak: runningStreak,
        longestStreak: longestStreak,
        last30DaysLog: last30DaysLog,
        last7DaysTakenCount: last7TakenCount,
        last7DaysSkippedCount: last7SkippedCount,
      ),
      last7ScheduledDoseCount: last7ScheduledDoseCount,
      last7ScheduledTakenCount: last7ScheduledTakenCount,
    );
  }

  DailyAdherenceStatus _statusForDate({
    required MedicationModel medication,
    required DateTime date,
    required DateTime today,
    required DateTime createdDate,
    required List<AdherenceLogModel> logs,
  }) {
    if (!_isScheduled(date, createdDate)) {
      return DailyAdherenceStatus.noSchedule;
    }

    final scheduledDoses = _scheduledDoseCount(medication);
    final takenDoses = _takenDoseCount(logs, scheduledDoses);
    final hasSkippedDose = logs.any(
      (log) => log.status == AdherenceStatus.missed,
    );

    if (hasSkippedDose) return DailyAdherenceStatus.skipped;
    if (takenDoses >= scheduledDoses) return DailyAdherenceStatus.taken;
    if (date.isBefore(today)) return DailyAdherenceStatus.skipped;

    return DailyAdherenceStatus.pending;
  }

  Map<String, Map<DateTime, List<AdherenceLogModel>>>
  _groupLogsByMedicationAndDate(List<AdherenceLogModel> logs) {
    final grouped = <String, Map<DateTime, List<AdherenceLogModel>>>{};

    for (final log in logs) {
      final medicationLogs = grouped.putIfAbsent(log.medicationId, () => {});
      final date = _dateOnly(log.date);
      medicationLogs.putIfAbsent(date, () => []).add(log);
    }

    return grouped;
  }

  int _scheduledDoseCount(MedicationModel medication) {
    if (medication.reminderTimes.isNotEmpty) {
      return medication.reminderTimes.length;
    }

    return medication.frequency.expectedReminderCount;
  }

  int _takenDoseCount(List<AdherenceLogModel> logs, int scheduledDoses) {
    final taken = logs
        .where((log) => log.status == AdherenceStatus.taken)
        .length;
    return taken.clamp(0, scheduledDoses);
  }

  int _skippedDoseCount({
    required List<AdherenceLogModel> logs,
    required int scheduledDoses,
    required int takenDoses,
    required DateTime date,
    required DateTime today,
  }) {
    final explicitlySkipped = logs
        .where((log) => log.status == AdherenceStatus.missed)
        .length;
    final unresolvedDoses = scheduledDoses - takenDoses - explicitlySkipped;
    final missingPastDoses = date.isBefore(today) ? unresolvedDoses : 0;

    return (explicitlySkipped + missingPastDoses).clamp(0, scheduledDoses);
  }

  bool _isWithinLast7Days(DateTime date, DateTime today) {
    final start = today.subtract(const Duration(days: 6));
    return !date.isBefore(start) && !date.isAfter(today);
  }

  bool _isScheduled(DateTime date, DateTime createdDate) {
    return !date.isBefore(createdDate);
  }

  DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }
}

class _MedicationStatsResult {
  final AdherenceStatsModel model;
  final int _last7ScheduledDoseCount;
  final int _last7ScheduledTakenCount;

  const _MedicationStatsResult({
    required this.model,
    required int last7ScheduledDoseCount,
    required int last7ScheduledTakenCount,
  }) : _last7ScheduledDoseCount = last7ScheduledDoseCount,
       _last7ScheduledTakenCount = last7ScheduledTakenCount;
}
