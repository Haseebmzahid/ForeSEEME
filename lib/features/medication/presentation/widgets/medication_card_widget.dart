import 'dart:async';
import 'dart:ui';

import 'package:fyp_foreseeme/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fyp_foreseeme/core/theme/app_theme.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/medication_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/enums/medication_enums.dart';
import 'package:fyp_foreseeme/features/medication/domain/services/dose_state_engine.dart';
import 'package:google_fonts/google_fonts.dart';

import '../adherence_notifier.dart';

const _kTeal = Color(0xFF006D77);
const _kCyan = Color(0xFF28DDE8);

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

  Color _statusColor(DoseAvailabilityState state) {
    return switch (state) {
      DoseAvailabilityState.completed => AppColors.success,
      DoseAvailabilityState.skipped => AppColors.error,
      DoseAvailabilityState.missed => AppColors.error,
      DoseAvailabilityState.actionable => _kCyan,
      DoseAvailabilityState.upcoming => AppColors.warning,
      DoseAvailabilityState.futureDate => AppColors.info,
      DoseAvailabilityState.readOnly => AppColors.error,
    };
  }

  Widget _statusBadge(DoseStateResult doseState) {
    final color = _statusColor(doseState.state);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20.0),
        border: Border.all(color: color.withValues(alpha: 0.34)),
      ),
      child: Text(
        doseState.label.toUpperCase(),
        style: GoogleFonts.manrope(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _actionButton(
    String label,
    IconData icon,
    Color activeColor,
    AdherenceStatus actionStatus,
    DoseStateResult doseState,
    bool isDark,
  ) {
    final isSelected = _visibleStatus == actionStatus;
    final canPerformAction = actionStatus == AdherenceStatus.taken
        ? doseState.canMarkTaken
        : doseState.canMarkSkipped;

    return Expanded(
      child: GestureDetector(
        onTap: canPerformAction && !_isUpdating
            ? () => _markDose(actionStatus)
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: isSelected
                ? LinearGradient(
                    colors: [activeColor, activeColor.withValues(alpha: 0.75)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: !isSelected
                ? (canPerformAction
                    ? (isDark
                        ? activeColor.withValues(alpha: 0.10)
                        : activeColor.withValues(alpha: 0.08))
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.03)
                        : Colors.black.withValues(alpha: 0.03)))
                : null,
            border: Border.all(
              color: isSelected
                  ? Colors.transparent
                  : (canPerformAction
                      ? activeColor.withValues(alpha: 0.25)
                      : (isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.black.withValues(alpha: 0.05))),
              width: 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: activeColor.withValues(alpha: 0.30),
                      blurRadius: 12,
                      spreadRadius: -2,
                      offset: const Offset(0, 4),
                    )
                  ]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected
                    ? Colors.white
                    : (canPerformAction
                        ? activeColor
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.30)
                            : Colors.black.withValues(alpha: 0.30))),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isSelected
                      ? Colors.white
                      : (canPerformAction
                          ? activeColor
                          : (isDark
                              ? Colors.white.withValues(alpha: 0.30)
                              : Colors.black.withValues(alpha: 0.30))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final doseState = _doseState;
    final isDark = AppColors.activePalette == AppColors.darkPalette ||
        Theme.of(context).brightness == Brightness.dark;

    if (doseState.shouldAutoMarkMissed &&
        _visibleStatus == AdherenceStatus.pending) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _markMissedAutomatically();
      });
    }

    final isCurrentDose = doseState.isCurrentDose;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.paddingHorizontal,
        vertical: 8.0,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: isDark
                  ? const Color(0xFF0D1F38).withValues(alpha: 0.68)
                  : Colors.white.withValues(alpha: 0.80),
              border: Border.all(
                color: isCurrentDose
                    ? _kCyan.withValues(alpha: 0.35)
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.09)
                        : _kTeal.withValues(alpha: 0.13)),
                width: 1.0,
              ),
              boxShadow: [
                if (isCurrentDose)
                  BoxShadow(
                    color: _kCyan.withValues(alpha: isDark ? 0.16 : 0.08),
                    blurRadius: 24,
                    spreadRadius: -6,
                    offset: const Offset(0, 8),
                  )
                else ...[
                  BoxShadow(
                    color: _kTeal.withValues(alpha: isDark ? 0.14 : 0.06),
                    blurRadius: 24,
                    spreadRadius: -6,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.05),
                    blurRadius: 16,
                    spreadRadius: -8,
                    offset: const Offset(0, 4),
                  ),
                ]
              ],
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
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : AppColors.textPrimary,
                          height: 1.2,
                        ),
                      ),
                    ),
                    _statusBadge(doseState),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.medication_rounded,
                      size: 16,
                      color: isDark ? const Color(0xFF8EA6BD) : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${widget.medication.dosage} - ${widget.medication.type.name}',
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: isDark ? const Color(0xFF8EA6BD) : AppColors.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.access_time_rounded,
                      size: 16,
                      color: isCurrentDose
                          ? (isDark ? _kCyan : _kTeal)
                          : (isDark ? const Color(0xFF8EA6BD) : AppColors.textSecondary),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _formatTime(),
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isCurrentDose
                            ? (isDark ? _kCyan : _kTeal)
                            : (isDark ? Colors.white : AppColors.textPrimary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _actionButton(
                      'Taken',
                      Icons.check_circle_outline_rounded,
                      AppColors.success,
                      AdherenceStatus.taken,
                      doseState,
                      isDark,
                    ),
                    const SizedBox(width: 12),
                    _actionButton(
                      'Skipped',
                      Icons.cancel_outlined,
                      AppColors.error,
                      AdherenceStatus.missed,
                      doseState,
                      isDark,
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
