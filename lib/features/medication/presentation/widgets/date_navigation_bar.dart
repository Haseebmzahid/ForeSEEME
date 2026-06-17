import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fyp_foreseeme/core/theme/app_colors.dart';

const _kTeal = Color(0xFF006D77);
const _kCyan = Color(0xFF28DDE8);

class DateNavigationBar extends StatelessWidget {
  final DateTime trueToday;
  final DateTime selectedDate;
  final List<DateTime> dateWindow;
  final ScrollController scrollController;
  final ValueChanged<DateTime> onDateSelected;

  const DateNavigationBar({
    super.key,
    required this.trueToday,
    required this.selectedDate,
    required this.dateWindow,
    required this.scrollController,
    required this.onDateSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.activePalette == AppColors.darkPalette ||
        Theme.of(context).brightness == Brightness.dark;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 85,
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF0A1628).withValues(alpha: 0.75)
                : Colors.white.withValues(alpha: 0.72),
            border: Border(
              bottom: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.07)
                    : _kTeal.withValues(alpha: 0.10),
              ),
            ),
          ),
          child: ListView.builder(
            controller: scrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            itemCount: dateWindow.length,
            itemBuilder: (context, index) {
              final date = dateWindow[index];
              final isSelected = date.isAtSameMomentAs(selectedDate);
              final isToday = date.isAtSameMomentAs(trueToday);

              return GestureDetector(
                onTap: () => onDateSelected(date),
                child: Container(
                  width: 62,
                  margin: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 10.0),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16.0),
                    gradient: isSelected
                        ? const LinearGradient(
                            colors: [_kTeal, _kCyan],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: !isSelected
                        ? (isToday
                            ? (isDark
                                ? Colors.white.withValues(alpha: 0.10)
                                : _kTeal.withValues(alpha: 0.06))
                            : Colors.transparent)
                        : null,
                    border: Border.all(
                      color: isSelected
                          ? Colors.transparent
                          : (isToday
                              ? _kTeal.withValues(alpha: 0.20)
                              : Colors.transparent),
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: _kCyan.withValues(alpha: 0.35),
                              blurRadius: 14,
                              spreadRadius: -2,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _getWeekdayAbbr(date.weekday),
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: isSelected
                              ? Colors.white
                              : (isToday
                                  ? (isDark ? _kCyan : _kTeal)
                                  : (isDark
                                      ? Colors.white.withValues(alpha: 0.45)
                                      : AppColors.textTertiary)),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${date.day}',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: isSelected
                              ? Colors.white
                              : (isToday
                                  ? (isDark ? Colors.white : AppColors.textPrimary)
                                  : (isDark
                                      ? Colors.white.withValues(alpha: 0.75)
                                      : AppColors.textSecondary)),
                        ),
                      ),
                      if (isToday && !isSelected)
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: isDark ? _kCyan : _kTeal,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  String _getWeekdayAbbr(int weekday) {
    const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    return days[weekday - 1];
  }
}
