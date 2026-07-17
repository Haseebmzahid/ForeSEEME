import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/medication_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/enums/medication_enums.dart';
import 'package:fyp_foreseeme/features/medication/domain/services/dose_state_engine.dart';

import '../adherence_notifier.dart';

class MedicationCardWidget extends ConsumerStatefulWidget {
  final MedicationModel medication;
  final String timeString; // "HH:mm"
  final AdherenceStatus status;
  final DateTime? confirmedAt;
  final DateTime selectedDate;

  const MedicationCardWidget({
    super.key,
    required this.medication,
    required this.timeString,
    required this.status,
    required this.confirmedAt,
    required this.selectedDate,
  });

  @override
  ConsumerState<MedicationCardWidget> createState() =>
      _MedicationCardWidgetState();
}

class _MedicationCardWidgetState extends ConsumerState<MedicationCardWidget> {
  AdherenceStatus? _optimisticStatus;
  bool _isUpdating = false;
  bool _autoMissedQueued = false;
  late DateTime _now;
  Timer? _clockTimer;

  AdherenceStatus get _visibleStatus => _optimisticStatus ?? widget.status;

  DoseStateResult get _doseState => DoseStateEngine.determineDoseState(
        selectedDate: widget.selectedDate,
        reminderTime: widget.timeString,
        status: _visibleStatus,
        confirmedAt: widget.confirmedAt,
        now: _now,
      );

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void didUpdateWidget(covariant MedicationCardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.status != oldWidget.status ||
        widget.status == _optimisticStatus) {
      _optimisticStatus = null;
    }
    if (widget.status != AdherenceStatus.pending) {
      _autoMissedQueued = false;
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  String _formatTime() {
    final parts = widget.timeString.split(':');
    if (parts.length != 2) return widget.timeString;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = parts[1];
    final suffix = h >= 12 ? 'PM' : 'AM';
    final readHour = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$readHour:$m $suffix';
  }

  Future<void> _markDose(AdherenceStatus newStatus) async {
    if (_isUpdating) return;
    final doseState = _doseState;
    final canSubmit = newStatus == AdherenceStatus.taken
        ? doseState.canMarkTaken
        : doseState.canMarkSkipped;
    if (!canSubmit) return;

    final previousStatus = _visibleStatus;
    setState(() {
      _isUpdating = true;
      _optimisticStatus = newStatus;
    });

    try {
      await ref.read(adherenceNotifierProvider.notifier).updateStatus(
            medication: widget.medication,
            date: widget.selectedDate,
            timeString: widget.timeString,
            status: newStatus,
          );
    } catch (e) {
      if (!mounted) return;
      setState(() => _optimisticStatus = previousStatus);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }

  Future<void> _markMissedAutomatically() async {
    if (_isUpdating ||
        _autoMissedQueued ||
        _visibleStatus != AdherenceStatus.pending) {
      return;
    }

    _autoMissedQueued = true;
    final previousStatus = _visibleStatus;
    setState(() {
      _isUpdating = true;
      _optimisticStatus = AdherenceStatus.missed;
    });

    try {
      await ref.read(adherenceNotifierProvider.notifier).updateStatus(
            medication: widget.medication,
            date: widget.selectedDate,
            timeString: widget.timeString,
            status: AdherenceStatus.missed,
          );
    } catch (e) {
      if (!mounted) return;
      _autoMissedQueued = false;
      setState(() => _optimisticStatus = previousStatus);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Missed update failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }

  /// Dose state → the design system's semantic tone (never a bespoke hue).
  Color _statusColor(BuildContext context, DoseAvailabilityState state) {
    final colors = context.fsmColors;
    return switch (state) {
      DoseAvailabilityState.completed => colors.success,
      DoseAvailabilityState.skipped => context.fsmPalette.error,
      DoseAvailabilityState.missed => context.fsmPalette.error,
      DoseAvailabilityState.actionable => context.fsmPalette.primary,
      DoseAvailabilityState.upcoming => colors.warning,
      DoseAvailabilityState.futureDate => colors.info,
      DoseAvailabilityState.readOnly => context.fsmPalette.error,
    };
  }

  Widget _statusBadge(BuildContext context, DoseStateResult doseState) {
    final color = _statusColor(context, doseState.state);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(ForeSeeMeRadius.full),
        border: Border.all(color: color.withValues(alpha: 0.34)),
      ),
      child: Text(
        doseState.label.toUpperCase(),
        style: context.fsmText.labelSmall?.copyWith(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _actionButton(
    BuildContext context,
    String label,
    IconData icon,
    Color activeColor,
    Color onActiveColor,
    AdherenceStatus actionStatus,
    DoseStateResult doseState,
  ) {
    final palette = context.fsmPalette;
    final isSelected = _visibleStatus == actionStatus;
    final canPerformAction = actionStatus == AdherenceStatus.taken
        ? doseState.canMarkTaken
        : doseState.canMarkSkipped;

    // Selected → solid gradient; available → tinted; disabled → muted surface.
    final Color contentColor = isSelected
        ? onActiveColor
        : (canPerformAction ? activeColor : palette.textDisabled);

    return Expanded(
      child: Semantics(
        button: true,
        enabled: canPerformAction && !_isUpdating,
        selected: isSelected,
        label: label,
        child: GestureDetector(
          onTap: canPerformAction && !_isUpdating
              ? () => _markDose(actionStatus)
              : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(ForeSeeMeRadius.sm),
              gradient: isSelected
                  ? LinearGradient(
                      colors: [
                        activeColor,
                        activeColor.withValues(alpha: 0.75),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: !isSelected
                  ? (canPerformAction
                        ? activeColor.withValues(alpha: 0.10)
                        : palette.surfaceContainerHighest)
                  : null,
              border: Border.all(
                color: isSelected
                    ? Colors.transparent
                    : (canPerformAction
                          ? activeColor.withValues(alpha: 0.25)
                          : palette.outlineVariant),
                width: ForeSeeMeBorderWidth.thin,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: activeColor.withValues(alpha: 0.30),
                        blurRadius: 12,
                        spreadRadius: -2,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : [],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: contentColor),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: context.fsmText.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: contentColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final doseState = _doseState;
    final palette = context.fsmPalette;
    final text = context.fsmText;

    if (doseState.shouldAutoMarkMissed &&
        _visibleStatus == AdherenceStatus.pending) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _markMissedAutomatically();
      });
    }

    final isCurrentDose = doseState.isCurrentDose;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ForeSeeMeSpacing.gutter,
        vertical: 8.0,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ForeSeeMeRadius.lg),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            padding: const EdgeInsets.all(16),
            // The current dose is highlighted with the brand border + glow;
            // every other card uses the shared surface recipe.
            decoration: ForeSeeMeSurface.card(
              context,
              borderColor: isCurrentDose
                  ? palette.primary.withValues(alpha: 0.35)
                  : null,
              shadow: isCurrentDose
                  ? [
                      BoxShadow(
                        color: palette.primary.withValues(
                          alpha: palette.isDark ? 0.16 : 0.08,
                        ),
                        blurRadius: 24,
                        spreadRadius: -6,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        widget.medication.name,
                        style: text.titleLarge?.copyWith(height: 1.2),
                      ),
                    ),
                    _statusBadge(context, doseState),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.medication_rounded,
                      size: 16,
                      color: palette.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${widget.medication.dosage} - ${widget.medication.type.name}',
                      style: text.bodyMedium?.copyWith(
                        fontSize: 13,
                        color: palette.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.access_time_rounded,
                      size: 16,
                      color: isCurrentDose
                          ? palette.primary
                          : palette.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _formatTime(),
                      style: text.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isCurrentDose
                            ? palette.primary
                            : palette.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _actionButton(
                      context,
                      'Taken',
                      Icons.check_circle_outline_rounded,
                      context.fsmColors.success,
                      context.fsmColors.onSuccess,
                      AdherenceStatus.taken,
                      doseState,
                    ),
                    const SizedBox(width: 12),
                    _actionButton(
                      context,
                      'Skipped',
                      Icons.cancel_outlined,
                      palette.error,
                      palette.onError,
                      AdherenceStatus.missed,
                      doseState,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
