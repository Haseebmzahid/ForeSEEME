import 'package:flutter_test/flutter_test.dart';
import 'package:fyp_foreseeme/features/medication/domain/enums/medication_enums.dart';
import 'package:fyp_foreseeme/features/medication/domain/services/dose_state_engine.dart';

void main() {
  final day = DateTime(2028, 2, 29);
  DoseStateResult state(
    DateTime now, {
    AdherenceStatus status = AdherenceStatus.pending,
    DateTime? confirmedAt,
  }) => DoseStateEngine.determineDoseState(
    selectedDate: day,
    reminderTime: '08:00',
    status: status,
    confirmedAt: confirmedAt,
    now: now,
  );

  test('FSM-U01 one microsecond before action window remains locked', () {
    final result = state(
      DateTime(2028, 2, 29, 7, 30).subtract(const Duration(microseconds: 1)),
    );
    expect(result.state, DoseAvailabilityState.upcoming);
    expect(result.canMarkTaken, isFalse);
    expect(result.canMarkSkipped, isFalse);
    expect(result.shouldAutoMarkMissed, isFalse);
  });
  test('FSM-U02 exact lead boundary enables both dose actions', () {
    final result = state(DateTime(2028, 2, 29, 7, 30));
    expect(result.state, DoseAvailabilityState.actionable);
    expect(result.canMarkTaken, isTrue);
    expect(result.canMarkSkipped, isTrue);
    expect(result.isCurrentDose, isTrue);
  });
  test('FSM-U03 final microsecond of grace remains actionable', () {
    final result = state(
      DateTime(2028, 2, 29, 10).subtract(const Duration(microseconds: 1)),
    );
    expect(result.canMarkTaken, isTrue);
    expect(result.isCurrentDose, isTrue);
    expect(result.shouldAutoMarkMissed, isFalse);
  });
  test('FSM-U04 exact grace boundary marks pending dose missed', () {
    final result = state(DateTime(2028, 2, 29, 10));
    expect(result.state, DoseAvailabilityState.missed);
    expect(result.effectiveStatus, AdherenceStatus.missed);
    expect(result.shouldAutoMarkMissed, isTrue);
    expect(result.canMarkTaken, isFalse);
    expect(result.canMarkSkipped, isFalse);
  });
  test('FSM-U05 confirmed taken dose stays completed after grace', () {
    final result = state(
      DateTime(2028, 2, 29, 12),
      status: AdherenceStatus.taken,
    );
    expect(result.state, DoseAvailabilityState.completed);
    expect(result.effectiveStatus, AdherenceStatus.taken);
    expect(result.shouldAutoMarkMissed, isFalse);
    expect(result.canMarkTaken, isFalse);
  });
  test('FSM-U06 leap day history is read only after month rollover', () {
    final result = state(DateTime(2028, 3, 1));
    expect(result.state, DoseAvailabilityState.readOnly);
    expect(result.effectiveStatus, AdherenceStatus.missed);
    expect(result.canMarkTaken, isFalse);
    expect(result.canMarkSkipped, isFalse);
    expect(result.shouldAutoMarkMissed, isFalse);
  });
  test(
    'FSM-U07 tomorrow dose stays locked even inside midnight lead window',
    () {
      final result = DoseStateEngine.determineDoseState(
        selectedDate: DateTime(2028, 3, 1),
        reminderTime: '00:10',
        status: AdherenceStatus.pending,
        now: DateTime(2028, 2, 29, 23, 50),
      );
      expect(result.state, DoseAvailabilityState.futureDate);
      expect(result.canMarkTaken, isFalse);
      expect(result.canMarkSkipped, isFalse);
      expect(result.shouldAutoMarkMissed, isFalse);
    },
  );
  test(
    'FSM-U08 manual skip before deadline remains skipped when viewed later',
    () {
      final result = state(
        DateTime(2028, 3, 1),
        status: AdherenceStatus.missed,
        confirmedAt: DateTime(2028, 2, 29, 9, 59),
      );
      expect(result.state, DoseAvailabilityState.skipped);
      expect(result.label, 'Skipped');
      expect(result.canMarkTaken, isFalse);
    },
  );
  test(
    'FSM-U09 confirmation at deadline is automatic missed not manual skip',
    () {
      final result = state(
        DateTime(2028, 2, 29, 11),
        status: AdherenceStatus.missed,
        confirmedAt: DateTime(2028, 2, 29, 10),
      );
      expect(result.state, DoseAvailabilityState.missed);
      expect(result.label, 'Missed');
      expect(result.shouldAutoMarkMissed, isFalse);
    },
  );
}
