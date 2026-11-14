import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/foreseeme_theme.dart';
import '../../../../core/theme/foreseeme_tokens.dart';
import '../../../../core/widgets/offline_state.dart';
import '../../../risk/domain/services/explanation_templater.dart';
import '../../../risk/domain/services/risk_staleness.dart';
import '../../../risk/presentation/risk_provider.dart';
import '../../domain/models/disease_risk_estimate.dart';
import '../disease_explorer_providers.dart';
import 'disease_trend_chart.dart';

class DiseaseDetailPanel extends ConsumerWidget {
  final String city, disease;
  final DiseaseRiskEstimate? estimate;
  const DiseaseDetailPanel({
    super.key,
    required this.city,
    required this.disease,
    required this.estimate,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = estimate;
    final p = context.fsmPalette;
    final historyKey = (city: city, disease: disease);
    final history = ref.watch(diseaseHistoryProvider(historyKey));
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(ForeSeeMeSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${diseaseNames[disease]} · $city',
                    style: context.fsmText.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close details',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (e == null)
              const Text(
                'Independent estimate unavailable. Older records may only contain the dominant disease; that summary cannot stand in for this prediction.',
              )
            else ...[
              Text(
                '${e.riskLevel} environmental risk',
                style: context.fsmText.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Model confidence: ${(e.confidence * 100).toStringAsFixed(1)}%',
              ),
              if (e.lowConfidence)
                Text(
                  'Low confidence. Interpret cautiously.',
                  style: TextStyle(color: p.warning),
                ),
              if (isRiskStale(e.generatedAt))
                Text(
                  'Stale estimate. Conditions may have changed.',
                  style: TextStyle(color: p.warning),
                ),
              const SizedBox(height: 8),
              Text(
                'Computed ${e.generatedAt.toIso8601String().substring(0, 16)} UTC · ${e.modelVersion}',
                style: context.fsmText.bodySmall,
              ),
              const SizedBox(height: 24),
              Text(
                'Model class probabilities',
                style: context.fsmText.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'How the model distributes confidence across risk categories. These are not probabilities of infection.',
              ),
              const SizedBox(height: 12),
              for (final entry in e.probabilities.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(entry.key)),
                          Text('${(entry.value * 100).toStringAsFixed(1)}%'),
                        ],
                      ),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: entry.value,
                        minHeight: 5,
                        color: p.secondary,
                        backgroundColor: p.surfaceContainerHighest,
                        semanticsLabel: '${entry.key} class probability',
                        semanticsValue:
                            '${(entry.value * 100).toStringAsFixed(1)}%',
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                'Environmental contributors',
                style: context.fsmText.titleMedium,
              ),
              const SizedBox(height: 8),
              if (e.attributions == null)
                const Text(
                  'An independent explanation is unavailable for this estimate.',
                )
              else ...[
                Text(
                  'These model signals change confidence in the ${e.riskLevel} class. They do not establish medical causation.',
                ),
                const SizedBox(height: 12),
                for (final c in e.attributions!.topContributors)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ExplanationTemplater.featureLabel(c.feature),
                          style: context.fsmText.labelLarge,
                        ),
                        Text(
                          '${c.contribution >= 0 ? '+' : ''}${(c.contribution * 100).toStringAsFixed(2)} percentage points toward the ${e.riskLevel} class',
                        ),
                      ],
                    ),
                  ),
                Text(
                  'Method: tree-path contributions · largest contributors shown',
                  style: context.fsmText.bodySmall,
                ),
              ],
              const SizedBox(height: 24),
              Text(
                'Precautions & guidance',
                style: context.fsmText.titleMedium,
              ),
              const SizedBox(height: 8),
              ref
                  .watch(
                    diseaseAdviceProvider((
                      disease: disease,
                      level: e.riskLevel,
                    )),
                  )
                  .when(
                    loading: () => const Text('Loading verified guidance…'),
                    error: (_, _) =>
                        const Text('Verified guidance is unavailable.'),
                    data: (advice) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (advice.category == '*')
                          const Text(
                            'General guidance from the existing content library',
                          ),
                        Text(advice.text),
                        const SizedBox(height: 8),
                        Text(advice.source, style: context.fsmText.labelMedium),
                        SelectableText(
                          advice.sourceUrl,
                          style: context.fsmText.bodySmall,
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            context.push(advice.deepLink);
                          },
                          child: const Text('Open health resources'),
                        ),
                      ],
                    ),
                  ),
            ],
            const SizedBox(height: 24),
            Text('Independent history', style: context.fsmText.titleMedium),
            const SizedBox(height: 12),
            if (ref
                    .watch(riskHistoryProvider(city))
                    .asData
                    ?.value
                    .any((record) => record.isFromCache) ==
                true)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Cached history · may be offline. Records may not include the latest estimates.',
                ),
              ),
            history.when(
              loading: () => const Text('Loading recorded history…'),
              error: (error, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isOfflineError(error)
                        ? 'History unavailable while offline.'
                        : 'Could not load history.',
                  ),
                  TextButton(
                    onPressed: () => ref.invalidate(riskHistoryProvider(city)),
                    child: const Text('Retry history'),
                  ),
                ],
              ),
              data: (values) => DiseaseTrendChart(history: values),
            ),
            const SizedBox(height: 24),
            const Text(
              'Environmental decision support only. Not a diagnosis, confirmed outbreak, or measure of infection prevalence.',
            ),
          ],
        ),
      ),
    );
  }
}
