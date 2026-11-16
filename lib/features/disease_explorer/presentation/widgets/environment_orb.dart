import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/theme/foreseeme_palette.dart';
import '../../../../core/theme/foreseeme_theme.dart';
import '../../../../core/widgets/app_motion.dart';

/// Decorative environmental artwork. Its light and motion never encode risk.
class EnvironmentOrb extends StatefulWidget {
  const EnvironmentOrb({super.key, this.size = 112});
  final double size;
  @override
  State<EnvironmentOrb> createState() => _EnvironmentOrbState();
}

class _EnvironmentOrbState extends State<EnvironmentOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _orbit = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduceMotion(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _orbit.stop();
      _orbit.value = 0;
    } else if (!_orbit.isAnimating) {
      _orbit.repeat();
    }
  }

  @override
  void dispose() {
    _orbit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: CustomPaint(painter: _OrbPainter(context.fsmPalette, _orbit)),
      ),
    ),
  );
}

class _OrbPainter extends CustomPainter {
  _OrbPainter(this.p, this.orbit) : super(repaint: orbit);
  final ForeSeeMePalette p;
  final Animation<double> orbit;
  @override
  void paint(Canvas canvas, Size size) {
    final phase = orbit.value * math.pi * 2;
    final c = size.center(Offset(0, math.sin(phase) * size.height * .025));
    final r = size.shortestSide * .31;
    final sphere = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r * 1.6,
      Paint()
        ..shader = RadialGradient(
          colors: [
            p.secondary.withValues(alpha: .23),
            p.tertiary.withValues(alpha: .07),
            p.secondary.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: r * 1.6)),
    );
    void ring(double tilt, double width, bool front) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(tilt);
      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: r * width,
        height: r * .85,
      );
      canvas.drawArc(
        rect,
        front ? 0 : math.pi,
        math.pi,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = front ? 1.5 : .8
          ..shader = SweepGradient(
            colors: [
              p.secondary.withValues(alpha: .08),
              p.secondary.withValues(alpha: .75),
              p.tertiary.withValues(alpha: .5),
              p.secondary.withValues(alpha: .08),
            ],
          ).createShader(rect),
      );
      canvas.restore();
    }

    final tilt = -.4 + math.sin(phase) * .12;
    ring(tilt, 3.1, false);
    ring(tilt + 1.05, 2.7, false);
    canvas.drawCircle(
      c + Offset(0, r * .10),
      r * 1.02,
      Paint()..color = p.shadow.withValues(alpha: .18),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: Alignment(-.5 + math.sin(phase) * .08, -.6),
          radius: 1.3,
          colors: [
            p.secondaryContainer,
            p.secondary,
            p.tertiary,
            p.isDark ? p.background : p.onTertiaryContainer,
          ],
          stops: const [0, .32, .72, 1],
        ).createShader(sphere),
    );
    canvas.save();
    canvas.clipPath(Path()..addOval(sphere));
    for (var i = 0; i < 4; i++) {
      canvas.drawOval(
        Rect.fromCenter(
          center: c + Offset(r * .2, r * (.1 + i * .21)),
          width: r * 2.3,
          height: r * (1.2 + i * .15),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * .025
          ..color = p.surfaceBright.withValues(alpha: .10 - i * .018),
      );
    }
    canvas.drawOval(
      Rect.fromCenter(
        center: c + Offset(-r * .32, -r * .40),
        width: r * .85,
        height: r * .6,
      ),
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                p.surfaceBright.withValues(alpha: .85),
                p.surfaceBright.withValues(alpha: 0),
              ],
            ).createShader(
              Rect.fromCircle(
                center: c + Offset(-r * .32, -r * .40),
                radius: r * .45,
              ),
            ),
    );
    canvas.restore();
    ring(tilt, 3.1, true);
    ring(tilt + 1.05, 2.7, true);
  }

  @override
  bool shouldRepaint(_OrbPainter oldDelegate) =>
      p != oldDelegate.p || orbit != oldDelegate.orbit;
}
