import 'package:flutter/material.dart';
import '../../../../core/theme/foreseeme_theme.dart';
import '../../../../core/theme/foreseeme_surface.dart';
import '../../../../core/theme/foreseeme_tokens.dart';
import '../../../../core/widgets/app_motion.dart';

/// Static atmospheric art, not a sensor or a visualization of prediction data.
class DiseaseHero extends StatelessWidget {
  const DiseaseHero({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.fsmPalette;
    return AppReveal(
      child: Container(
        decoration: ForeSeeMeSurface.card(context, radius: ForeSeeMeRadius.xl),
        padding: const EdgeInsets.all(ForeSeeMeSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'ENVIRONMENT & HEALTH',
                    style: context.fsmText.labelSmall?.copyWith(
                      color: p.secondary,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                ExcludeSemantics(
                  child: RepaintBoundary(
                    child: SizedBox(
                      width: 80,
                      height: 80,
                      child: CustomPaint(
                        painter: _AtmospherePainter(
                          p.secondary,
                          p.tertiary,
                          p.surfaceBright,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Text(
              'One city.\nThree perspectives.',
              style: context.fsmText.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: ForeSeeMeSpacing.md),
            Text(
              'Explore each environmental risk independently. Understand the evidence behind the estimate.',
              style: context.fsmText.bodyMedium?.copyWith(
                color: p.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AtmospherePainter extends CustomPainter {
  final Color teal, violet, highlight;
  const _AtmospherePainter(this.teal, this.violet, this.highlight);
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: center, radius: size.width * .38);
    canvas.drawCircle(
      center,
      size.width * .47,
      Paint()
        ..shader = RadialGradient(
          colors: [teal.withValues(alpha: .2), teal.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawOval(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.5, -.6),
          colors: [highlight, teal, violet],
          stops: const [0, .45, 1],
        ).createShader(rect),
    );
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-.45);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: size.width * .95,
        height: size.height * .32,
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = teal.withValues(alpha: .65),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AtmospherePainter old) =>
      teal != old.teal || violet != old.violet || highlight != old.highlight;
}
