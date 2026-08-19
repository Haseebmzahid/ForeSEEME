import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/features/medication/domain/enums/medication_enums.dart';

import '../../../profile/presentation/widgets/profile_hub_motion.dart';

/// The physically-lit medication objects the Medications prototype floats on
/// its stage: a two-tone capsule and a syrup bottle.
///
/// Like `MedDoseTint` on the Daily Check-In orbit, these colours are the
/// **object's own** and are constant across light and dark: a capsule does not
/// change colour when the room does. Only the cast shadow adapts.
///
/// **Object kind comes from the real [MedicationType]** — capsule for `pill`,
/// bottle for `syrup`. The prototype draws four different objects for its four
/// mock medications, but the app stores only two types, and giving two
/// medications of the same type different objects would signal a distinction
/// the data does not make.

// ── Capsule ──────────────────────────────────────────────────────────────────

/// The prototype's capsule: a rounded body split down the middle, teal on the
/// left and pearl on the right, with a specular bar across the top.
class MedHubCapsule extends StatelessWidget {
  const MedHubCapsule({
    super.key,
    required this.width,
    required this.height,
    required this.shadowColor,
    required this.isDark,
    this.glow,
    this.rightTop = const Color(0xFF7BFFDF),
    this.rightBottom = const Color(0xFF1E9C86),
  });

  final double width;
  final double height;
  final Color shadowColor;
  final bool isDark;

  /// The accent halo the hero capsule carries (`0 0 46px var(--glow)`). Null on
  /// the small card objects, which the prototype leaves unlit.
  final Color? glow;

  /// The coloured half's gradient — `linear-gradient(160deg, …)`.
  final Color rightTop;
  final Color rightBottom;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(height);
    // `linear-gradient(160deg, …)`: 160° clockwise from "to top" runs from the
    // upper-left down to the lower-right, steeply.
    const begin = Alignment(-0.36, -1.0);
    const end = Alignment(0.36, 1.0);

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: shadowColor.withValues(alpha: isDark ? 0.60 : 0.20),
            blurRadius: height * 0.76,
            offset: Offset(0, height * 0.39),
          ),
          if (glow != null) BoxShadow(color: glow!, blurRadius: height * 0.7),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            // Coloured half.
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: width / 2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: begin,
                    end: end,
                    colors: [rightTop, rightBottom],
                    stops: const [0.0, 0.7],
                  ),
                ),
              ),
            ),
            // Pearl half.
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: width / 2,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: begin,
                    end: end,
                    colors: [Color(0xEBFFFFFF), Color(0xB3B2CCC7)],
                    stops: [0.0, 0.75],
                  ),
                ),
              ),
            ),
            // The seam between the halves.
            Positioned(
              left: width / 2 - 0.5,
              top: 0,
              bottom: 0,
              width: 1,
              child: const ColoredBox(color: Color(0x40000000)),
            ),
            // `inset 0 -14px 24px rgba(0,0,0,.45)` — the body's shaded belly.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.center,
                    colors: [
                      Colors.black.withValues(alpha: 0.42),
                      Colors.black.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            // The specular bar (`filter: blur(1px)`).
            Positioned(
              left: width * 0.081,
              right: width * 0.081,
              top: height * 0.136,
              height: height * 0.182,
              child: _Blur(
                sigma: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(height),
                    gradient: const LinearGradient(
                      colors: [Color(0x8CFFFFFF), Color(0x0FFFFFFF)],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Bottle ───────────────────────────────────────────────────────────────────

/// The prototype's suspension bottle: a translucent body with an amber fill in
/// the lower 58% and a soft highlight down its left side.
class MedHubBottle extends StatelessWidget {
  const MedHubBottle({
    super.key,
    required this.width,
    required this.height,
    required this.liquid,
    required this.shadowColor,
    required this.isDark,
  });

  final double width;
  final double height;

  /// The liquid's colour — the theme's `--warn` amber, so the object belongs to
  /// the same palette in both rooms.
  final Color liquid;

  final Color shadowColor;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.vertical(
      top: Radius.circular(width * 0.29),
      bottom: Radius.circular(width * 0.36),
    );

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: shadowColor.withValues(alpha: isDark ? 0.50 : 0.18),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: const Alignment(-0.36, -1.0),
                    end: const Alignment(0.36, 1.0),
                    colors: [
                      Colors.white.withValues(alpha: 0.28),
                      Colors.white.withValues(alpha: 0.08),
                    ],
                  ),
                ),
              ),
            ),
            // The liquid — the bottom 58%.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: height * 0.58,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      liquid.withValues(alpha: 0.85),
                      const Color(0xFFC88C3C).withValues(alpha: 0.75),
                    ],
                  ),
                ),
              ),
            ),
            // The highlight down the left side (`filter: blur(1px)`).
            Positioned(
              left: width * 0.25,
              top: height * 0.125,
              width: width * 0.18,
              height: height * 0.40,
              child: _Blur(
                sigma: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── The card's object slot ───────────────────────────────────────────────────

/// The 58×54 slot on a medication card: the object for the medication's stored
/// [MedicationType], floating over its contact shadow.
///
/// The prototype staggers each row's `med-floatS` loop; [floatIndex] carries
/// that stagger without any row knowing about the others.
class MedHubObject extends StatelessWidget {
  const MedHubObject({
    super.key,
    required this.type,
    required this.floatIndex,
    required this.shadowColor,
    required this.isDark,
    required this.warn,
  });

  final MedicationType type;
  final int floatIndex;
  final Color shadowColor;
  final bool isDark;
  final Color warn;

  @override
  Widget build(BuildContext context) {
    // `5s`, `5.6s .4s`, `6.2s .8s`, `5.2s 1.1s` — cycled so a long list keeps
    // the same unsynchronised rhythm.
    const periods = [5000, 5600, 6200, 5200];
    final period = periods[floatIndex % periods.length];
    final restT = (floatIndex % periods.length) / periods.length;

    final isBottle = type == MedicationType.syrup;

    final object = isBottle
        ? MedHubBottle(
            width: 28,
            height: 40,
            liquid: warn,
            shadowColor: shadowColor,
            isDark: isDark,
          )
        : Transform.rotate(
            angle: -20 * math.pi / 180,
            child: MedHubCapsule(
              width: 50,
              height: 24,
              shadowColor: shadowColor,
              isDark: isDark,
            ),
          );

    return SizedBox(
      width: 58,
      height: 54,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The contact shadow on the floor.
          Positioned(
            bottom: 4,
            child: _Blur(
              sigma: 1.5,
              child: SizedBox(
                width: isBottle ? 30 : 42,
                height: isBottle ? 7 : 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [
                        shadowColor.withValues(alpha: isDark ? 0.7 : 0.24),
                        shadowColor.withValues(alpha: 0),
                      ],
                      stops: const [0.0, 0.7],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: isBottle ? 6 : 8,
            child: AmbientLoop(
              period: Duration(milliseconds: period),
              restT: restT,
              builder: (context, t, child) => Transform.translate(
                offset: Offset(0, pingPongBetween(t, 0, -4)),
                child: child,
              ),
              child: object,
            ),
          ),
        ],
      ),
    );
  }
}

/// A localised `filter: blur(Npx)`, used for the prototype's soft highlights
/// and contact shadows.
class _Blur extends StatelessWidget {
  const _Blur({required this.sigma, required this.child});

  final double sigma;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ui.ImageFilter.blur(
        sigmaX: sigma,
        sigmaY: sigma,
        tileMode: TileMode.decal,
      ),
      child: child,
    );
  }
}
