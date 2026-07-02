import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/app_design_v2.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/core/widgets/app_skeleton.dart';
import 'package:fyp_foreseeme/core/widgets/empty_state.dart';
import 'package:fyp_foreseeme/core/widgets/error_state.dart';
import 'package:fyp_foreseeme/core/widgets/medical_disclaimer.dart';
import 'package:fyp_foreseeme/core/widgets/offline_state.dart';
import 'package:fyp_foreseeme/features/health_profile/domain/constants/cities_constants.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/domain/services/risk_comparison_service.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_visuals.dart';

/// City & Disease Comparison (Sprint 5, Prompt 9).
///
/// **Descriptive only.** Reuses the existing risk reads ([allCitiesRiskProvider],
/// [cityDiseaseSummaryProvider]) — no new query or write path. Two views:
/// cities ranked by their latest risk, and the diseases a chosen city has faced
/// recently. Charts are never colour-only: every bar carries a text label + a
/// distinct risk icon (via [RiskVisuals]).
class ComparisonScreen extends ConsumerStatefulWidget {
  const ComparisonScreen({super.key});

  @override
  ConsumerState<ComparisonScreen> createState() => _ComparisonScreenState();
}

enum _View { cities, diseases }

class _ComparisonScreenState extends ConsumerState<ComparisonScreen> {
  _View _view = _View.cities;
  String? _selectedCity;

  @override
  Widget build(BuildContext context) {
    final defaultCity =
        _selectedCity ??
        ref.watch(userCityProvider).asData?.value ??
        kSupportedCities.first;

    return Scaffold(
      backgroundColor: AppColorsV2.shell,
      appBar: AppBar(
        backgroundColor: AppColorsV2.shell,
        elevation: 0,
        foregroundColor: AppColorsV2.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => context.pop(),
        ),
        title: Text('Compare', style: AppTextStylesV2.cardTitle),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: _ViewToggle(
                view: _view,
                onChanged: (v) => setState(() => _view = v),
              ),
            ),
            Expanded(
              child: AppMotion.stateSwitcher(
                context,
                _view == _View.cities
                    ? const _CitiesView()
                    : _DiseasesView(
                        city: defaultCity,
                        onCityChanged: (c) => setState(() => _selectedCity = c),
                      ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: MedicalDisclaimer.banner(),
            ),
          ],
        ),
      ),
    );
  }
}

// ── View toggle ──────────────────────────────────────────────────────────────

class _ViewToggle extends StatelessWidget {
  final _View view;
  final ValueChanged<_View> onChanged;
  const _ViewToggle({required this.view, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColorsV2.glassFill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColorsV2.stroke),
      ),
      child: Row(
        children: [
          _segment('Cities', _View.cities),
          _segment('Diseases', _View.diseases),
        ],
      ),
    );
  }

  Widget _segment(String label, _View value) {
    final selected = view == value;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: GestureDetector(
          onTap: () => onChanged(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? AppColorsV2.teal.withValues(alpha: 0.18) : null,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected
                    ? AppColorsV2.teal.withValues(alpha: 0.5)
                    : Colors.transparent,
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: AppTextStylesV2.body.copyWith(
                color: selected ? AppColorsV2.teal : AppColorsV2.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Cities view ──────────────────────────────────────────────────────────────

class _CitiesView extends ConsumerWidget {
  const _CitiesView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(allCitiesRiskProvider);
    return async.when(
      loading: () => const _BarsSkeleton(),
      error: (error, _) => isOfflineError(error)
          ? OfflineState(onRetry: () => ref.invalidate(allCitiesRiskProvider))
          : ErrorState(
              title: "Couldn't load the comparison",
              explanation: 'Something went wrong. Please try again.',
              onRetry: () => ref.invalidate(allCitiesRiskProvider),
              detail: '$error',
            ),
      data: (estimates) {
        if (estimates.isEmpty) {
          return const EmptyState(
            icon: Icons.location_city_outlined,
            title: 'No city estimates yet',
            description:
                'Risk estimates for your cities will appear here once the '
                'weekly pipeline has run.',
          );
        }
        final ranked = rankCitiesBySeverity(estimates);
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Text(
              'Latest environmental risk across cities, most severe first.',
              style: AppTextStylesV2.body,
            ),
            const SizedBox(height: 14),
            for (final e in ranked)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ComparisonRow(
                  title: e.city,
                  subtitle: e.disease,
                  level: e.riskLevel,
                  lowConfidence: e.lowConfidence,
                ),
              ),
          ],
        );
      },
    );
  }
}

// ── Diseases view ────────────────────────────────────────────────────────────

class _DiseasesView extends ConsumerWidget {
  final String city;
  final ValueChanged<String> onCityChanged;
  const _DiseasesView({required this.city, required this.onCityChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(cityDiseaseSummaryProvider(city));
    return Column(
      children: [
        _CityPicker(selected: city, onChanged: onCityChanged),
        Expanded(
          child: async.when(
            loading: () => const _BarsSkeleton(),
            error: (error, _) => isOfflineError(error)
                ? OfflineState(
                    onRetry: () =>
                        ref.invalidate(cityDiseaseSummaryProvider(city)),
                  )
                : ErrorState(
                    title: "Couldn't load the comparison",
                    explanation: 'Something went wrong. Please try again.',
                    onRetry: () =>
                        ref.invalidate(cityDiseaseSummaryProvider(city)),
                    detail: '$error',
                  ),
            data: (summaries) {
              if (summaries.isEmpty) {
                return EmptyState(
                  icon: Icons.coronavirus_outlined,
                  title: 'No recent history for $city',
                  description:
                      'Once a few weekly estimates are recorded for $city, the '
                      'diseases it has faced will be compared here.',
                );
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: [
                  Text(
                    'Diseases $city has faced over recent weeks, most severe '
                    'first.',
                    style: AppTextStylesV2.body,
                  ),
                  const SizedBox(height: 14),
                  for (final s in summaries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ComparisonRow(
                        title: s.disease,
                        subtitle: s.weeksObserved == 1
                            ? '1 week'
                            : '${s.weeksObserved} weeks',
                        level: s.latestLevel,
                        lowConfidence: s.latestLowConfidence,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CityPicker extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;
  const _CityPicker({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
        children: [
          for (final city in kSupportedCities)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _CityChip(
                label: city,
                selected: city == selected,
                onTap: () => onChanged(city),
              ),
            ),
        ],
      ),
    );
  }
}

class _CityChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _CityChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? AppColorsV2.teal.withValues(alpha: 0.18)
                : AppColorsV2.glassFill,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? AppColorsV2.teal.withValues(alpha: 0.5)
                  : AppColorsV2.stroke,
            ),
          ),
          child: Text(
            label,
            style: AppTextStylesV2.caption.copyWith(
              color: selected ? AppColorsV2.teal : AppColorsV2.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Comparison row (label + icon + bar — never colour alone) ────────────────

class _ComparisonRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final RiskLevel level;
  final bool lowConfidence;

  const _ComparisonRow({
    required this.title,
    required this.subtitle,
    required this.level,
    required this.lowConfidence,
  });

  @override
  Widget build(BuildContext context) {
    final a = RiskVisuals.of(level, lowConfidence: lowConfidence);
    return Semantics(
      container: true,
      label: '$title, $subtitle: ${a.label} risk',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: AppTextStylesV2.body.copyWith(
                    color: AppColorsV2.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              // Risk pill: icon + label (readable in greyscale).
              Icon(a.icon, size: 14, color: a.color),
              const SizedBox(width: 5),
              Text(
                a.label,
                style: AppTextStylesV2.caption.copyWith(
                  color: a.color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _Bar(fraction: severityFraction(level), color: a.color),
          const SizedBox(height: 4),
          Text(subtitle, style: AppTextStylesV2.caption),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final double fraction;
  final Color color;
  const _Bar({required this.fraction, required this.color});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Stack(
            children: [
              Container(height: 10, color: AppColorsV2.stroke),
              Container(
                height: 10,
                width: constraints.maxWidth * fraction,
                color: color,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Skeleton ─────────────────────────────────────────────────────────────────

class _BarsSkeleton extends StatelessWidget {
  const _BarsSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      physics: NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: AppSkeleton(
        child: Column(
          children: [
            SkeletonBox(height: 44),
            SizedBox(height: 14),
            SkeletonBox(height: 44),
            SizedBox(height: 14),
            SkeletonBox(height: 44),
            SizedBox(height: 14),
            SkeletonBox(height: 44),
          ],
        ),
      ),
    );
  }
}
