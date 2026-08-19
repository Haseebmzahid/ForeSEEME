import 'package:fyp_foreseeme/features/medication/domain/enums/medication_enums.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_log_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/medication_hub_state.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/medication_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/services/dose_state_engine.dart';

/// Derives everything the Medications screen shows from the two collections the
/// app already stores, plus the wall clock.
///
/// Pure and synchronous: no repository, no Firestore, no Flutter. It is called
/// from `medication_hub_providers.dart`, which supplies the medications and the
/// day's adherence logs from the existing streams.
///
/// **Every scheduling decision defers to [DoseStateEngine]**, the app's single
/// source of dose truth — this service only counts and labels what the engine
/// returns, so the Medications screen can never disagree with Daily Check-In
/// about whether a dose is due, taken or missed.
///
/// The dose expansion below (valid reminder times, sorted, capped at the
/// frequency's expected count) mirrors the *shape* of `check_in_screen.dart`'s
/// own expansion rather than reusing its code — that screen's version is
/// entangled with its optimistic-update and focus machinery, and is untouched
/// here. This follows the precedent `adherence_journey_service.dart` set for
/// the weekly timeline.
class MedicationHubService {
  const MedicationHubService();

  /// Builds the screen's read model.
  ///
  /// [medications] is the raw stream — inactive (archived) medications are
  /// filtered out here, so an archived medication is never scheduled, counted
  /// or listed. [logs] are the adherence logs for [now]'s calendar day.
  MedicationHubSummary summarise({
    required List<MedicationModel> medications,
    required List<AdherenceLogModel> logs,
    required DateTime now,
  }) {
    final today = DoseStateEngine.dateOnly(now);

    final active =
        medications.where((m) => m.isActive).toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    if (active.isEmpty) return MedicationHubSummary.empty;

    // Logs for the day, keyed by the dose they belong to.
    final logByDose = <String, AdherenceLogModel>{};
    for (final log in logs) {
      if (DoseStateEngine.dateOnly(log.date) != today) continue;
      logByDose['${log.medicationId}@${log.scheduledTime}'] = log;
    }

    // ── Resolve every scheduled dose through the engine ───────────────────
    final resolved = <_ResolvedDose>[];
    for (final medication in active) {
      for (final time in scheduledTimes(medication)) {
        final log = logByDose['${medication.id}@$time'];
        final state = DoseStateEngine.determineDoseState(
          selectedDate: today,
          reminderTime: time,
          status: log?.status ?? AdherenceStatus.pending,
          confirmedAt: log?.confirmedAt,
          now: now,
        );
        resolved.add(
          _ResolvedDose(medication: medication, time: time, state: state),
        );
      }
    }

    resolved.sort((a, b) => _minutesOf(a.time).compareTo(_minutesOf(b.time)));

    // The prototype promotes exactly one tile: the first dose the user can
    // actually act on right now.
    final nextIndex = resolved.indexWhere((d) => d.state.canMarkTaken);

    final doses = <HubDose>[];
    for (var i = 0; i < resolved.length; i++) {
      doses.add(
        HubDose(
          medication: resolved[i].medication,
          time: resolved[i].time,
          phase: _phaseOf(resolved[i].state, isNext: i == nextIndex),
        ),
      );
    }

    // ── Per-medication standing ──────────────────────────────────────────
    final byMedication = <String, List<HubDose>>{};
    for (final dose in doses) {
      (byMedication[dose.medication.id] ??= []).add(dose);
    }

    final hubMedications = [
      for (final medication in active)
        _statusFor(medication, byMedication[medication.id] ?? const []),
    ];

    final takenCount = doses
        .where((d) => d.phase == HubDosePhase.taken)
        .length;
    final missedCount = doses.where((d) => d.phase.isWarn).length;

    // "Next" for the hero and the Check-In prompt: the promoted dose, or the
    // earliest still-scheduled one when nothing is actionable yet.
    HubDose? nextDose;
    for (final dose in doses) {
      if (dose.phase == HubDosePhase.next) {
        nextDose = dose;
        break;
      }
    }
    if (nextDose == null) {
      for (final dose in doses) {
        if (dose.phase == HubDosePhase.later) {
          nextDose = dose;
          break;
        }
      }
    }

    return MedicationHubSummary(
      medications: hubMedications,
      doses: doses,
      takenCount: takenCount,
      missedCount: missedCount,
      nextDose: nextDose,
    );
  }

  /// The reminder times a medication is actually scheduled for today: the
  /// well-formed ones, in order, capped at what its frequency expects.
  ///
  /// Malformed entries are dropped rather than guessed at — a medication whose
  /// stored times are all unusable is reported as having no schedule, not as
  /// being on track.
  static List<String> scheduledTimes(MedicationModel medication) {
    final times = medication.reminderTimes.where(_isValidTime).toList()
      ..sort((a, b) => _minutesOf(a).compareTo(_minutesOf(b)));
    return times.take(medication.frequency.expectedReminderCount).toList();
  }

  HubMedication _statusFor(MedicationModel medication, List<HubDose> doses) {
    if (doses.isEmpty) {
      return HubMedication(
        medication: medication,
        status: HubMedicationStatus.noSchedule,
        missedCount: 0,
        times: const [],
      );
    }

    final missed = doses.where((d) => d.phase.isWarn).length;
    final allTaken = doses.every((d) => d.phase == HubDosePhase.taken);

    final status = missed > 0
        ? HubMedicationStatus.behind
        : allTaken
        ? HubMedicationStatus.allTaken
        : HubMedicationStatus.onTrack;

    return HubMedication(
      medication: medication,
      status: status,
      missedCount: missed,
      times: [for (final dose in doses) dose.time],
    );
  }

  static HubDosePhase _phaseOf(DoseStateResult state, {required bool isNext}) {
    // A confirmed dose reads as taken whatever the clock says. The engine
    // reports a dose the user logged ahead of its window as `upcoming`, because
    // that is its *availability*; on this screen the stored confirmation is the
    // honest thing to show.
    if (state.effectiveStatus == AdherenceStatus.taken) {
      return HubDosePhase.taken;
    }

    return switch (state.state) {
      DoseAvailabilityState.completed => HubDosePhase.taken,
      DoseAvailabilityState.skipped => HubDosePhase.skipped,
      DoseAvailabilityState.missed ||
      DoseAvailabilityState.readOnly => HubDosePhase.missed,
      DoseAvailabilityState.actionable =>
        isNext ? HubDosePhase.next : HubDosePhase.later,
      DoseAvailabilityState.upcoming ||
      DoseAvailabilityState.futureDate => HubDosePhase.later,
    };
  }

  static bool _isValidTime(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return false;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return false;
    return hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59;
  }

  static int _minutesOf(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return 0;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }
}

/// A dose paired with the engine's verdict, before it is labelled for drawing.
class _ResolvedDose {
  const _ResolvedDose({
    required this.medication,
    required this.time,
    required this.state,
  });

  final MedicationModel medication;
  final String time;
  final DoseStateResult state;
}
