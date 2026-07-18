import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_journey_model.dart';

/// Smart Insight Cards (Feature 5): up to 3 deterministic, rule-based
/// observations from `AdherenceJourneyService` — no AI, just existing
/// adherence data read through a few supportive rules.
class InsightCardsWidget extends StatelessWidget {
  const InsightCardsWidget({super.key, required this.insights});

  final List<InsightCard> insights;

  @override
  Widget build(BuildContext context) {
    if (insights.isEmpty) return const SizedBox.shrink();

    final text = context.fsmText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text('Insights', style: text.titleLarge),
        ),
        for (var i = 0; i < insights.length; i++) ...[
          _InsightTile(insight: insights[i]),
          if (i != insights.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _InsightTile extends StatelessWidget {
  const _InsightTile({required this.insight});

  final InsightCard insight;

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;

    return Semantics(
      container: true,
      label: '${insight.title}. ${insight.message}',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: ForeSeeMeSurface.card(context, radius: ForeSeeMeRadius.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: palette.secondary.withValues(alpha: 0.14),
                ),
                child: Text(
                  insight.emoji,
                  style: const TextStyle(fontSize: 18),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      insight.title,
                      style: text.titleMedium?.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      insight.message,
                      style: text.bodyMedium?.copyWith(
                        color: palette.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
