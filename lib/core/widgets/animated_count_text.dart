import 'package:flutter/material.dart';

import 'app_motion.dart';

/// Counts up from 0 to [value] the first time it's built — the "smooth
/// number counting" micro-interaction (Feature 8) shared by the adherence
/// hero, level, and weekly-reflection cards. Honours reduced motion (jumps
/// straight to the final value).
class AnimatedCountText extends StatelessWidget {
  final int value;
  final String suffix;
  final TextStyle? style;
  final Duration duration;

  const AnimatedCountText({
    super.key,
    required this.value,
    this.suffix = '',
    this.style,
    this.duration = const Duration(milliseconds: 900),
  });

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduceMotion(context)) {
      return Text('$value$suffix', style: style);
    }
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: 0, end: value),
      duration: duration,
      curve: AppMotion.curve,
      builder: (context, animatedValue, _) =>
          Text('$animatedValue$suffix', style: style),
    );
  }
}
