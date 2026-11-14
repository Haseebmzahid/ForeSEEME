import 'package:flutter/material.dart';
import '../../../../core/theme/foreseeme_theme.dart';
import '../../domain/models/disease_risk_estimate.dart';

/// Discrete observations, deliberately unconnected across missing records.
/// Equal-width columns are dated observations, not an invented continuous curve.
class DiseaseTrendChart extends StatelessWidget {
  final List<DiseaseRiskEstimate> history;
  const DiseaseTrendChart({super.key, required this.history});
  @override
  Widget build(BuildContext context) {
    if (history.length < 2) {
      return const Text(
        'Disease-specific history is not yet available. At least two independent records are needed.',
      );
    }
    final color = context.fsmPalette.secondary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Recorded categories · each column is a dated observation'),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final e in history)
                Semantics(
                  label:
                      '${e.generatedAt.toIso8601String()}, ${e.riskLevel} risk, model ${e.modelVersion}',
                  child: ExcludeSemantics(
                    child: SizedBox(
                      width: 100 * MediaQuery.textScalerOf(context).scale(1),
                      child: Column(
                        children: [
                          for (final level in const ['High', 'Medium', 'Low'])
                            Container(
                              constraints: const BoxConstraints(minHeight: 32),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              alignment: Alignment.center,
                              margin: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: e.riskLevel == level
                                    ? color.withValues(alpha: .14)
                                    : null,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                e.riskLevel == level ? '● $level' : '·',
                                style: context.fsmText.labelMedium,
                              ),
                            ),
                          const SizedBox(height: 6),
                          Text(
                            e.generatedAt.toIso8601String().substring(0, 10),
                            style: context.fsmText.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Missing independent records are omitted. Categories are not infection rates.',
        ),
      ],
    );
  }
}
