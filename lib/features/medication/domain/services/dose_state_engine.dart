import 'package:fyp_foreseeme/features/medication/domain/enums/medication_enums.dart';

enum DoseAvailabilityState {
  upcoming,
  actionable,
  completed,
  skipped,
  missed,
  futureDate,
  readOnly,
}

class DoseStateResult {
  final DoseAvailabilityState state;
  final AdherenceStatus effectiveStatus;
  final bool canMarkTaken;
  final bool canMarkSkipped;
  final bool shouldAutoMarkMissed;
  final bool isCurrentDose;
  final String label;

  const DoseStateResult({
    required this.state,
    required this.effectiveStatus,
    required this.canMarkTaken,
    required this.canMarkSkipped,
    required this.shouldAutoMarkMissed,
    required this.isCurrentDose,
    required this.label,
  });
}

class DoseStateEngine {
  static const Duration defaultActionLeadTime = Duration(minutes: 30);
  static const Duration defaultMissedGracePeriod = Duration(hours: 2);

  const DoseStateEngine._();

  static DoseStateResult determineDoseState({
    required DateTime selectedDate,
    required String reminderTime,
    required AdherenceStatus status,
    DateTime? confirmedAt,
    DateTime? now,
    Duration actionLeadTime = defaultActionLeadTime,
    Duration missedGracePeriod = defaultMissedGracePeriod,
  }) {
    final currentTime = now ?? DateTime.now();
    final selectedDay = dateOnly(selectedDate);
    final today = dateOnly(currentTime);
    final scheduledAt = scheduledDateTime(selectedDay, reminderTime);

    if (selectedDay.isAfter(today)) {
      return _result(DoseAvailabilityState.futureDate, status, 'Scheduled');
    }
    if (selectedDay.isBefore(today)) {
      if (status == AdherenceStatus.taken) {
        return _result(DoseAvailabilityState.completed, status, 'Taken');
      }
      if (status == AdherenceStatus.missed) {
        return _missedOrSkippedResult(
          confirmedAt: confirmedAt,
          missedAt: scheduledAt.add(missedGracePeriod),
          now: currentTime,
        );
      }
      return _result(
        DoseAvailabilityState.readOnly,
        AdherenceStatus.missed,
        'Missed',
      );
    }

    final actionableAt = scheduledAt.subtract(actionLeadTime);
    final missedAt = scheduledAt.add(missedGracePeriod);
    final isCurrentDose =
        !currentTime.isBefore(actionableAt) && currentTime.isBefore(missedAt);

    if (currentTime.isBefore(actionableAt)) {
      return DoseStateResult(
        state: DoseAvailabilityState.upcoming,
        effectiveStatus: status,
        canMarkTaken: false,
        canMarkSkipped: false,
        shouldAutoMarkMissed: false,
        isCurrentDose: false,
        label: 'Upcoming',
      );
    }

    if (status == AdherenceStatus.taken) {
      return _result(DoseAvailabilityState.completed, status, 'Taken');
    }
    if (status == AdherenceStatus.missed) {
      return _missedOrSkippedResult(
        confirmedAt: confirmedAt,
        missedAt: missedAt,
        now: currentTime,
      );
    }

    if (!currentTime.isBefore(missedAt)) {
      return DoseStateResult(
        state: DoseAvailabilityState.missed,
        effectiveStatus: AdherenceStatus.missed,
        canMarkTaken: false,
        canMarkSkipped: false,
        shouldAutoMarkMissed: true,
        isCurrentDose: false,
        label: 'Missed',
      );
    }

    return DoseStateResult(
      state: DoseAvailabilityState.actionable,
      effectiveStatus: status,
      canMarkTaken: true,
      canMarkSkipped: true,
      shouldAutoMarkMissed: false,
      isCurrentDose: isCurrentDose,
      label: 'Upcoming',
    );
  }

  static DateTime dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  static DateTime scheduledDateTime(DateTime date, String reminderTime) {
    final parts = reminderTime.split(':');
    final hour = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  static DoseStateResult _result(
    DoseAvailabilityState state,
    AdherenceStatus status,
    String label,
  ) {
    return DoseStateResult(
      state: state,
      effectiveStatus: status,
      canMarkTaken: false,
      canMarkSkipped: false,
      shouldAutoMarkMissed: false,
      isCurrentDose: false,
      label: label,
    );
  }

  static DoseStateResult _missedOrSkippedResult({
    required DateTime? confirmedAt,
    required DateTime missedAt,
    required DateTime now,
  }) {
    final isAutomaticMissed = confirmedAt == null
        ? !now.isBefore(missedAt)
        : !confirmedAt.isBefore(missedAt);

    return isAutomaticMissed
        ? _result(
            DoseAvailabilityState.missed,
            AdherenceStatus.missed,
            'Missed',
          )
        : _result(
            DoseAvailabilityState.skipped,
            AdherenceStatus.missed,
            'Skipped',
          );
  }
}
