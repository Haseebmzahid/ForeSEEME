import 'package:fyp_foreseeme/features/medication/domain/models/medication_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/services/dose_state_engine.dart';

/// Immutable read models backing the **Medications screen** (the "hub").
///
/// Everything here is a *projection* of data the app already stores —
/// `users/{uid}/medications` and `users/{uid}/adherence_logs` — resolved through
/// the app's own [DoseStateEngine]. Nothing is stored, nothing is invented, and
/// no value exists here that could not be recomputed from those two collections
/// plus the wall clock.

/// How the hub draws one of today's scheduled doses.
///
/// A *rendering* phase derived from [DoseStateResult] — never a source of
/// scheduling truth. The approved prototype has exactly four dose states, which
/// these mirror; [HubDosePhase.skipped] shares the prototype's `missed`
/// treatment because the prototype has no separate skipped tile, but keeps its
/// own label so a dose the user deliberately skipped is not reported back to
/// them as one they missed.
enum HubDosePhase {
  /// Confirmed taken — the prototype's `taken` tile.
  taken,

  /// Passed without confirmation — the prototype's `missed` tile.
  missed,

  /// Deliberately skipped by the user. Drawn as `missed`, labelled `SKIPPED`.
  skipped,

  /// The next dose the user can act on — the prototype's promoted `next` tile.
  next,

  /// Scheduled but not yet actionable — the prototype's `later` tile.
  later;

  /// The prototype's tile caption.
  String get label => switch (this) {
    HubDosePhase.taken => 'TAKEN',
    HubDosePhase.missed => 'MISSED',
    HubDosePhase.skipped => 'SKIPPED',
    HubDosePhase.next => 'NEXT UP',
    HubDosePhase.later => 'LATER',
  };

  /// Whether the phase uses the prototype's amber `--warn` treatment.
  bool get isWarn =>
      this == HubDosePhase.missed || this == HubDosePhase.skipped;
}

/// One scheduled dose on today's rail.
class HubDose {
  const HubDose({
    required this.medication,
    required this.time,
    required this.phase,
  });

  final MedicationModel medication;

  /// The user's own reminder time, `HH:mm`, exactly as stored.
  final String time;

  final HubDosePhase phase;

  @override
  String toString() =>
      'HubDose(${medication.name} @ $time, ${phase.name})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HubDose &&
          other.medication.id == medication.id &&
          other.time == time &&
          other.phase == phase;

  @override
  int get hashCode => Object.hash(medication.id, time, phase);
}

/// Today's standing for a single medication, shown as the card's status chip.
enum HubMedicationStatus {
  /// Every dose scheduled today has been confirmed taken.
  allTaken,

  /// Doses remain today and none has been missed or skipped.
  onTrack,

  /// One or more of today's doses were missed or skipped.
  behind,

  /// The medication carries no usable reminder time, so no dose is scheduled
  /// and there is nothing honest to report about today.
  noSchedule,
}

/// A medication plus the standing derived for it.
class HubMedication {
  const HubMedication({
    required this.medication,
    required this.status,
    required this.missedCount,
    required this.times,
  });

  final MedicationModel medication;
  final HubMedicationStatus status;

  /// How many of today's doses are missed or skipped. Only meaningful for
  /// [HubMedicationStatus.behind].
  final int missedCount;

  /// The medication's scheduled reminder times for today, sorted, `HH:mm`.
  /// Empty when the medication has no usable reminder time.
  final List<String> times;

  @override
  String toString() =>
      'HubMedication(${medication.name}, ${status.name}, missed: $missedCount)';
}

/// Everything the Medications screen draws, derived in one pass.
class MedicationHubSummary {
  const MedicationHubSummary({
    required this.medications,
    required this.doses,
    required this.takenCount,
    required this.missedCount,
    required this.nextDose,
  });

  /// Active medications, in the order the screen lists them.
  final List<HubMedication> medications;

  /// Today's scheduled doses, ordered by time.
  final List<HubDose> doses;

  /// Doses confirmed taken today.
  final int takenCount;

  /// Doses missed or skipped today.
  final int missedCount;

  /// The dose the prototype promotes — the first still-actionable dose today,
  /// falling back to the first later dose. Null once the day holds nothing
  /// still to confirm.
  final HubDose? nextDose;

  int get activeCount => medications.length;

  /// Total doses scheduled today (the `n of m taken` denominator).
  int get scheduledCount => doses.length;

  static const MedicationHubSummary empty = MedicationHubSummary(
    medications: [],
    doses: [],
    takenCount: 0,
    missedCount: 0,
    nextDose: null,
  );

  @override
  String toString() =>
      'MedicationHubSummary(active: $activeCount, doses: $scheduledCount, '
      'taken: $takenCount, missed: $missedCount, next: $nextDose)';
}
