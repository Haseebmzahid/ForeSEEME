import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/core/widgets/empty_state_widget.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_log_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/medication_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/enums/medication_enums.dart';
import 'package:fyp_foreseeme/features/medication/domain/services/dose_state_engine.dart';

import 'adherence_notifier.dart';
import 'notification_refresh_provider.dart';
import 'widgets/med_orbit_chrome.dart';
import 'widgets/med_orbit_field.dart';
import 'widgets/med_orbit_style.dart';

class DoseItem {
  final MedicationModel medication;
  final String timeString;
  final AdherenceStatus status;
  final DateTime? confirmedAt;

  DoseItem(this.medication, this.timeString, this.status, this.confirmedAt);

  int get hour => int.tryParse(timeString.split(':')[0]) ?? 0;

  String get timeSlot {
    if (hour >= 5 && hour < 12) return 'Morning';
    if (hour >= 12 && hour < 17) return 'Afternoon';
    if (hour >= 17 && hour < 21) return 'Evening';
    return 'Night';
  }
}

DateTime _dateOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

int _timeSortValue(String timeString) {
  final parts = timeString.split(':');
  if (parts.length != 2) return 0;
  final hour = int.tryParse(parts[0]) ?? 0;
  final minute = int.tryParse(parts[1]) ?? 0;
  return (hour * 60) + minute;
}

bool _isValidReminderTime(String timeString) {
  final parts = timeString.split(':');
  if (parts.length != 2) return false;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return false;
  return hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59;
}

bool _isScheduledForDate(MedicationModel medication, DateTime selectedDate) {
  return medication.isActive;
}

List<String> _scheduledReminderTimes(MedicationModel medication) {
  final reminderTimes = medication.reminderTimes.where(_isValidReminderTime).toList()
    ..sort((a, b) => _timeSortValue(a).compareTo(_timeSortValue(b)));
  return reminderTimes.take(medication.frequency.expectedReminderCount).toList();
}

List<DoseItem> _buildScheduledDoseItems({
  required List<MedicationModel> medications,
  required List<AdherenceLogModel> logs,
  required DateTime selectedDate,
  required String Function(String medicationId, DateTime date, String timeString) generateLogId,
}) {
  final normalizedSelectedDate = _dateOnly(selectedDate);
  final logsById = {for (final log in logs) log.id: log};
  final doseItems = <DoseItem>[];

  for (final medication in medications) {
    if (!_isScheduledForDate(medication, normalizedSelectedDate)) continue;

    for (final timeString in _scheduledReminderTimes(medication)) {
      final logId = generateLogId(medication.id, normalizedSelectedDate, timeString);
      final matchedLog = logsById[logId];
      final status = matchedLog?.status ?? AdherenceStatus.pending;

      doseItems.add(DoseItem(medication, timeString, status, matchedLog?.confirmedAt));
    }
  }

  doseItems.sort((a, b) => _timeSortValue(a.timeString).compareTo(_timeSortValue(b.timeString)));
  return doseItems;
}

/// A scheduled dose resolved against the dose-state engine, ready to draw.
///
/// Purely a render-time projection of [DoseItem] + [DoseStateResult] — it adds
/// no scheduling rule of its own.
class _OrbitDose {
  _OrbitDose({
    required this.item,
    required this.logId,
    required this.status,
    required this.state,
  });

  final DoseItem item;
  final String logId;

  /// Effective status, including an in-flight optimistic update.
  final AdherenceStatus status;

  final DoseStateResult state;

  MedicationModel get medication => item.medication;
  int get minutes => _timeSortValue(item.timeString);
  MedPeriod get period => MedPeriod.ofMinutes(minutes);
  bool get isCapsule => item.medication.type == MedicationType.syrup;
}

class DailyCheckInScreen extends ConsumerStatefulWidget {
  const DailyCheckInScreen({super.key});

  @override
  ConsumerState<DailyCheckInScreen> createState() => _DailyCheckInScreenState();
}

class _DailyCheckInScreenState extends ConsumerState<DailyCheckInScreen> {
  late DateTime _selectedDate;
  late final List<DateTime> _dateWindow;

  /// Focused dose index, per day — the prototype remembers where you were when
  /// you shuttle back to a day.
  final Map<DateTime, int> _focusByDate = {};

  /// Optimistic status by log id, cleared once the stream confirms it.
  final Map<String, AdherenceStatus> _optimisticStatus = {};

  /// Doses already handed to the auto-missed write, so it fires once each.
  final Set<String> _autoMissedQueued = {};

  /// Guards the mutation: one check-in commits at a time, so a double tap
  /// cannot write twice and Take-then-Skip cannot interleave.
  bool _isUpdating = false;

  /// The dose currently playing a check-in beat, and which beat it is on.
  String? _actionLogId;
  MedDoseAction _action = MedDoseAction.none;

  int _rippleTick = 0;
  bool _detailOpen = false;

  /// Holds focus on a dose that has just been checked in, so its new status is
  /// readable before the next pending dose takes over.
  Timer? _focusHoldTimer;

  late DateTime _now;
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    final today = _dateOnly(_now);
    _selectedDate = today;

    _dateWindow = List.generate(15, (index) {
      return today.add(Duration(days: index - 7));
    });

    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _focusHoldTimer?.cancel();
    super.dispose();
  }

  /// Ends any in-progress confirmation hold. Called whenever the user takes
  /// their own decision about what to look at, so the timer never yanks focus
  /// away from a dose they just chose.
  void _cancelFocusHold({bool release = false}) {
    if (_focusHoldTimer == null) return;
    _focusHoldTimer!.cancel();
    _focusHoldTimer = null;
    if (release) {
      _focusByDate.remove(_selectedDate);
      _actionLogId = null;
      _action = MedDoseAction.none;
    }
  }

  // ── Date navigation (unchanged behaviour, new chrome) ──────────────────────

  void _onDateSelected(DateTime date) {
    _cancelFocusHold(release: true);
    setState(() {
      _selectedDate = _dateOnly(date);
      _detailOpen = false;
    });
  }

  void _goDay(int delta) {
    final target = _selectedDate.add(Duration(days: delta));
    if (target.isBefore(_dateWindow.first) || target.isAfter(_dateWindow.last)) {
      return;
    }
    _onDateSelected(target);
  }

  bool get _canGoBack => _selectedDate.isAfter(_dateWindow.first);
  bool get _canGoForward => _selectedDate.isBefore(_dateWindow.last);

  // ── Focus along the temporal path ──────────────────────────────────────────

  int _focusIndex(List<_OrbitDose> doses) {
    if (doses.isEmpty) return 0;
    final stored = _focusByDate[_selectedDate];
    if (stored != null) return stored.clamp(0, doses.length - 1);
    final next = doses.indexWhere((d) => d.status == AdherenceStatus.pending);
    return next >= 0 ? next : doses.length - 1;
  }

  void _setFocus(int index, List<_OrbitDose> doses) {
    if (doses.isEmpty) return;
    final clamped = index.clamp(0, doses.length - 1);
    if (clamped == _focusIndex(doses)) return;
    _cancelFocusHold();
    setState(() {
      _focusByDate[_selectedDate] = clamped;
      _detailOpen = false;
    });
  }

  void _onDoseTapped(int index, List<_OrbitDose> doses) {
    if (index == _focusIndex(doses)) {
      setState(() => _detailOpen = !_detailOpen);
    } else {
      _setFocus(index, doses);
    }
  }

  // ── Check-in actions (same repository calls as before) ─────────────────────

  /// Commits a check-in, choreographing the dose object around the *existing*
  /// mutation rather than replacing it.
  ///
  /// Two beats play before the state lands — pick up → consume for Take,
  /// set down → withdraw for Skip — then the optimistic status commits, the
  /// next dose takes focus, and the write goes to the same notifier the dose
  /// cards always used. The animation never gates the write and the write never
  /// gates the animation.
  ///
  /// `_isUpdating` is checked and set with no `await` between, so a double tap
  /// (or Take-then-Skip) cannot produce a second mutation: the second tap
  /// returns before the first beat starts. It stays set until the write
  /// settles, which is also what greys the controls.
  Future<void> _markDose(
    _OrbitDose dose,
    AdherenceStatus newStatus, {
    required int focusIndex,
  }) async {
    if (_isUpdating) return;
    final canSubmit = newStatus == AdherenceStatus.taken
        ? dose.state.canMarkTaken
        : dose.state.canMarkSkipped;
    if (!canSubmit) return;

    final previousStatus = _optimisticStatus[dose.logId];
    final isTaking = newStatus == AdherenceStatus.taken;
    // Reduced motion keeps the meaning and drops the travel: the state commits
    // on the next frame instead of after the beats.
    final reduceMotion = AppMotion.reduceMotion(context);

    setState(() {
      _isUpdating = true;
      _actionLogId = dose.logId;
      _action = reduceMotion
          ? MedDoseAction.none
          : (isTaking ? MedDoseAction.lift : MedDoseAction.push);
    });

    if (!reduceMotion) {
      // Beat 1 — the dose responds in the hand.
      await Future<void>.delayed(
        Duration(milliseconds: isTaking ? 150 : 120),
      );
      if (!mounted) return;
      setState(() {
        _action = isTaking ? MedDoseAction.consume : MedDoseAction.recede;
      });
      // Beat 2 — it leaves, landing where the spatial system will take over.
      await Future<void>.delayed(
        Duration(milliseconds: isTaking ? 230 : 210),
      );
      if (!mounted) return;
    }

    setState(() {
      // The dose keeps focus, in a settled pose, for one confirmation beat:
      // long enough to read COMPLETED / SKIPPED on the panel before the next
      // pending dose takes over. Releasing focus immediately would swap the
      // readout to a different medication the instant the user acted.
      _action = MedDoseAction.settled;
      _optimisticStatus[dose.logId] = newStatus;
      _focusByDate[_selectedDate] = focusIndex;
      _detailOpen = false;
      if (isTaking && !reduceMotion) _rippleTick++;
    });

    _focusHoldTimer?.cancel();
    _focusHoldTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      // Hand focus back to the auto rule, which lands on the next pending dose.
      setState(() => _cancelFocusHold(release: true));
    });

    try {
      await ref.read(adherenceNotifierProvider.notifier).updateStatus(
            medication: dose.medication,
            date: _selectedDate,
            timeString: dose.item.timeString,
            status: newStatus,
          );
      _refreshNotifications();
    } catch (e) {
      if (!mounted) return;
      // Rollback: the dose returns to Pending and its controls come back. No
      // dramatic reversal animation — the object simply settles back onto the
      // path via its normal depth transition.
      setState(() {
        if (previousStatus == null) {
          _optimisticStatus.remove(dose.logId);
        } else {
          _optimisticStatus[dose.logId] = previousStatus;
        }
        _cancelFocusHold(release: true);
      });
      _showCheckInError(isTaking);
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }

  /// Calm, actionable copy on the existing snackbar channel — never a raw
  /// Firestore exception, and never an alarming one.
  void _showCheckInError(bool wasTaking) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          wasTaking
              ? "Couldn't save this dose as taken. Please try again."
              : "Couldn't save this dose as skipped. Please try again.",
        ),
      ),
    );
  }

  /// Best-effort: a completed/missed dose can change Today's Mission and
  /// today's escalation state (Phase 8 — cancel a nudge once a dose is
  /// resolved), so the coaching notification pipeline is refreshed right
  /// after every check-in. Never blocks or surfaces errors to the UI.
  void _refreshNotifications() {
    final uid = ref.read(authStateProvider).value?.uid;
    if (uid == null || uid.isEmpty) return;
    unawaited(refreshMedicationNotifications(ref.container, uid));
  }

  Future<void> _markMissedAutomatically(_OrbitDose dose) async {
    if (_autoMissedQueued.contains(dose.logId)) return;
    // A user check-in owns the write channel while it commits. Not queuing here
    // means the sweep simply retries on the next build.
    if (_isUpdating) return;
    _autoMissedQueued.add(dose.logId);

    setState(() => _optimisticStatus[dose.logId] = AdherenceStatus.missed);

    try {
      await ref.read(adherenceNotifierProvider.notifier).updateStatus(
            medication: dose.medication,
            date: _selectedDate,
            timeString: dose.item.timeString,
            status: AdherenceStatus.missed,
          );
      _refreshNotifications();
    } catch (_) {
      if (!mounted) return;
      _autoMissedQueued.remove(dose.logId);
      setState(() => _optimisticStatus.remove(dose.logId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't record a missed dose. Please try again."),
        ),
      );
    }
  }

  // ── Formatting ─────────────────────────────────────────────────────────────

  static const List<String> _months = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];
  static const List<String> _weekdays = [
    'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN',
  ];

  /// 24h "HH:mm" → the prototype's 12h readout, split into value and meridiem.
  static (String, String) _splitTime(int minutes) {
    final hour = minutes ~/ 60;
    final minute = minutes % 60;
    final readHour = hour % 12 == 0 ? 12 : hour % 12;
    return (
      '$readHour:${minute.toString().padLeft(2, '0')}',
      hour < 12 ? 'AM' : 'PM',
    );
  }

  static String _fullTime(int minutes) {
    final (value, meridiem) = _splitTime(minutes);
    return '$value $meridiem';
  }

  static String _fullTimeOf(DateTime value) =>
      _fullTime(value.hour * 60 + value.minute);

  String get _dateLabel =>
      '${_months[_selectedDate.month - 1]} ${_selectedDate.day}';

  String get _dayLabel {
    final today = _dateOnly(_now);
    final delta = _selectedDate.difference(today).inDays;
    return switch (delta) {
      0 => 'TODAY',
      -1 => 'YESTERDAY',
      1 => 'TOMORROW',
      _ => _weekdays[_selectedDate.weekday - 1],
    };
  }

  String get _fullDateLabel =>
      '${_weekdays[_selectedDate.weekday - 1]} ${_selectedDate.day} '
      '${_months[_selectedDate.month - 1]} ${_selectedDate.year}';

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = MedOrbitTheme.of(context);
    final medicationsAsync = ref.watch(medicationsStreamProvider);
    final logsAsync = ref.watch(adherenceLogsStreamProvider(_selectedDate));

    final error = medicationsAsync.error ?? logsAsync.error;
    if (error != null) {
      return Scaffold(
        backgroundColor: theme.bgMid,
        body: EmptyStateWidget(
          title: 'Error',
          subTitle: error.toString(),
          icon: Icons.error_outline,
        ),
      );
    }

    // Shuttling to another day swaps the log stream, so it briefly reports
    // loading. The stage chrome stays mounted through that so the date shuttle
    // never blinks out from under the finger; only the path waits.
    final isLoading = medicationsAsync.isLoading || logsAsync.isLoading;
    final doses = _resolveDoses(
      medicationsAsync.value ?? const [],
      logsAsync.value ?? const [],
    );

    return Scaffold(
      backgroundColor: theme.bgMid,
      body: _buildStage(context, theme, doses, isLoading),
    );
  }

  List<_OrbitDose> _resolveDoses(
    List<MedicationModel> medications,
    List<AdherenceLogModel> logs,
  ) {
    final generateLogId =
        ref.read(adherenceNotifierProvider.notifier).generateLogId;

    final items = _buildScheduledDoseItems(
      medications: medications,
      logs: logs,
      selectedDate: _selectedDate,
      generateLogId: generateLogId,
    );

    final doses = <_OrbitDose>[];
    for (final item in items) {
      final logId = generateLogId(
        item.medication.id,
        _selectedDate,
        item.timeString,
      );
      final optimistic = _optimisticStatus[logId];
      // The stream is the source of truth; an optimistic value is dropped the
      // moment Firestore confirms it (or supersedes it).
      if (optimistic != null && optimistic == item.status) {
        _optimisticStatus.remove(logId);
      }
      final status = _optimisticStatus[logId] ?? item.status;

      doses.add(
        _OrbitDose(
          item: item,
          logId: logId,
          status: status,
          state: DoseStateEngine.determineDoseState(
            selectedDate: _selectedDate,
            reminderTime: item.timeString,
            status: status,
            confirmedAt: item.confirmedAt,
            now: _now,
          ),
        ),
      );
    }

    // Same automatic bookkeeping the dose cards used to perform, now swept once
    // per build across the day rather than once per card.
    final pendingAutoMissed = doses
        .where(
          (d) =>
              d.state.shouldAutoMarkMissed &&
              d.status == AdherenceStatus.pending &&
              !_autoMissedQueued.contains(d.logId),
        )
        .toList();
    if (pendingAutoMissed.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        for (final dose in pendingAutoMissed) {
          _markMissedAutomatically(dose);
        }
      });
    }

    return doses;
  }

  Widget _buildStage(
    BuildContext context,
    MedOrbitTheme theme,
    List<_OrbitDose> doses,
    bool isLoading,
  ) {
    final focus = _focusIndex(doses);
    final nextIndex = doses.indexWhere(
      (d) => d.status == AdherenceStatus.pending,
    );
    final focused = doses.isEmpty ? null : doses[focus];

    MedOrbitPhase phaseOf(int index) => medOrbitPhaseOf(
      doses[index].state,
      isNext: index == nextIndex,
    );

    final focusedPhase = focused == null
        ? MedOrbitPhase.pending
        : phaseOf(focus);

    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(decoration: BoxDecoration(gradient: theme.stage)),
        ),
        Positioned.fill(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 1100),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              gradient: theme.atmosphere(
                focused?.period ?? MedPeriod.afternoon,
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: theme.vignette),
            ),
          ),
        ),
        SafeArea(
          bottom: false,
          child: Column(
            children: [
              const SizedBox(height: 6),
              MedOrbitHeader(
                ticks: [
                  for (var i = 0; i < doses.length; i++)
                    MedAdherenceTick(phase: phaseOf(i)),
                ],
                adherenceLabel: doses.isEmpty
                    ? '—'
                    : '${doses.where((d) => d.status == AdherenceStatus.taken).length}'
                          ' / ${doses.length}',
                dateLabel: _dateLabel,
                dayLabel: _dayLabel,
                onPreviousDay: _canGoBack ? () => _goDay(-1) : null,
                onNextDay: _canGoForward ? () => _goDay(1) : null,
                // Pushed, not `go` — the form is a child screen of whatever
                // opened it, so Back returns here rather than switching to the
                // Medications tab.
                onAddMedication: () => context.push('/medications/add'),
              ),
              Expanded(
                child: isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          strokeCap: StrokeCap.round,
                        ),
                      )
                    : Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(
                            child: MedOrbitField(
                              rippleTick: _rippleTick,
                              onFocusStep: (step) =>
                                  _setFocus(focus + step, doses),
                              onDayStep: _goDay,
                              doses: [
                                for (var i = 0; i < doses.length; i++)
                                  _doseView(doses, i, focus, phaseOf(i)),
                              ],
                            ),
                          ),
                          if (doses.isNotEmpty)
                            Positioned(
                              left: 14,
                              top: 22,
                              bottom: 16,
                              width: 64,
                              child: MedMeridianRail(
                                dots: [
                                  for (var i = 0; i < doses.length; i++)
                                    MedRailDot(
                                      minutes: doses[i].minutes,
                                      phase: phaseOf(i),
                                    ),
                                ],
                                activePeriod: focused?.period,
                                nowMinutes: _selectedDate == _dateOnly(_now)
                                    ? _now.hour * 60 + _now.minute
                                    : null,
                              ),
                            ),
                        ],
                      ),
              ),
              if (!isLoading)
                Stack(
                  children: [
                    _focusPanel(context, focused, focusedPhase, focus),
                    const Positioned(
                      top: 0,
                      left: 22,
                      right: 22,
                      child: MedHairlineRule(),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  MedOrbitDoseView _doseView(
    List<_OrbitDose> doses,
    int index,
    int focus,
    MedOrbitPhase phase,
  ) {
    final dose = doses[index];
    final (time, meridiem) = _splitTime(dose.minutes);

    return MedOrbitDoseView(
      id: dose.logId,
      slot: index - focus,
      phase: phase,
      isCapsule: dose.isCapsule,
      badge: switch (dose.state.state) {
        DoseAvailabilityState.completed => MedDoseBadge.taken,
        DoseAvailabilityState.skipped => MedDoseBadge.skipped,
        DoseAvailabilityState.missed ||
        DoseAvailabilityState.readOnly => MedDoseBadge.missed,
        _ => MedDoseBadge.none,
      },
      timeLabel: '$time $meridiem',
      semanticLabel:
          '${dose.medication.name}, $time $meridiem, ${dose.state.label}',
      action: _actionLogId == dose.logId ? _action : MedDoseAction.none,
      onTap: () => _onDoseTapped(index, doses),
    );
  }

  Widget _focusPanel(
    BuildContext context,
    _OrbitDose? focused,
    MedOrbitPhase phase,
    int focusIndex,
  ) {
    // With `Scaffold(extendBody: true)` in AppShell, Flutter reports the
    // floating bottom navigation's height as the body's bottom padding. Reading
    // it here keeps the controls clear of the bar without hardcoding its size.
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    if (focused == null) {
      return MedOrbitFocusPanel(
        phase: MedOrbitPhase.pending,
        stateLabel: 'NO DOSE',
        periodLabel: '',
        time: '—',
        meridiem: '',
        name: 'Nothing scheduled',
        dosage: '',
        detail: null,
        canAct: false,
        isBusy: false,
        passiveLabel: null,
        onTake: () {},
        onSkip: () {},
        onAddMedication: () => context.push('/medications/add'),
        bottomInset: bottomInset,
      );
    }

    final (time, meridiem) = _splitTime(focused.minutes);
    final confirmedAt = focused.item.confirmedAt;
    final takenAt = confirmedAt != null
        ? _fullTimeOf(confirmedAt)
        : _fullTime(focused.minutes);

    final (String stateLabel, String? passiveLabel) =
        switch (focused.state.state) {
      DoseAvailabilityState.completed => ('COMPLETED', 'TAKEN $takenAt'),
      DoseAvailabilityState.skipped => ('SKIPPED', 'NOT TAKEN'),
      DoseAvailabilityState.missed ||
      DoseAvailabilityState.readOnly => ('MISSED WINDOW', 'NOT TAKEN'),
      DoseAvailabilityState.actionable => (
        phase == MedOrbitPhase.next ? 'NEXT DOSE' : 'LATER TODAY',
        null,
      ),
      DoseAvailabilityState.upcoming => ('LATER TODAY', 'NOT YET DUE'),
      DoseAvailabilityState.futureDate => (
        'SCHEDULED',
        'SCHEDULED · $_dayLabel',
      ),
    };

    return MedOrbitFocusPanel(
      phase: phase,
      stateLabel: stateLabel,
      periodLabel: focused.period.label,
      time: time,
      meridiem: meridiem,
      name: focused.medication.name,
      dosage: focused.medication.dosage,
      detail: _detailOpen
          ? MedOrbitDetail(
              schedule: '${_fullTime(focused.minutes)} · '
                  '${focused.period.label}',
              status: focused.state.state == DoseAvailabilityState.completed
                  ? 'Taken $takenAt'
                  : focused.state.label,
              date: _fullDateLabel,
            )
          : null,
      canAct: focused.state.canMarkTaken,
      isBusy: _isUpdating,
      passiveLabel: passiveLabel,
      onTake: () =>
          _markDose(focused, AdherenceStatus.taken, focusIndex: focusIndex),
      onSkip: () =>
          _markDose(focused, AdherenceStatus.missed, focusIndex: focusIndex),
      onAddMedication: null,
      bottomInset: bottomInset,
    );
  }
}
