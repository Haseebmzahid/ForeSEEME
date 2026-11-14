import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/foreseeme_theme.dart';
import '../../../core/theme/foreseeme_tokens.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/offline_state.dart';
import '../../health_profile/domain/constants/cities_constants.dart';
import '../../health_profile/presentation/health_profile_providers.dart';
import '../../risk/presentation/risk_provider.dart';
import '../../risk/domain/models/risk_estimate_model.dart';
import '../domain/models/disease_risk_estimate.dart';
import '../domain/services/disease_explorer_service.dart';
import 'widgets/disease_hero.dart';
import 'widgets/disease_risk_card.dart';
import 'widgets/disease_detail_panel.dart';

class DiseaseExplorerScreen extends ConsumerStatefulWidget {
  final String? initialCity;
  const DiseaseExplorerScreen({super.key, this.initialCity});
  @override
  ConsumerState<DiseaseExplorerScreen> createState() =>
      _DiseaseExplorerScreenState();
}

class _DiseaseExplorerScreenState extends ConsumerState<DiseaseExplorerScreen> {
  String? _city;
  @override
  void initState() {
    super.initState();
    if (kSupportedCities.contains(widget.initialCity)) {
      _city = widget.initialCity;
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileCity = ref.watch(userCityProvider).asData?.value;
    final city =
        _city ??
        (kSupportedCities.contains(profileCity)
            ? profileCity!
            : kSupportedCities.first);
    final result = ref.watch(latestRiskForCityProvider(city));
    // Keep failures actionable while Riverpod retries in the background.
    final AsyncValue<RiskEstimateModel?> state = result.hasError
        ? AsyncError(result.error!, result.stackTrace ?? StackTrace.empty)
        : result;
    final p = context.fsmPalette;
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        title: const Text('Disease Explorer'),
        actions: [
          IconButton(
            tooltip: 'Refresh estimates',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              ref.invalidate(latestRiskForCityProvider(city));
              ref.invalidate(riskHistoryProvider(city));
            },
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: context.fsmColors.gradients.surface,
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1040),
                  child: Padding(
                    padding: const EdgeInsets.all(ForeSeeMeSpacing.gutter),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const DiseaseHero(),
                        const SizedBox(height: 24),
                        Text(
                          'YOUR CITY',
                          style: context.fsmText.labelSmall?.copyWith(
                            letterSpacing: 1.5,
                            color: p.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          key: ValueKey(city),
                          initialValue: city,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Selected city',
                            prefixIcon: Icon(Icons.location_on_outlined),
                          ),
                          items: [
                            for (final name in kSupportedCities)
                              DropdownMenuItem(value: name, child: Text(name)),
                          ],
                          onChanged: (value) {
                            if (value != null) setState(() => _city = value);
                          },
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Independent estimates',
                          style: context.fsmText.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Each disease has its own model classification.',
                          style: context.fsmText.bodyMedium?.copyWith(
                            color: p.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        state.when(
                          skipLoadingOnRefresh: false,
                          loading: () => const Padding(
                            padding: EdgeInsets.all(32),
                            child: Column(
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 16),
                                Text('Loading independent estimates…'),
                              ],
                            ),
                          ),
                          error: (error, _) => Column(
                            children: [
                              Icon(
                                isOfflineError(error)
                                    ? Icons.wifi_off_rounded
                                    : Icons.cloud_off_rounded,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                isOfflineError(error)
                                    ? 'Offline · no estimate available'
                                    : 'Could not load estimates',
                              ),
                              TextButton(
                                onPressed: () => ref.invalidate(
                                  latestRiskForCityProvider(city),
                                ),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                          data: (document) => Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (document?.isFromCache == true)
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 16),
                                  child: Text(
                                    'Cached data · may be offline. Refresh when connected.',
                                  ),
                                ),
                              if (document == null ||
                                  document.diseaseEstimates.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: Text(
                                    'No independent estimates available for $city yet. Missing data does not mean low risk.',
                                  ),
                                ),
                              LayoutBuilder(
                                builder: (context, box) {
                                  final wide =
                                      box.maxWidth >= 780 &&
                                      MediaQuery.textScalerOf(
                                            context,
                                          ).scale(1) <=
                                          1.3;
                                  final cards = [
                                    for (final key in diseaseNames.keys)
                                      DiseaseRiskCard(
                                        disease: key,
                                        estimate:
                                            DiseaseExplorerService.estimate(
                                              document,
                                              key,
                                            ),
                                        onTap: () => showModalBottomSheet<void>(
                                          context: context,
                                          isScrollControlled: true,
                                          useSafeArea: true,
                                          constraints: const BoxConstraints(
                                            maxWidth: 720,
                                          ),
                                          sheetAnimationStyle:
                                              AppMotion.reduceMotion(context)
                                              ? AnimationStyle.noAnimation
                                              : null,
                                          builder: (_) => FractionallySizedBox(
                                            heightFactor: .9,
                                            child: DiseaseDetailPanel(
                                              city: city,
                                              disease: key,
                                              estimate:
                                                  DiseaseExplorerService.estimate(
                                                    document,
                                                    key,
                                                  ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ];
                                  return wide
                                      ? Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            for (
                                              var i = 0;
                                              i < cards.length;
                                              i++
                                            ) ...[
                                              if (i > 0)
                                                const SizedBox(width: 16),
                                              Expanded(child: cards[i]),
                                            ],
                                          ],
                                        )
                                      : Column(
                                          children: [
                                            for (final card in cards)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  bottom: 16,
                                                ),
                                                child: card,
                                              ),
                                          ],
                                        );
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        Icon(Icons.verified_user_outlined, color: p.secondary),
                        const SizedBox(height: 8),
                        Text(
                          'Environmental intelligence, thoughtfully interpreted.',
                          textAlign: TextAlign.center,
                          style: context.fsmText.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Risk categories are not infection rates. Confidence describes the model’s classification, not your chance of illness. These estimates are not medical diagnoses.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
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
