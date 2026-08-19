import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fyp_foreseeme/features/medication/domain/models/medication_hub_state.dart';
import 'package:fyp_foreseeme/features/medication/domain/services/medication_hub_service.dart';
import 'package:fyp_foreseeme/features/medication/presentation/adherence_notifier.dart';

/// Derived state backing the **Medications screen**.
///
/// Every provider here is a projection of providers that already exist — no new
/// repository, no new Firestore path, no second medication data path. The
/// screen reads these instead of reaching for repositories itself (Golden Rule
/// 1), and all counting/labelling happens in [MedicationHubService] rather than
/// in a widget.

/// The derivation service. A `Provider` rather than a bare const so tests can
/// override it and so the dependency is explicit — mirrors
/// `profileCompletenessServiceProvider`.
final medicationHubServiceProvider = Provider<MedicationHubService>(
  (ref) => const MedicationHubService(),
);

/// The wall clock the screen reads today against.
///
/// A provider rather than a bare `DateTime.now()` so the whole screen shares
/// one instant — the day key and the dose states can never straddle midnight —
/// and so tests can pin it.
final hubNowProvider = Provider<DateTime>((ref) => DateTime.now());

/// Today's date at midnight, the key the adherence log stream is family'd on.
///
/// Derived from [hubNowProvider] so it is computed once per rebuild rather than
/// per watch — passing a raw `DateTime.now()` to a `family` would mint a new
/// provider (and a new Firestore listener) on every frame.
final hubTodayProvider = Provider<DateTime>((ref) {
  final now = ref.watch(hubNowProvider);
  return DateTime(now.year, now.month, now.day);
});

/// The Medications screen's read model: active medications, today's schedule
/// resolved through the dose-state engine, and the counts the hero reports.
///
/// Composes the existing `medicationsStreamProvider` and
/// `adherenceLogsStreamProvider`, so the screen stays real-time: a medication
/// added, edited or archived elsewhere, and a dose confirmed on Daily Check-In,
/// both land here without any extra plumbing.
final medicationHubProvider = Provider<AsyncValue<MedicationHubSummary>>((ref) {
  final now = ref.watch(hubNowProvider);
  final today = ref.watch(hubTodayProvider);
  final medicationsAsync = ref.watch(medicationsStreamProvider);
  final logsAsync = ref.watch(adherenceLogsStreamProvider(today));

  // Medications govern the screen's loading and error states: the log stream is
  // supporting detail, and a log read that has not landed yet must not blank
  // out a medication list that has. Until logs arrive every dose simply resolves
  // as unconfirmed, which is what it is.
  return medicationsAsync.whenData((medications) {
    return ref
        .watch(medicationHubServiceProvider)
        .summarise(
          medications: medications,
          logs: logsAsync.value ?? const [],
          now: now,
        );
  });
});
