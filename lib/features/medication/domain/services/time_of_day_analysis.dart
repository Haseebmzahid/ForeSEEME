import 'package:fyp_foreseeme/features/medication/domain/enums/medication_enums.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_log_model.dart';

/// Morning/Evening dose-outcome tally for a date range — the shared building
/// block behind `AdherenceJourneyService`'s insights/achievements (Sprint
/// UX-M2.2) and `MedicationCoachingService`'s adaptive coaching (Sprint
/// UX-M2.5). Extracted once a second service needed the identical
/// computation, rather than duplicating it a third time.
class TimeOfDayBreakdown {
  final int morningTotal;
  final int morningTaken;
  final int eveningTotal;
  final int eveningTaken;

  const TimeOfDayBreakdown({
    required this.morningTotal,
    required this.morningTaken,
    required this.eveningTotal,
    required this.eveningTaken,
  });

  int get morningMissed => morningTotal - morningTaken;
  int get eveningMissed => eveningTotal - eveningTaken;

  double? get morningRate =>
      morningTotal == 0 ? null : morningTaken / morningTotal;
  double? get eveningRate =>
      eveningTotal == 0 ? null : eveningTaken / eveningTotal;
}

/// Buckets [logs] into Morning (5am-11:59am) / Evening (5pm-8:59pm) by
/// scheduled hour, counting only logs within [start]..[end] (inclusive,
/// date-only) and ignoring still-pending doses — only resolved taken/missed
/// outcomes count.
TimeOfDayBreakdown computeTimeOfDayBreakdown(
  List<AdherenceLogModel> logs, {
  required DateTime start,
  required DateTime end,
}) {
  var morningTotal = 0;
  var morningTaken = 0;
  var eveningTotal = 0;
  var eveningTaken = 0;

  for (final log in logs) {
    if (log.status == AdherenceStatus.pending) continue;
    final date = DateTime(log.date.year, log.date.month, log.date.day);
    if (date.isBefore(start) || date.isAfter(end)) continue;

    final hour = timeOfDayHourOf(log.scheduledTime);
    if (hour == null) continue;

    if (hour >= 5 && hour < 12) {
      morningTotal++;
      if (log.status == AdherenceStatus.taken) morningTaken++;
    } else if (hour >= 17 && hour < 21) {
      eveningTotal++;
      if (log.status == AdherenceStatus.taken) eveningTaken++;
    }
  }

  return TimeOfDayBreakdown(
    morningTotal: morningTotal,
    morningTaken: morningTaken,
    eveningTotal: eveningTotal,
    eveningTaken: eveningTaken,
  );
}

/// Parses the leading hour out of an "HH:mm" scheduled-time string. Shared so
/// every morning/evening classification in the medication feature agrees on
/// the same parsing rule.
int? timeOfDayHourOf(String scheduledTime) {
  final parts = scheduledTime.split(':');
  if (parts.length != 2) return null;
  return int.tryParse(parts[0]);
}
