import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_journey_model.dart';

/// Celebrate Progress (Feature 7): a subtle card for every milestone, with a
/// lightweight confetti burst reserved for major ones (level-ups, a first
/// perfect week) — never for a routine streak update. Hand-rolled with
/// `CustomPainter` rather than a confetti package, so it adds zero new
/// dependencies. Auto-dismisses, and is always dismissible by tapping.
class MilestoneCelebrationOverlay extends StatefulWidget {
  const MilestoneCelebrationOverlay({
    super.key,
    required this.milestone,
    required this.onDismiss,
  });

  final Milestone milestone;
  final VoidCallback onDismiss;

  @override
  State<MilestoneCelebrationOverlay> createState() =>
      _MilestoneCelebrationOverlayState();
}

class _MilestoneCelebrationOverlayState
    extends State<MilestoneCelebrationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_ConfettiParticle> _particles;
  Timer? _autoDismissTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..forward();
    _particles = _generateParticles();

    _autoDismissTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) widget.onDismiss();
    });
  }

  List<_ConfettiParticle> _generateParticles() {
    // Fixed seed: a deterministic, reproducible burst rather than true
    // randomness (keeps this testable and avoids visual flakiness).
    final random = Random(7);
    return List.generate(24, (_) {
      return _ConfettiParticle(
        x0: random.nextDouble(),
        startDelay: random.nextDouble() * 0.25,
        drift: (random.nextDouble() - 0.5) * 2,
        size: 5 + random.nextDouble() * 5,
        rotationSpeed: 2 + random.nextDouble() * 4,
        colorIndex: random.nextInt(4),
      );
    });
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final milestone = widget.milestone;
    final palette = context.fsmPalette;
    final reduce = AppMotion.reduceMotion(context);
    final showConfetti = milestone.isMajor && !reduce;

    return Positioned.fill(
      child: Semantics(
        liveRegion: true,
        label: '${milestone.title}. ${milestone.message}',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onDismiss,
          child: Stack(
            alignment: Alignment.center,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 260),
                builder: (context, value, _) => Container(
                  color: palette.scrim.withValues(alpha: 0.45 * value),
                ),
              ),
              if (showConfetti)
                IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) => CustomPaint(
                      size: Size.infinite,
                      painter: _ConfettiPainter(
                        progress: _controller.value,
                        particles: _particles,
                        colors: [
                          palette.primary,
                          palette.secondary,
                          context.fsmColors.success,
                          context.fsmColors.warning,
                        ],
                      ),
                    ),
                  ),
                ),
              _CelebrationCard(milestone: milestone, onDismiss: widget.onDismiss),
            ],
          ),
        ),
      ),
    );
  }
}

class _CelebrationCard extends StatelessWidget {
  const _CelebrationCard({required this.milestone, required this.onDismiss});

  final Milestone milestone;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final reduce = AppMotion.reduceMotion(context);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: reduce ? Duration.zero : const Duration(milliseconds: 380),
      curve: AppMotion.curve,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.scale(scale: 0.9 + (0.1 * value), child: child),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          decoration: ForeSeeMeSurface.card(
            context,
            radius: ForeSeeMeRadius.lg,
            borderColor: palette.primary.withValues(alpha: 0.4),
            shadow: [
              BoxShadow(
                color: palette.primary.withValues(alpha: 0.28),
                blurRadius: 40,
                spreadRadius: -14,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(milestone.emoji, style: const TextStyle(fontSize: 48)),
              const SizedBox(height: 14),
              Text(
                milestone.title,
                textAlign: TextAlign.center,
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                milestone.message,
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: palette.textSecondary),
              ),
              const SizedBox(height: 18),
              Semantics(
                button: true,
                label: 'Dismiss',
                child: TextButton(
                  onPressed: onDismiss,
                  child: const Text('Nice!'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfettiParticle {
  final double x0;
  final double startDelay;
  final double drift;
  final double size;
  final double rotationSpeed;
  final int colorIndex;

  const _ConfettiParticle({
    required this.x0,
    required this.startDelay,
    required this.drift,
    required this.size,
    required this.rotationSpeed,
    required this.colorIndex,
  });
}

class _ConfettiPainter extends CustomPainter {
  final double progress;
  final List<_ConfettiParticle> particles;
  final List<Color> colors;

  const _ConfettiPainter({
    required this.progress,
    required this.particles,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final particle in particles) {
      final localProgress = progress < particle.startDelay
          ? 0.0
          : ((progress - particle.startDelay) / (1 - particle.startDelay))
                .clamp(0.0, 1.0);
      if (localProgress <= 0) continue;

      final y = localProgress * size.height;
      final sway = sin(localProgress * pi * 3) * 24 * particle.drift;
      final x = (particle.x0 * size.width) + sway;
      final opacity = localProgress > 0.8
          ? (1 - localProgress) / 0.2
          : 1.0;
      if (opacity <= 0) continue;

      final paint = Paint()
        ..color = colors[particle.colorIndex % colors.length]
            .withValues(alpha: opacity.clamp(0.0, 1.0));

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(localProgress * particle.rotationSpeed * pi);
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: particle.size,
          height: particle.size * 0.6,
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
