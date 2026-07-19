import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/core/widgets/brand_loading.dart';
import 'package:fyp_foreseeme/core/widgets/empty_state.dart';
import 'package:fyp_foreseeme/core/widgets/error_state.dart';
import 'package:fyp_foreseeme/core/widgets/offline_state.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/services/alert_deep_link_router.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/insights/domain/models/health_recommendation.dart';
import 'package:fyp_foreseeme/features/insights/presentation/insights_providers.dart';
import 'package:fyp_foreseeme/features/risk/domain/constants/city_coordinates.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/domain/services/risk_staleness.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/collapsible_risk_legend.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/location_comparison_card.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_visuals.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/staleness_indicator.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/trend_badge.dart';

/// **Geospatial Health Intelligence** (Sprint: Geospatial Intelligence) — the
/// national risk map, transformed from a colour key into an explorable
/// surface. The map itself is unchanged (one colored zone per city, a Google
/// Map, never a fabricated density heatmap — see ADR/GOLDEN_RULES honesty
/// discussion): this sprint only enriches the presentation and interaction
/// around it — camera motion, a collapsible legend, a real two-city Location
/// Intelligence comparison, and an Area Insight sheet that explains *why* a
/// tapped city looks the way it does (reusing the same explainability
/// building blocks as Explainable Health Intelligence). Bound live to
/// [allCitiesRiskProvider]; handles loading / empty / error states.
class RiskMapScreen extends ConsumerStatefulWidget {
  const RiskMapScreen({super.key});

  @override
  ConsumerState<RiskMapScreen> createState() => _RiskMapScreenState();
}

class _RiskMapScreenState extends ConsumerState<RiskMapScreen> {
  String? _selectedCity;
  bool _comparisonDismissed = false;
  GoogleMapController? _controller;

  // Centred on Pakistan so all five cities are in view on open.
  static const CameraPosition _initialCamera = CameraPosition(
    target: LatLng(30.4, 71.5),
    zoom: 5.1,
  );

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// Explicit selection (a tap, or returning from Recent Activity) — glides
  /// the camera to the city, unlike the passive worst-case default in
  /// [_resolveSelected].
  void _selectCity(String city) {
    setState(() => _selectedCity = city);
    final coord = kCityCoordinates[city];
    if (coord != null) {
      _controller?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(coord.lat, coord.lon), 8.5),
      );
    }
  }

  Future<void> _openRecentActivity() async {
    // Pops back with the tapped alert's city (if any) rather than pushing a
    // second GoogleMap instance — one live map, no wasted platform view.
    final city = await context.push<String>('/risk-activity');
    if (city != null && city.isNotEmpty && mounted) {
      _selectCity(city);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final async = ref.watch(allCitiesRiskProvider);

    return Scaffold(
      backgroundColor: palette.background,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: palette.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: Text('Geospatial Risk Map', style: context.fsmText.titleLarge),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'Recent activity',
            onPressed: _openRecentActivity,
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart_rounded),
            tooltip: 'Compare cities & diseases',
            onPressed: () => context.push('/compare'),
          ),
        ],
      ),
      body: AppMotion.stateSwitcher(
        context,
        async.when(
          loading: () => const BrandLoading(message: 'Loading national risk…'),
          error: (error, _) => isOfflineError(error)
              ? OfflineState(
                  onRetry: () => ref.invalidate(allCitiesRiskProvider),
                )
              : ErrorState(
                  title: "Couldn't load the map",
                  explanation:
                      'Something went wrong loading the map. Please try again.',
                  onRetry: () => ref.invalidate(allCitiesRiskProvider),
                  detail: '$error',
                ),
          data: (estimates) {
            if (estimates.isEmpty) {
              return const EmptyState(
                icon: Icons.map_outlined,
                title: 'No risk data yet',
                description:
                    'We have no city estimates to map this week. Check back soon.',
              );
            }
            return _buildMap(estimates);
          },
        ),
      ),
    );
  }

  Widget _buildMap(List<RiskEstimateModel> estimates) {
    final selected = _resolveSelected(estimates);

    return Stack(
      children: [
        Positioned.fill(
          child: GoogleMap(
            initialCameraPosition: _initialCamera,
            onMapCreated: (controller) => _controller = controller,
            // Deep-space style in dark mode; the default light map otherwise.
            style: context.fsmPalette.isDark ? _kDarkMapStyle : null,
            circles: _circlesFor(estimates),
            markers: _markersFor(estimates),
            // The Maps SDK owns its own permission prompt for the blue dot —
            // an honest "You are here" with no separate location plumbing.
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 16, top: 8),
              child: const CollapsibleRiskLegend(initiallyExpanded: false),
            ),
          ),
        ),
        if (!_comparisonDismissed)
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 16, top: 8),
                child: _LocationComparisonSlot(
                  onDismiss: () => setState(() => _comparisonDismissed = true),
                ),
              ),
            ),
          ),
        Align(
          alignment: Alignment.bottomCenter,
          child: AnimatedSwitcher(
            duration: AppMotion.medium,
            switchInCurve: AppMotion.curve,
            switchOutCurve: AppMotion.curve,
            transitionBuilder: (child, animation) => SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.15),
                end: Offset.zero,
              ).animate(animation),
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: selected == null
                ? const SizedBox.shrink(key: ValueKey('no-selection'))
                : CityDetailSheet(
                    key: ValueKey(selected.city),
                    estimate: selected,
                  ),
          ),
        ),
      ],
    );
  }

  /// The estimate to show in the sheet: the explicitly tapped city, else the
  /// highest-risk city (so the worst case surfaces first).
  RiskEstimateModel? _resolveSelected(List<RiskEstimateModel> estimates) {
    if (estimates.isEmpty) return null;
    if (_selectedCity != null) {
      for (final e in estimates) {
        if (e.city == _selectedCity) return e;
      }
    }
    final sorted = [...estimates]
      ..sort((a, b) => _score(b).compareTo(_score(a)));
    return sorted.first;
  }

  Set<Circle> _circlesFor(List<RiskEstimateModel> estimates) {
    final circles = <Circle>{};
    for (final e in estimates) {
      final coord = kCityCoordinates[e.city];
      if (coord == null) continue;
      final a = RiskVisuals.of(e.riskLevel, lowConfidence: e.lowConfidence);
      circles.add(
        Circle(
          circleId: CircleId(e.city),
          center: LatLng(coord.lat, coord.lon),
          radius: 45000,
          fillColor: a.color.withValues(alpha: 0.30),
          strokeColor: a.color,
          strokeWidth: 2,
          consumeTapEvents: true,
          onTap: () => _selectCity(e.city),
        ),
      );
    }
    return circles;
  }

  Set<Marker> _markersFor(List<RiskEstimateModel> estimates) {
    final markers = <Marker>{};
    for (final e in estimates) {
      final coord = kCityCoordinates[e.city];
      if (coord == null) continue;
      final a = RiskVisuals.of(e.riskLevel, lowConfidence: e.lowConfidence);
      markers.add(
        Marker(
          markerId: MarkerId(e.city),
          position: LatLng(coord.lat, coord.lon),
          icon: BitmapDescriptor.defaultMarkerWithHue(riskMarkerHue(a)),
          infoWindow: InfoWindow(title: e.city, snippet: '${a.label} risk'),
          onTap: () => _selectCity(e.city),
        ),
      );
    }
    return markers;
  }
}

int _score(RiskEstimateModel e) => switch (e.riskLevel) {
  RiskLevel.low => 0,
  RiskLevel.medium => 1,
  RiskLevel.high => 2,
};

/// Marker hue approximating the risk appearance (markers can't take an exact
/// colour). Uncertain (low-confidence) maps to azure to stand apart from the
/// three risk hues. Uses the static [RiskVisuals] identities.
double riskMarkerHue(RiskAppearance a) {
  if (identical(a, RiskVisuals.high)) return BitmapDescriptor.hueRed;
  if (identical(a, RiskVisuals.medium)) return BitmapDescriptor.hueOrange;
  if (identical(a, RiskVisuals.low)) return BitmapDescriptor.hueGreen;
  return BitmapDescriptor.hueAzure;
}

// ── Location Intelligence slot ───────────────────────────────────────────────

/// Watches [locationComparisonProvider] and shows the [LocationComparisonCard]
/// once real two-city data resolves; otherwise renders nothing (loading,
/// error, or fewer than two cities on record all degrade to empty — never a
/// half-filled card).
class _LocationComparisonSlot extends ConsumerWidget {
  const _LocationComparisonSlot({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(locationComparisonProvider);
    return async.maybeWhen(
      data: (comparison) => comparison == null
          ? const SizedBox.shrink()
          : LocationComparisonCard(
              comparison: comparison,
              onDismiss: onDismiss,
            ),
      orElse: () => const SizedBox.shrink(),
    );
  }
}

// ── Detail sheet ──────────────────────────────────────────────────────────────

/// Bottom sheet showing a tapped city's risk — name + driver + an accessible
/// risk pill (icon + label + colour), how long ago the estimate was
/// generated, an **Area Insight** section (primary contributor, recent trend,
/// and a cited recommendation for that area — Geospatial Intelligence sprint),
/// and — only for the user's own profile city, since `/risk-details` isn't
/// city-parameterised — a "View details" CTA into the full analytics screen.
class CityDetailSheet extends ConsumerWidget {
  final RiskEstimateModel estimate;

  const CityDetailSheet({super.key, required this.estimate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final a = RiskVisuals.resolve(
      context,
      estimate.riskLevel,
      lowConfidence: estimate.lowConfidence,
    );
    final isOwnCity = ref.watch(userCityProvider).value == estimate.city;
    final insightAsync = ref.watch(areaInsightProvider(estimate.city));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 26),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: ForeSeeMeSurface.stroke(context)),
        boxShadow: context.fsmColors.shadows.strong,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 4,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: palette.onSurfaceVariant.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(estimate.city, style: text.titleLarge),
                    const SizedBox(height: 2),
                    Text(
                      estimate.disease,
                      style: text.bodySmall?.copyWith(
                        color: palette.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Updated ${riskAgeLabel(estimate.generatedAt)}',
                      style: text.bodySmall?.copyWith(
                        color: palette.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: a.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: a.color.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(a.icon, size: 14, color: a.color),
                    const SizedBox(width: 6),
                    Text(
                      a.label,
                      style: text.bodySmall?.copyWith(
                        color: a.color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Honest staleness label for this city's estimate (self-guarding —
          // shows only when the cached/last estimate is out of date).
          RiskStalenessNotice(generatedAt: estimate.generatedAt, topGap: 14),
          // Area Insight — degrades to nothing while loading/erroring, so the
          // sheet above (unchanged) never depends on this section resolving.
          insightAsync.maybeWhen(
            data: (view) => view == null
                ? const SizedBox.shrink()
                : _AreaInsightExtras(view: view),
            orElse: () => const SizedBox.shrink(),
          ),
          // "View details" only for the user's own profile city: the full
          // Risk Details screen reads `currentCityRiskProvider` (the user's
          // city), not an arbitrary tapped city, so the CTA never claims to
          // open detail for a city it can't actually show.
          if (isOwnCity) ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => context.push('/risk-details'),
                style: TextButton.styleFrom(
                  foregroundColor: palette.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  minimumSize: const Size(0, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: palette.primary.withValues(alpha: 0.4),
                    ),
                  ),
                ),
                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                label: const Text('View details'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The Area Insight body: primary contributor, recent trend, and a cited
/// recommendation — genuine signals for the TAPPED city (Geospatial
/// Intelligence sprint), sourced from [areaInsightProvider].
class _AreaInsightExtras extends StatelessWidget {
  const _AreaInsightExtras({required this.view});

  final AreaInsightView view;

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Divider(height: 1, color: palette.outlineVariant),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PRIMARY CONTRIBUTOR',
                    style: text.labelSmall?.copyWith(
                      letterSpacing: 1.0,
                      color: palette.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    view.primaryDriver?.label ?? 'Not available',
                    style: text.bodyMedium?.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'RECENT TREND',
                  style: text.labelSmall?.copyWith(
                    letterSpacing: 1.0,
                    color: palette.textTertiary,
                  ),
                ),
                const SizedBox(height: 4),
                TrendBadge(direction: view.trend),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        _RecommendationRow(recommendation: view.recommendation),
      ],
    );
  }
}

class _RecommendationRow extends StatelessWidget {
  const _RecommendationRow({required this.recommendation});

  final HealthRecommendation recommendation;

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(ForeSeeMeRadius.sm),
        border: Border.all(color: palette.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            recommendation.text,
            style: text.bodyMedium?.copyWith(color: palette.textPrimary),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.verified_outlined,
                size: 13,
                color: palette.textTertiary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Source: ${recommendation.source}',
                  style: text.bodySmall?.copyWith(color: palette.textTertiary),
                ),
              ),
              _LearnMoreLink(deepLink: recommendation.deepLink),
            ],
          ),
        ],
      ),
    );
  }
}

/// Only offers navigation to a known in-app route (reuses the Prompt 4
/// whitelist) — mirrors `recommendations_card.dart`'s identical guard.
class _LearnMoreLink extends StatelessWidget {
  const _LearnMoreLink({required this.deepLink});

  final String deepLink;

  @override
  Widget build(BuildContext context) {
    if (!AlertDeepLinkRouter.knownRoutes.contains(deepLink)) {
      return const SizedBox.shrink();
    }
    return TextButton(
      onPressed: () {
        if (AlertDeepLinkRouter.shellBranchRoutes.contains(deepLink)) {
          context.go(deepLink);
        } else {
          context.push(deepLink);
        }
      },
      style: TextButton.styleFrom(
        foregroundColor: context.fsmPalette.primary,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        minimumSize: const Size(0, 44),
        tapTargetSize: MaterialTapTargetSize.padded,
        textStyle: context.fsmText.bodySmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      child: const Text('Learn more'),
    );
  }
}

// A dark Google Map style so the map matches the v2 deep-space shell (dark mode).
const String _kDarkMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#0b1120"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#8b96b1"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#0b1120"}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#2a3247"}]},
  {"featureType":"administrative.country","elementType":"labels.text.fill","stylers":[{"color":"#a4aecb"}]},
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#172033"}]},
  {"featureType":"road","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#05070f"}]}
]
''';
