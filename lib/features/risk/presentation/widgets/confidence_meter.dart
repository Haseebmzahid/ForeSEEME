import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';

/// A thin proportional fill bar visualising the model's real confidence value
/// (Playbook M-1 item 2) — the pill badge next to it states the number in
/// text; this bar gives it a visual magnitude so confidence reads as more
/// than a caption. [confidence] must already be the real stored probability
/// in `[0.0, 1.0]` — this widget never invents or clamps a fabricated value
/// beyond that range.
class ConfidenceMeter extends StatelessWidget {
  final double confidence;
  final double width;

  const ConfidenceMeter({
    super.key,
    required this.confidence,
    this.width = 120,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = confidence.clamp(0.0, 1.0);
    final color = _colorFor(context, fraction);

    return ExcludeSemantics(
      // The pill badge beside this bar already carries the accessible label
      // ("N% confidence"); the bar itself is a decorative reinforcement, not a
      // second, differently-worded announcement.
      child: SizedBox(
        width: width,
        height: 6,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Stack(
            children: [
              Container(color: context.fsmPalette.surfaceContainerHighest),
              FractionallySizedBox(
                widthFactor: fraction,
                child: Container(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Mirrors [ConfidenceExplanation]'s strong/moderate/weak → semantic-token
  /// mapping: low confidence renders as the neutral tone, never the error red
  /// (which would misread as "high risk" right beside the hero card's own risk
  /// colour).
  Color _colorFor(BuildContext context, double fraction) {
    final colors = context.fsmColors;
    if (fraction >= 0.75) return colors.success;
    if (fraction >= 0.5) return colors.warning;
    return context.fsmPalette.onSurfaceVariant;
  }
}
