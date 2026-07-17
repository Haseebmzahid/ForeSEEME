import 'dart:ui';
import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';

/// Horizontal date strip for the Daily Check-In schedule.
///
/// All colour comes from the ForeSeeMe design system for the ambient
/// brightness: the selected day uses the primary gradient, today is marked with
/// a tinted surface + dot, and the rest use the palette's text tiers.
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
    final palette = context.fsmPalette;
    final text = context.fsmText;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 85,
          decoration: BoxDecoration(
            color: ForeSeeMeSurface.chromeFill(context),
            border: Border(
              bottom: BorderSide(color: ForeSeeMeSurface.stroke(context)),
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

              final Color weekdayColor = isSelected
                  ? palette.onPrimary
                  : (isToday ? palette.primary : palette.textTertiary);
              final Color dayColor = isSelected
                  ? palette.onPrimary
                  : (isToday ? palette.textPrimary : palette.textSecondary);

              return Semantics(
                button: true,
                selected: isSelected,
                label: '${date.day}/${date.month}${isToday ? ', today' : ''}',
                child: GestureDetector(
                  onTap: () => onDateSelected(date),
                  child: Container(
                    width: 62,
                    margin: const EdgeInsets.symmetric(
                      horizontal: 5.0,
                      vertical: 10.0,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(ForeSeeMeRadius.md),
                      gradient: isSelected
                          ? context.fsmColors.gradients.primary
                          : null,
                      color: !isSelected
                          ? (isToday
                                ? palette.primary.withValues(alpha: 0.08)
                                : Colors.transparent)
                          : null,
                      border: Border.all(
                        color: !isSelected && isToday
                            ? palette.primary.withValues(alpha: 0.20)
                            : Colors.transparent,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: palette.primary.withValues(alpha: 0.35),
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
                          style: text.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: weekdayColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${date.day}',
                          style: text.titleLarge?.copyWith(
                            fontSize: 20,
                            color: dayColor,
                          ),
                        ),
                        if (isToday && !isSelected)
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              color: palette.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
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
