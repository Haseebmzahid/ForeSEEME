import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/widgets/glass_action_button.dart';

import 'med_orbit_style.dart';

/// Chrome for the Daily Check-In "Medication Orbit" screen, transcribed from
/// the approved prototype (`docs/Design/Medication Orbit (standalone).html`).
///
/// Every widget here is presentation only — it takes values and callbacks and
/// owns no state, no provider and no navigation decision. Scope is Daily
/// Check-In; nothing else in the app imports this file.

// ── Header ───────────────────────────────────────────────────────────────────

/// One tick per scheduled dose, filled as the day resolves.
@immutable
class MedAdherenceTick {
  const MedAdherenceTick({required this.phase});

  final MedOrbitPhase phase;
}

/// The prototype's top band: the day's adherence ticks, the date shuttle, and
/// a trailing utility slot.
class MedOrbitHeader extends StatelessWidget {
  const MedOrbitHeader({
    super.key,
    required this.ticks,
    required this.adherenceLabel,
    required this.dateLabel,
    required this.dayLabel,
    required this.onPreviousDay,
    required this.onNextDay,
    required this.onAddMedication,
  });

  final List<MedAdherenceTick> ticks;

  /// `2 / 4`, or `—` on an empty day.
  final String adherenceLabel;

  /// `AUG 16`.
  final String dateLabel;

  /// `TODAY`, `YESTERDAY`, `TOMORROW`, or the weekday.
  final String dayLabel;

  /// Null at the end of the existing date window, which greys the arrow.
  final VoidCallback? onPreviousDay;
  final VoidCallback? onNextDay;

  final VoidCallback onAddMedication;

  @override
  Widget build(BuildContext context) {
    final theme = MedOrbitTheme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    label: 'Doses resolved: $adherenceLabel',
                    child: ExcludeSemantics(
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 3,
                        children: [
                          for (final tick in ticks.take(9))
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 500),
                              width: 15,
                              height: 3,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(2),
                                color: switch (tick.phase) {
                                  MedOrbitPhase.taken => theme.accent,
                                  MedOrbitPhase.inactive => const Color(
                                    0x73B4AC9E,
                                  ),
                                  _ => theme.ink.withValues(alpha: 0.13),
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    adherenceLabel,
                    style: medMono(
                      context,
                      size: 10,
                      em: 0.14,
                      color: theme.ink5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _ShuttleArrow(
                      icon: Icons.chevron_left_rounded,
                      semanticLabel: 'Previous day',
                      onPressed: onPreviousDay,
                    ),
                    Flexible(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 96),
                        child: Text(
                          dateLabel,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: medMono(
                            context,
                            size: 15,
                            em: 0.2,
                            color: theme.ink,
                            weight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    _ShuttleArrow(
                      icon: Icons.chevron_right_rounded,
                      semanticLabel: 'Next day',
                      onPressed: onNextDay,
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  dayLabel,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: medMono(
                    context,
                    size: 8.5,
                    em: 0.34,
                    color: theme.ink6,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 84,
            child: Align(
              alignment: Alignment.topRight,
              child: Semantics(
                button: true,
                label: 'Add medication',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onAddMedication,
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.ink.withValues(alpha: 0.09),
                          ),
                        ),
                        child: Icon(
                          Icons.add_rounded,
                          size: 15,
                          color: theme.ink5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShuttleArrow extends StatelessWidget {
  const _ShuttleArrow({
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = MedOrbitTheme.of(context);
    final enabled = onPressed != null;

    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(shape: BoxShape.circle),
              child: Icon(
                icon,
                size: 22,
                color: theme.ink4.withValues(alpha: enabled ? 1 : 0.35),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Meridian rail ────────────────────────────────────────────────────────────

/// A dose's mark on the meridian rail.
@immutable
class MedRailDot {
  const MedRailDot({
    required this.minutes,
    required this.phase,
  });

  final int minutes;
  final MedOrbitPhase phase;
}

/// The day's clock rendered as a vertical meridian: period bands, one dot per
/// dose at its scheduled minute, and a NOW marker while today is in view.
class MedMeridianRail extends StatelessWidget {
  const MedMeridianRail({
    super.key,
    required this.dots,
    required this.activePeriod,
    required this.nowMinutes,
  });

  final List<MedRailDot> dots;

  /// The band the focused dose falls in; it lights up.
  final MedPeriod? activePeriod;

  /// Minute-of-day of the NOW marker, or null when a past / future day is
  /// selected.
  final int? nowMinutes;

  @override
  Widget build(BuildContext context) {
    final theme = MedOrbitTheme.of(context);

    return ExcludeSemantics(
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.maxHeight;
            double topFor(double fraction) => fraction * height;

            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          theme.ink.withValues(alpha: 0),
                          theme.ink.withValues(alpha: 0.10),
                          theme.ink.withValues(alpha: 0.10),
                          theme.ink.withValues(alpha: 0),
                        ],
                        stops: const [0.0, 0.12, 0.88, 1.0],
                      ),
                    ),
                  ),
                ),
                for (final period in MedPeriod.values)
                  Positioned(
                    left: 0,
                    top: topFor(medRailFraction(period.railMidpoint)) - 5,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 600),
                      opacity: activePeriod == period ? 1 : 0.6,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 1,
                            color: activePeriod == period
                                ? theme.accent
                                : theme.ink6,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            period.label,
                            style: medMono(
                              context,
                              size: 8,
                              em: 0.24,
                              color: activePeriod == period
                                  ? theme.accent
                                  : theme.ink6,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                for (final dot in dots)
                  Positioned(
                    left: -2,
                    top: topFor(medRailFraction(dot.minutes)) - 2,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: MedDoseTint.of(dot.phase).solid,
                        boxShadow: dot.phase == MedOrbitPhase.next
                            ? [
                                BoxShadow(
                                  color: theme.accent.withValues(alpha: 0.9),
                                  blurRadius: 8,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ),
                if (nowMinutes != null) ...[
                  Positioned(
                    left: -5,
                    top: topFor(medRailFraction(nowMinutes!)) - 5,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.accent.withValues(alpha: 0.85),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 22,
                    top: topFor(medRailFraction(nowMinutes!)) - 6,
                    child: Text(
                      'NOW',
                      style: medMono(
                        context,
                        size: 7.5,
                        em: 0.24,
                        color: theme.accent.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Focus panel ──────────────────────────────────────────────────────────────

/// The three technical rows revealed when the focused dose is tapped.
@immutable
class MedOrbitDetail {
  const MedOrbitDetail({
    required this.schedule,
    required this.status,
    required this.date,
  });

  final String schedule;
  final String status;
  final String date;
}

/// The bottom readout: what the focused dose is, and what can be done about it.
class MedOrbitFocusPanel extends StatelessWidget {
  const MedOrbitFocusPanel({
    super.key,
    required this.phase,
    required this.stateLabel,
    required this.periodLabel,
    required this.time,
    required this.meridiem,
    required this.name,
    required this.dosage,
    required this.detail,
    required this.canAct,
    required this.isBusy,
    required this.passiveLabel,
    required this.onTake,
    required this.onSkip,
    required this.onAddMedication,
    this.bottomInset = 0,
  });

  final MedOrbitPhase phase;
  final String stateLabel;
  final String periodLabel;
  final String time;
  final String meridiem;
  final String name;
  final String dosage;

  /// Non-null while the detail rows are expanded.
  final MedOrbitDetail? detail;

  /// Mirrors the dose-state engine's `canMarkTaken` / `canMarkSkipped`; when
  /// false the panel shows a read-only plate instead of the actions.
  final bool canAct;

  final bool isBusy;

  /// Read-only caption, e.g. `TAKEN 8:04 AM`.
  final String? passiveLabel;

  final VoidCallback onTake;
  final VoidCallback onSkip;

  /// Only offered on a day with nothing scheduled.
  final VoidCallback? onAddMedication;

  /// Space to reserve beneath the controls for whatever the app shell floats
  /// over this screen — the persistent bottom navigation, plus the system
  /// gesture inset.
  ///
  /// The panel stays anchored to the bottom of the stage (its fill has to reach
  /// the screen edge or a seam appears between it and the ambient background),
  /// so the clearance is applied to the panel's *content* rather than by
  /// shrinking the panel itself.
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final theme = MedOrbitTheme.of(context);
    final stateColor = theme.stateColor(phase);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            theme.panel.withValues(alpha: 0),
            theme.panel.withValues(alpha: 0.86),
            theme.panel,
          ],
          stops: const [0.0, 0.16, 0.44],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(22, 26, 22, 24 + bottomInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    stateLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: medMono(
                      context,
                      size: 9.5,
                      em: 0.30,
                      color: stateColor,
                    ),
                  ),
                ),
                Text(
                  periodLabel,
                  style: medMono(
                    context,
                    size: 9,
                    em: 0.24,
                    color: theme.ink6,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    time,
                    style: medMono(
                      context,
                      size: 42,
                      em: -0.01,
                      color: theme.ink,
                      weight: FontWeight.w300,
                      height: 1.0,
                    ),
                  ),
                  if (meridiem.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        meridiem,
                        style: medMono(
                          context,
                          size: 13,
                          em: 0.16,
                          color: theme.ink3,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.fsmText.titleLarge?.copyWith(
                      fontSize: 21,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.21,
                      color: theme.ink,
                    ),
                  ),
                ),
                if (dosage.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      dosage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: medMono(
                        context,
                        size: 13,
                        em: 0.04,
                        color: theme.ink3,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (detail != null) _DetailRows(detail: detail!, theme: theme),
            const SizedBox(height: 20),
            if (canAct)
              _Actions(
                theme: theme,
                isBusy: isBusy,
                onTake: onTake,
                onSkip: onSkip,
              )
            else if (passiveLabel != null)
              _PassivePlate(
                label: passiveLabel!,
                color: stateColor,
                theme: theme,
              )
            else if (onAddMedication != null)
              _AddMedicationPlate(theme: theme, onPressed: onAddMedication!),
          ],
        ),
      ),
    );
  }
}

class _DetailRows extends StatelessWidget {
  const _DetailRows({required this.detail, required this.theme});

  final MedOrbitDetail detail;
  final MedOrbitTheme theme;

  @override
  Widget build(BuildContext context) {
    Widget row(String key, String value) => Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            key,
            style: medMono(context, size: 10, em: 0.12, color: theme.ink5),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: medMono(context, size: 10, em: 0.12, color: theme.ink2),
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        padding: const EdgeInsets.only(top: 3),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: theme.hair)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            row('SCHEDULE', detail.schedule),
            row('STATUS', detail.status),
            row('DATE', detail.date),
          ],
        ),
      ),
    );
  }
}

/// The two committing controls, as glass panes floating over the stage.
///
/// Hierarchy is carried by weight, not alarm: Take Now is the accent-tinted
/// primary pane, Skip is the same material untinted and narrower. Skip is
/// deliberately *not* an error treatment — a missed dose is information, not a
/// scolding.
///
/// At large text scales the pair stacks, so both labels stay at full size
/// rather than being shrunk to fit a row.
class _Actions extends StatelessWidget {
  const _Actions({
    required this.theme,
    required this.isBusy,
    required this.onTake,
    required this.onSkip,
  });

  final MedOrbitTheme theme;
  final bool isBusy;
  final VoidCallback onTake;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final take = GlassActionButton(
      label: 'TAKE NOW',
      icon: Icons.check_rounded,
      semanticLabel: 'Take now',
      tone: GlassActionTone.primary,
      accent: theme.accent,
      foreground: theme.ink,
      onPressed: onTake,
    );
    final skip = GlassActionButton(
      label: 'Skip',
      icon: Icons.remove_rounded,
      semanticLabel: 'Skip',
      accent: theme.accent,
      foreground: theme.ink4,
      fontSize: 12,
      onPressed: onSkip,
    );

    // Past ~1.45x the two labels can no longer share a row without shrinking
    // the type, which is exactly what a user at that scale does not want.
    final stacked = MediaQuery.textScalerOf(context).scale(13) > 18.5;

    final pair = stacked
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [take, const SizedBox(height: 10), skip],
          )
        : Row(
            children: [
              Expanded(child: take),
              const SizedBox(width: 10),
              SizedBox(width: 104, child: skip),
            ],
          );

    // While a check-in commits the controls stop accepting input but keep their
    // appearance: the commit window is only a few hundred milliseconds, the
    // capsule is already carrying the feedback, and dimming or spinning for
    // that long would read as a stutter. The screen's mutation guard is the
    // real protection; this closes the door at the widget level too.
    return IgnorePointer(ignoring: isBusy, child: pair);
  }
}

/// The read-only plate shown wherever the dose-state engine allows no action.
class _PassivePlate extends StatelessWidget {
  const _PassivePlate({
    required this.label,
    required this.color,
    required this.theme,
  });

  final String label;
  final Color color;
  final MedOrbitTheme theme;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: CustomPaint(
        painter: _DashedPlatePainter(
          color: theme.ink.withValues(alpha: 0.14),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: medMono(context, size: 10, em: 0.26, color: color),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AddMedicationPlate extends StatelessWidget {
  const _AddMedicationPlate({required this.theme, required this.onPressed});

  final MedOrbitTheme theme;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Add medication',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.accent.withValues(alpha: 0.4)),
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'ADD MEDICATION',
                  style: medMono(
                    context,
                    size: 10,
                    em: 0.26,
                    color: theme.accent,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedPlatePainter extends CustomPainter {
  const _DashedPlatePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(14),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;

    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + 5).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + 4;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedPlatePainter old) => old.color != color;
}

/// The prototype's hairline rule: a fade that reads as a horizon, not a border.
class MedHairlineRule extends StatelessWidget {
  const MedHairlineRule({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = MedOrbitTheme.of(context);
    return SizedBox(
      height: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              theme.grid.withValues(alpha: 0),
              theme.grid.withValues(alpha: 0.22),
              theme.grid.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}
