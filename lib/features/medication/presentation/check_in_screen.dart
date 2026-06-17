import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:fyp_foreseeme/core/theme/app_colors.dart';
import 'package:fyp_foreseeme/core/theme/app_theme.dart';
import 'package:fyp_foreseeme/core/widgets/empty_state_widget.dart';
import 'package:fyp_foreseeme/core/widgets/section_header.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_log_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/medication_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/enums/medication_enums.dart';

import 'adherence_notifier.dart';
import 'widgets/medication_card_widget.dart';
import 'widgets/date_navigation_bar.dart';

const _kTeal = Color(0xFF006D77);
const _kCyan = Color(0xFF28DDE8);

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

class GroupedMedicationList extends StatelessWidget {
  final Map<String, List<DoseItem>> grouped;
  final DateTime selectedDate;

  const GroupedMedicationList({
    super.key,
    required this.grouped,
    required this.selectedDate,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.only(
        bottom: 96.0,
        top: MediaQuery.of(context).padding.top + kToolbarHeight + 85 + 8.0, // Accounts for AppBar + Nav bar
      ),
      children: [
        if (grouped['Morning']?.isNotEmpty ?? false) ...[
          const SectionHeader(title: 'Morning', icon: Icons.wb_twilight_rounded),
          ...grouped['Morning']!.map(
            (dose) => MedicationCardWidget(
              medication: dose.medication,
              timeString: dose.timeString,
              status: dose.status,
              confirmedAt: dose.confirmedAt,
              selectedDate: selectedDate,
            ),
          ),
        ],
        if (grouped['Afternoon']?.isNotEmpty ?? false) ...[
          const SectionHeader(title: 'Afternoon', icon: Icons.wb_sunny_rounded),
          ...grouped['Afternoon']!.map(
            (dose) => MedicationCardWidget(
              medication: dose.medication,
              timeString: dose.timeString,
              status: dose.status,
              confirmedAt: dose.confirmedAt,
              selectedDate: selectedDate,
            ),
          ),
        ],
        if (grouped['Evening']?.isNotEmpty ?? false) ...[
          const SectionHeader(title: 'Evening', icon: Icons.nights_stay_rounded),
          ...grouped['Evening']!.map(
            (dose) => MedicationCardWidget(
              medication: dose.medication,
              timeString: dose.timeString,
              status: dose.status,
              confirmedAt: dose.confirmedAt,
              selectedDate: selectedDate,
            ),
          ),
        ],
        if (grouped['Night']?.isNotEmpty ?? false) ...[
          const SectionHeader(title: 'Night', icon: Icons.bedtime_rounded),
          ...grouped['Night']!.map(
            (dose) => MedicationCardWidget(
              medication: dose.medication,
              timeString: dose.timeString,
              status: dose.status,
              confirmedAt: dose.confirmedAt,
              selectedDate: selectedDate,
            ),
          ),
        ],
      ],
    );
  }
}

class DailyCheckInEmptyState extends StatelessWidget {
  const DailyCheckInEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.activePalette == AppColors.darkPalette ||
        Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.success.withValues(alpha: 0.18),
                    AppColors.success.withValues(alpha: 0.06),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
              child: Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: [AppColors.success, AppColors.success.withValues(alpha: 0.7)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.success.withValues(alpha: 0.30),
                        blurRadius: 18,
                        spreadRadius: -4,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.event_available_rounded,
                      color: Colors.white, size: 28),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              "You're all clear today",
              style: GoogleFonts.spaceGrotesk(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No medications scheduled for this day.\nEnjoy your time.',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: 14,
                height: 1.6,
                color: isDark ? const Color(0xFF8EA6BD) : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 28),
            _GradientAddButton(onPressed: () => context.go('/medications/add')),
          ],
        ),
      ),
    );
  }
}

// ── Gradient Add button ──────────────────────────────────────────────────────

class _GradientAddButton extends StatefulWidget {
  final VoidCallback onPressed;
  const _GradientAddButton({required this.onPressed});

  @override
  State<_GradientAddButton> createState() => _GradientAddButtonState();
}

class _GradientAddButtonState extends State<_GradientAddButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _isPressed ? 0.975 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: AppDimensions.buttonHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
            gradient: const LinearGradient(
              colors: [_kTeal, _kCyan],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: _kCyan.withValues(alpha: _isPressed ? 0.20 : 0.36),
                blurRadius: _isPressed ? 18 : 30,
                spreadRadius: -6,
                offset: Offset(0, _isPressed ? 4 : 10),
              ),
            ],
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Add Medication',
                  style: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DailyCheckInScreen extends ConsumerStatefulWidget {
  const DailyCheckInScreen({super.key});

  @override
  ConsumerState<DailyCheckInScreen> createState() => _DailyCheckInScreenState();
}

class _DailyCheckInScreenState extends ConsumerState<DailyCheckInScreen> {
  late DateTime _selectedDate;
  late final List<DateTime> _dateWindow;
  final ScrollController _dateScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final today = _dateOnly(DateTime.now());
    _selectedDate = today;

    _dateWindow = List.generate(15, (index) {
      return today.add(Duration(days: index - 7));
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_dateScrollController.hasClients) {
        final screenWidth = MediaQuery.of(context).size.width;
        _dateScrollController.jumpTo((7 * 72.0) - (screenWidth / 2) + 36.0);
      }
    });
  }

  void _onDateSelected(DateTime date) {
    setState(() {
      _selectedDate = _dateOnly(date);
    });
  }

  @override
  void dispose() {
    _dateScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trueToday = _dateOnly(DateTime.now());
    final medicationsAsync = ref.watch(medicationsStreamProvider);
    final logsAsync = ref.watch(adherenceLogsStreamProvider(_selectedDate));
    
    final isDark = AppColors.activePalette == AppColors.darkPalette ||
        Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight + 85.0),
        child: Column(
          children: [
            ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: AppBar(
                  backgroundColor: isDark
                      ? const Color(0xFF0A1628).withValues(alpha: 0.75)
                      : Colors.white.withValues(alpha: 0.72),
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  title: Text(
                    'Daily Check-In',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : AppColors.textPrimary,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ),
            ),
            DateNavigationBar(
              trueToday: trueToday,
              selectedDate: _selectedDate,
              dateWindow: _dateWindow,
              scrollController: _dateScrollController,
              onDateSelected: _onDateSelected,
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          // Ambient gradient background
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? const [Color(0xFF0A1628), Color(0xFF0D1F38), Color(0xFF081220)]
                      : const [Color(0xFFF0F7FF), Color(0xFFE6F5F5), Color(0xFFF5F0FF)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),
          // Ambient glow orb – top-left
          Positioned(
            top: 40,
            left: -50,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _kCyan.withValues(alpha: isDark ? 0.16 : 0.08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          medicationsAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(_kCyan),
                strokeCap: StrokeCap.round,
              ),
            ),
            error: (err, _) => EmptyStateWidget(
              title: 'Error',
              subTitle: err.toString(),
              icon: Icons.error_outline,
            ),
            data: (medications) {
              return logsAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(_kCyan),
                    strokeCap: StrokeCap.round,
                  ),
                ),
                error: (err, _) => EmptyStateWidget(
                  title: 'Error',
                  subTitle: err.toString(),
                  icon: Icons.error_outline,
                ),
                data: (logs) {
                  final allDoses = _buildScheduledDoseItems(
                    medications: medications,
                    logs: logs,
                    selectedDate: _selectedDate,
                    generateLogId: ref.read(adherenceNotifierProvider.notifier).generateLogId,
                  );

                  if (allDoses.isEmpty) {
                    return const DailyCheckInEmptyState();
                  }

                  final Map<String, List<DoseItem>> grouped = {
                    'Morning': allDoses.where((d) => d.timeSlot == 'Morning').toList(),
                    'Afternoon': allDoses.where((d) => d.timeSlot == 'Afternoon').toList(),
                    'Evening': allDoses.where((d) => d.timeSlot == 'Evening').toList(),
                    'Night': allDoses.where((d) => d.timeSlot == 'Night').toList(),
                  };

                  return GroupedMedicationList(
                    grouped: grouped,
                    selectedDate: _selectedDate,
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
