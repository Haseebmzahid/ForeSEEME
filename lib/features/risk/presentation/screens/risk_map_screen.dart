import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:fyp_foreseeme/core/theme/a11y.dart';
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
import 'package:fyp_foreseeme/features/risk/domain/models/trend_direction.dart';
import 'package:fyp_foreseeme/features/risk/domain/services/risk_staleness.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/collapsible_risk_legend.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/location_comparison_card.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_map_chrome.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_map_style.dart';
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
///
/// **Sprint 6 visual pass.** The presentation is now the approved prototype
/// (`docs/Design/ForeSeeMe Risk Map.html`): an environmental instrument
/// surface — dark map bed, glass chrome, the RISK FIELD puck, a layered risk
/// field and a telemetry sheet. Data, providers, navigation and map behaviour
/// are unchanged; the prototype's district-level fiction is mapped onto the
/// app's real five-city geometry (see [_fieldCircles]).
class RiskMapScreen extends ConsumerStatefulWidget {
  const RiskMapScreen({super.key});

  @override
  ConsumerState<RiskMapScreen> createState() => _RiskMapScreenState();
}

class _RiskMapScreenState extends ConsumerState<RiskMapScreen> {
  String? _selectedCity;
  bool _comparisonDismissed = false;
  bool _searchOpen = false;

  /// Whether the layered risk field is drawn over the base map (the
  /// prototype's FIELD / BASE control).
  bool _fieldOn = true;

  GoogleMapController? _controller;

  /// Finished label-plate marker icons. Built lazily; until one resolves the
  /// city falls back to the hue marker, so the map is never waiting on bitmap
  /// generation to be usable.
  final Map<String, BitmapDescriptor> _labelIcons = {};

  /// Plates currently being rasterised, so a rebuild never queues one twice.
  final Set<String> _pendingIcons = {};

  /// Camera tilt applied when settling on a region — the prototype's tilted
  /// map bed. The national overview stays flat.
  static const double _regionTilt = 52;

  /// Resting height of the regional sheet, as a fraction of the screen. Chosen
  /// so the selected region's field, its label and the top chrome all stay
  /// visible; the user pulls the sheet up for the rest of the detail.
  static const double _sheetInitialExtent = 0.42;
  static const double _sheetMinExtent = 0.32;
  static const double _sheetMaxExtent = 0.90;

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
    setState(() {
      _selectedCity = city;
      _searchOpen = false;
    });
    final coord = kCityCoordinates[city];
    if (coord != null) {
      _controller?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(coord.lat, coord.lon),
            zoom: 8.5,
            tilt: _regionTilt,
          ),
        ),
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
    final t = RiskMapTheme.of(context);
    final selected = _resolveSelected(estimates);
    final stale =
        selected != null && isRiskStale(selected.generatedAt);

    _ensureLabelIcons(estimates);

    return Stack(
      children: [
        Positioned.fill(
          child: GoogleMap(
            initialCameraPosition: _initialCamera,
            onMapCreated: (controller) => _controller = controller,
            // The prototype's environmental bed, in both brightnesses. This is
            // Risk-Map-specific and deliberately not the shared kDarkMapStyle,
            // which the Nearby Hospitals map also uses.
            style: t.mapStyle,
            circles: _fieldCircles(estimates, selected),
            markers: _markersFor(estimates),
            // The Maps SDK owns its own permission prompt for the blue dot —
            // an honest "You are here" with no separate location plumbing.
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),
        ),

        // Edge vignette and the top horizon haze — the prototype's two
        // atmosphere layers that seat the chrome over the map.
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.76),
                  radius: 1.2,
                  colors: [Colors.transparent, t.vignette],
                  stops: const [0.4, 1.0],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 230,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [t.mapBg, t.horizonHaze, Colors.transparent],
                  stops: const [0.12, 0.62, 1.0],
                ),
              ),
            ),
          ),
        ),

        _TopChrome(
          estimates: estimates,
          selected: selected,
          stale: stale,
          searchOpen: _searchOpen,
          fieldOn: _fieldOn,
          comparisonDismissed: _comparisonDismissed,
          onBack: () => context.pop(),
          onToggleSearch: () => setState(() => _searchOpen = !_searchOpen),
          onToggleField: () => setState(() => _fieldOn = !_fieldOn),
          onRecenter: _recenter,
          onHistory: _openRecentActivity,
          onCompare: () => context.push('/compare'),
          onPickCity: _selectCity,
          onDismissComparison: () =>
              setState(() => _comparisonDismissed = true),
        ),

        // Legend rests just above the sheet's resting extent, so the map and
        // the legend both stay readable in the default selected state.
        Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: EdgeInsets.only(
              left: 14,
              bottom: selected == null
                  ? 12
                  : MediaQuery.sizeOf(context).height * _sheetInitialExtent + 12,
            ),
            child: const AppReveal(
              child: CollapsibleRiskLegend(initiallyExpanded: false),
            ),
          ),
        ),

        // The regional sheet is draggable: it rests at a little over a third
        // of the screen so the risk field stays visible, and pulls up to the
        // full detail. Everything above its child passes pointer events
        // straight through to the map.
        if (selected != null)
          DraggableScrollableSheet(
            initialChildSize: _sheetInitialExtent,
            minChildSize: _sheetMinExtent,
            maxChildSize: _sheetMaxExtent,
            snap: true,
            snapSizes: const [_sheetInitialExtent],
            builder: (context, scrollController) => CityDetailSheet(
              key: ValueKey(selected.city),
              estimate: selected,
              scrollController: scrollController,
            ),
          ),
      ],
    );
  }

  /// Returns the camera to the national overview — the prototype's recenter
  /// control, mapped onto this map's own "all five cities" home view.
  void _recenter() {
    setState(() => _selectedCity = null);
    _controller?.animateCamera(
      CameraUpdate.newCameraPosition(_initialCamera),
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

  /// The **layered risk field**: the prototype draws each region as a stack of
  /// shrinking translucent contours whose *count* encodes intensity (low 2,
  /// medium 4, high 6, uncertain 1), so severity survives greyscale.
  ///
  /// The prototype's bed is a fictional set of Lahore district polygons; this
  /// app maps five real cities and has no district geometry, so the same
  /// contour stack is drawn on the real city circles the map already used. The
  /// visual language is the prototype's; the geometry stays the app's own.
  Set<Circle> _fieldCircles(
    List<RiskEstimateModel> estimates,
    RiskEstimateModel? selected,
  ) {
    const baseRadius = 45000.0;
    final circles = <Circle>{};

    for (final e in estimates) {
      final coord = kCityCoordinates[e.city];
      if (coord == null) continue;
      final centre = LatLng(coord.lat, coord.lon);
      final style = RiskFieldStyle.of(
        e.riskLevel,
        lowConfidence: e.lowConfidence,
      );
      final isSelected = selected?.city == e.city;

      // Every layer of a city selects that city, so the tap target is exactly
      // the area it was before.
      void onTap() => _selectCity(e.city);

      // Atmospheric haze bed, just outside the field.
      circles.add(
        Circle(
          circleId: CircleId('${e.city}-haze'),
          center: centre,
          radius: baseRadius * 1.02,
          fillColor: style.color.withValues(
            alpha: !_fieldOn ? 0 : (style.isUnknown ? 0.02 : 0.05),
          ),
          strokeWidth: 0,
          zIndex: 0,
          consumeTapEvents: true,
          onTap: onTap,
        ),
      );

      final layers = _fieldOn ? style.layers : 1;
      for (var z = 0; z < layers; z++) {
        circles.add(
          Circle(
            circleId: CircleId('${e.city}-l$z'),
            center: centre,
            radius: baseRadius * style.shrinkFor(z),
            fillColor: style.color.withValues(
              alpha: _fieldOn
                  ? style.fillAlphaFor(z, selected: isSelected)
                  : 0.0,
            ),
            strokeColor: style.color.withValues(
              alpha: style.strokeAlphaFor(selected: isSelected),
            ),
            strokeWidth: isSelected && z == 0 ? 3 : 1,
            zIndex: 1 + z,
            consumeTapEvents: true,
            onTap: onTap,
          ),
        );
      }

      // Focus boundary on the selected region — the prototype's crisp inner
      // ring that lifts the selection above the rest of the field.
      if (isSelected) {
        circles.add(
          Circle(
            circleId: CircleId('${e.city}-focus'),
            center: centre,
            radius: baseRadius * 0.97,
            fillColor: Colors.transparent,
            strokeColor: style.color.withValues(
              alpha: style.isUnknown ? 0.8 : 0.95,
            ),
            strokeWidth: 2,
            zIndex: 20,
            consumeTapEvents: true,
            onTap: onTap,
          ),
        );
      }
    }
    return circles;
  }

  Set<Marker> _markersFor(List<RiskEstimateModel> estimates) {
    final markers = <Marker>{};
    for (final e in estimates) {
      final coord = kCityCoordinates[e.city];
      if (coord == null) continue;
      final a = RiskVisuals.of(e.riskLevel, lowConfidence: e.lowConfidence);
      final icon = _labelIcons[_iconKey(e)];
      markers.add(
        Marker(
          markerId: MarkerId(e.city),
          position: LatLng(coord.lat, coord.lon),
          // The prototype labels regions with a flat plate rather than a pin.
          // Until the plate is rasterised the hue marker stands in, so the map
          // is never blank while bitmaps generate.
          icon: icon ?? BitmapDescriptor.defaultMarkerWithHue(riskMarkerHue(a)),
          anchor: icon != null ? const Offset(0.5, 1.15) : const Offset(0.5, 1),
          infoWindow: InfoWindow(title: e.city, snippet: '${a.label} risk'),
          onTap: () => _selectCity(e.city),
        ),
      );
    }
    return markers;
  }

  /// Identity of a rendered plate — regenerated only when something it draws
  /// actually changes.
  String _iconKey(RiskEstimateModel e) =>
      '${e.city}|${e.riskLevel.name}|${e.lowConfidence}';

  /// Rasterises the prototype's region label plates, one per city, and caches
  /// them by [_iconKey]. Failures are swallowed — the marker simply keeps its
  /// hue fallback, so bitmap generation can never break the map.
  void _ensureLabelIcons(List<RiskEstimateModel> estimates) {
    final theme = RiskMapTheme.of(context);
    final ratio = MediaQuery.devicePixelRatioOf(context);

    for (final e in estimates) {
      final key = _iconKey(e);
      // `_pendingIcons` reserves the slot so a rebuild never queues the same
      // plate twice; `_labelIcons` only ever holds a finished plate.
      if (_labelIcons.containsKey(key) || !_pendingIcons.add(key)) continue;
      unawaited(_buildLabelIcon(key, e, theme, ratio));
    }
  }

  Future<void> _buildLabelIcon(
    String key,
    RiskEstimateModel estimate,
    RiskMapTheme theme,
    double ratio,
  ) async {
    BitmapDescriptor? icon;
    try {
      icon = await _renderLabelPlate(
        city: estimate.city,
        style: RiskFieldStyle.of(
          estimate.riskLevel,
          lowConfidence: estimate.lowConfidence,
        ),
        theme: theme,
        ratio: ratio,
      );
    } catch (_) {
      icon = null;
    }
    if (!mounted || icon == null) return;
    setState(() => _labelIcons[key] = icon!);
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

// ── Floating chrome ──────────────────────────────────────────────────────────

/// Everything that floats over the map: the region bar, the data-condition
/// banner, the Location Intelligence card, the RISK FIELD puck and the control
/// stack. Pure layout over callbacks the screen owns.
class _TopChrome extends StatelessWidget {
  const _TopChrome({
    required this.estimates,
    required this.selected,
    required this.stale,
    required this.searchOpen,
    required this.fieldOn,
    required this.comparisonDismissed,
    required this.onBack,
    required this.onToggleSearch,
    required this.onToggleField,
    required this.onRecenter,
    required this.onHistory,
    required this.onCompare,
    required this.onPickCity,
    required this.onDismissComparison,
  });

  final List<RiskEstimateModel> estimates;
  final RiskEstimateModel? selected;
  final bool stale;
  final bool searchOpen;
  final bool fieldOn;
  final bool comparisonDismissed;
  final VoidCallback onBack;
  final VoidCallback onToggleSearch;
  final VoidCallback onToggleField;
  final VoidCallback onRecenter;
  final VoidCallback onHistory;
  final VoidCallback onCompare;
  final ValueChanged<String> onPickCity;
  final VoidCallback onDismissComparison;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                MapIconButton(
                  semanticLabel: 'Back',
                  icon: Icons.arrow_back_rounded,
                  onPressed: onBack,
                  radius: 14,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: MapRegionBar(
                    regionName: selected == null
                        ? 'Pakistan · national view'
                        : selected!.city,
                    searchOpen: searchOpen,
                    onSearch: onToggleSearch,
                  ),
                ),
              ],
            ),

            if (searchOpen) ...[
              const SizedBox(height: 10),
              _RegionPicker(
                estimates: estimates,
                selectedCity: selected?.city,
                onPick: onPickCity,
              ),
            ],

            // The prototype's data-condition banner. The app's offline and
            // service-error conditions are already whole-screen states, so the
            // banner carries the one condition that coexists with a usable
            // map: an estimate that is out of date.
            if (!searchOpen && stale) ...[
              const SizedBox(height: 12),
              const MapBanner(
                text:
                    'This regional estimate has not refreshed on schedule. '
                    'Showing the last values received.',
                color: Color(0xFFE3A63F),
              ),
            ],

            if (!searchOpen && !comparisonDismissed) ...[
              const SizedBox(height: 12),
              _LocationComparisonSlot(onDismiss: onDismissComparison),
            ],

            if (!searchOpen) ...[
              const SizedBox(height: 12),
              // Two short rails rather than one tall stack: the regional sheet
              // is drawn above this chrome, so a single column of six controls
              // would put the last of them behind the sheet and out of reach.
              // The map controls keep the prototype's right-hand position; the
              // screen's two navigation actions sit opposite them.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MapIconButton(
                        semanticLabel: 'Recent activity',
                        icon: Icons.history_rounded,
                        onPressed: onHistory,
                      ),
                      const SizedBox(height: 8),
                      MapIconButton(
                        semanticLabel: 'Compare cities and diseases',
                        icon: Icons.bar_chart_rounded,
                        onPressed: onCompare,
                      ),
                    ],
                  ),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (selected != null)
                        _RiskFieldPuckSlot(estimate: selected!, stale: stale),
                      const SizedBox(height: 10),
                      MapIconButton(
                        semanticLabel: 'Return to the national view',
                        icon: Icons.my_location_rounded,
                        onPressed: onRecenter,
                      ),
                      const SizedBox(height: 8),
                      MapIconButton(
                        semanticLabel: fieldOn
                            ? 'Hide the risk field layer'
                            : 'Show the risk field layer',
                        label: fieldOn ? 'FIELD' : 'BASE',
                        active: fieldOn,
                        onPressed: onToggleField,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The region list behind the region bar's control — the prototype's search
/// panel, listing exactly the cities the model actually covers this week.
class _RegionPicker extends StatelessWidget {
  const _RegionPicker({
    required this.estimates,
    required this.selectedCity,
    required this.onPick,
  });

  final List<RiskEstimateModel> estimates;
  final String? selectedCity;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final t = RiskMapTheme.of(context);
    final sorted = [...estimates]..sort((a, b) => a.city.compareTo(b.city));

    return AppReveal(
      child: MapGlassPanel(
        radius: 14,
        blur: 18,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Text(
                'REGIONS IN MODEL COVERAGE',
                style: mapMono(context, size: 9, em: 0.16, color: t.ink2),
              ),
            ),
            for (final e in sorted)
              _RegionRow(
                estimate: e,
                selected: e.city == selectedCity,
                onTap: () => onPick(e.city),
              ),
          ],
        ),
      ),
    );
  }
}

class _RegionRow extends StatelessWidget {
  const _RegionRow({
    required this.estimate,
    required this.selected,
    required this.onTap,
  });

  final RiskEstimateModel estimate;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = RiskMapTheme.of(context);
    final style = RiskFieldStyle.of(
      estimate.riskLevel,
      lowConfidence: estimate.lowConfidence,
    );
    final appearance = RiskVisuals.of(
      estimate.riskLevel,
      lowConfidence: estimate.lowConfidence,
    );

    return Semantics(
      button: true,
      selected: selected,
      label: '${estimate.city}, ${appearance.label} risk',
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: selected
              ? style.color.withValues(alpha: 0.10)
              : Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: t.hair)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: style.color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      estimate.city,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.fsmText.bodyMedium?.copyWith(
                        fontSize: 13,
                        color: t.ink,
                      ),
                    ),
                  ),
                  Text(
                    style.label,
                    style: mapMono(context, size: 10, em: 0.1, color: t.ink2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Feeds the RISK FIELD puck from the selected city's own signals — its level
/// and confidence from the estimate, its trend from the same
/// [areaInsightProvider] the sheet below already uses.
class _RiskFieldPuckSlot extends ConsumerWidget {
  const _RiskFieldPuckSlot({required this.estimate, required this.stale});

  final RiskEstimateModel estimate;
  final bool stale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = RiskMapTheme.of(context);
    final appearance = RiskVisuals.of(
      estimate.riskLevel,
      lowConfidence: estimate.lowConfidence,
    );
    final trend = ref.watch(areaInsightProvider(estimate.city)).asData?.value
        ?.trend;

    return AppReveal(
      child: RiskFieldPuck(
        style: RiskFieldStyle.of(
          estimate.riskLevel,
          lowConfidence: estimate.lowConfidence,
        ),
        levelLabel: appearance.label,
        trendLabel: 'TREND · ${_trendWord(trend)}',
        confidenceLabel: 'CONF ${estimate.confidence.toStringAsFixed(2)}',
        freshnessLabel: stale
            ? 'STALE · ${riskAgeLabel(estimate.generatedAt).toUpperCase()}'
            : 'UPDATED ${riskAgeLabel(estimate.generatedAt).toUpperCase()}',
        freshnessColor: stale ? const Color(0xFFE3A63F) : t.ink2,
      ),
    );
  }

  /// Uses the same vocabulary as the shared `TrendBadge`, so the puck and the
  /// sheet can never disagree, and says N/A rather than guessing a direction.
  static String _trendWord(TrendDirection? d) => switch (d) {
    TrendDirection.rising => 'RISING',
    TrendDirection.stable => 'STABLE',
    TrendDirection.falling => 'FALLING',
    TrendDirection.insufficient => 'INSUFFICIENT',
    null => 'N/A',
  };
}

/// Draws the prototype's on-map region label — a dark plate carrying a risk
/// swatch, the city name and the level — and returns it as a marker icon.
Future<BitmapDescriptor?> _renderLabelPlate({
  required String city,
  required RiskFieldStyle style,
  required RiskMapTheme theme,
  required double ratio,
}) async {
  const padH = 11.0;
  const padV = 7.0;
  const dot = 6.0;
  const gap = 7.0;
  const radius = 9.0;

  final name = TextPainter(
    text: TextSpan(
      text: city,
      style: TextStyle(
        color: theme.ink,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.07,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  final level = TextPainter(
    text: TextSpan(
      text: style.label,
      style: TextStyle(
        color: theme.ink,
        fontSize: 9,
        letterSpacing: 1.08,
        fontFeatures: const [ui.FontFeature.tabularFigures()],
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  final w = padH * 2 + dot + gap + name.width + gap + level.width;
  final h = padV * 2 + math.max(name.height, level.height);

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(ratio);

  final rect = RRect.fromRectAndRadius(
    Rect.fromLTWH(0, 0, w, h),
    const Radius.circular(radius),
  );
  canvas.drawRRect(rect, Paint()..color = theme.labelPlate);
  canvas.drawRRect(
    rect,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = style.color.withValues(alpha: 0.55),
  );

  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(padH, (h - dot) / 2, dot, dot),
      const Radius.circular(2),
    ),
    Paint()..color = style.color,
  );

  name.paint(canvas, Offset(padH + dot + gap, (h - name.height) / 2));
  level.paint(
    canvas,
    Offset(padH + dot + gap + name.width + gap, (h - level.height) / 2),
  );

  final image = await recorder.endRecording().toImage(
    (w * ratio).ceil(),
    (h * ratio).ceil(),
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (bytes == null) return null;
  return BitmapDescriptor.bytes(
    bytes.buffer.asUint8List(),
    imagePixelRatio: ratio,
  );
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
      // The reveal lives here, not at the call site: the card is gated
      // behind this async read, so an outer AppReveal would finish its
      // clock while the slot was still an invisible SizedBox and the card
      // would just snap in once the data arrived.
      data: (comparison) => comparison == null
          ? const SizedBox.shrink()
          : AppReveal(
              child: LocationComparisonCard(
                comparison: comparison,
                onDismiss: onDismiss,
              ),
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
///
/// Sprint 6 visual pass: presented as the prototype's regional sheet — a
/// rounded glass panel with a full-bleed telemetry strip and the WHY THIS RISK
/// section. Every element it carried before is still here; only the surface,
/// type and rhythm changed.
class CityDetailSheet extends ConsumerWidget {
  final RiskEstimateModel estimate;

  /// Supplied by [DraggableScrollableSheet]. Driving the sheet's scroll view
  /// with it is what makes the surface draggable: a pull moves the sheet until
  /// it is fully open, then keeps scrolling the content. When null the sheet
  /// simply sizes to its content (how it is pumped directly in tests).
  final ScrollController? scrollController;

  const CityDetailSheet({
    super.key,
    required this.estimate,
    this.scrollController,
  });

  /// The sheet's horizontal padding — shared with the telemetry strip, which
  /// cancels it out to run edge to edge.
  static const double _padH = 20;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = RiskMapTheme.of(context);
    final text = context.fsmText;
    final a = RiskVisuals.resolve(
      context,
      estimate.riskLevel,
      lowConfidence: estimate.lowConfidence,
    );
    final style = RiskFieldStyle.of(
      estimate.riskLevel,
      lowConfidence: estimate.lowConfidence,
    );
    final isOwnCity = ref.watch(userCityProvider).value == estimate.city;
    final insightAsync = ref.watch(areaInsightProvider(estimate.city));

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: A11y.blurSigma(context, sigma: 22),
          sigmaY: A11y.blurSigma(context, sigma: 22),
        ),
        child: Container(
          width: double.infinity,
          // Horizontal padding is applied per section rather than to the whole
          // sheet, so the telemetry strip can run edge to edge as it does in
          // the prototype.
          padding: const EdgeInsets.only(top: 10, bottom: 26),
          decoration: BoxDecoration(
            color: A11y.reduceTransparency(context)
                ? Color.alphaBlend(t.sheet, t.mapBg)
                : t.sheet,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            border: Border(top: BorderSide(color: t.hair)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.42),
                blurRadius: 60,
                offset: const Offset(0, -22),
              ),
            ],
          ),
          child: _SheetBody(
            controller: scrollController,
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: t.hair,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: _padH),
                child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SELECTED REGION',
                          style: mapMono(
                            context,
                            size: 9,
                            em: 0.16,
                            color: t.ink2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          estimate.city,
                          style: text.titleLarge?.copyWith(
                            fontSize: 21,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.315,
                            color: t.ink,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          estimate.disease,
                          style: mapMono(context, size: 10, color: t.ink2),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Updated ${riskAgeLabel(estimate.generatedAt)} · '
                          'confidence ${estimate.confidence.toStringAsFixed(2)}',
                          style: mapMono(context, size: 9.5, color: t.ink2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Risk chip — the prototype's geometry, but keeping the
                  // distinct RiskVisuals icon so the level never depends on
                  // colour alone.
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: style.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                        color: style.color.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(a.icon, size: 14, color: a.color),
                        const SizedBox(width: 8),
                        Text(
                          a.label,
                          style: mapMono(
                            context,
                            size: 11,
                            em: 0.12,
                            color: a.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                ),
              ),
              const SizedBox(height: 15),
              Container(
                height: 1,
                color: t.hair,
                margin: const EdgeInsets.symmetric(horizontal: _padH),
              ),

              // Full-bleed telemetry — only the readings the estimate stores.
              MapTelemetryGrid(
                cells: [
                  MapTelemetryCell(
                    label: 'AQI',
                    value: estimate.aqi.round().toString(),
                    unit: 'US index',
                  ),
                  MapTelemetryCell(
                    label: 'TEMP',
                    value: estimate.temperature.toStringAsFixed(1),
                    unit: '°C',
                  ),
                  MapTelemetryCell(
                    label: 'HUMIDITY',
                    value: estimate.humidity.round().toString(),
                    unit: '%',
                  ),
                ],
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: _padH),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 16),
                    Text(
                      'WHY THIS RISK',
                      style: mapMono(
                        context,
                        size: 9,
                        em: 0.16,
                        color: t.ink2,
                      ),
                    ),
                    const SizedBox(height: 9),
                    MapWhyBars(
                      drivers: _driversFor(estimate),
                      color: style.color,
                    ),
                    const SizedBox(height: 9),
                    Text(
                      'Values from the regional environmental feed · '
                      'no causal inference is claimed.',
                      style: mapMono(context, size: 9, em: 0.06, color: t.ink2)
                          .copyWith(height: 1.5),
                    ),

                    // Honest staleness label for this city's estimate
                    // (self-guarding — shows only when the cached/last
                    // estimate is out of date).
                    RiskStalenessNotice(
                      generatedAt: estimate.generatedAt,
                      topGap: 14,
                    ),
                    // Area Insight — degrades to nothing while
                    // loading/erroring, so the sheet above never depends on
                    // this section resolving.
                    insightAsync.maybeWhen(
                      data: (view) => view == null
                          ? const SizedBox.shrink()
                          : _AreaInsightExtras(view: view),
                      orElse: () => const SizedBox.shrink(),
                    ),
                    // "View details" only for the user's own profile city: the
                    // full Risk Details screen reads `currentCityRiskProvider`
                    // (the user's city), not an arbitrary tapped city, so the
                    // CTA never claims to open detail for a city it can't
                    // actually show.
                    if (isOwnCity) ...[
                      const SizedBox(height: 14),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => context.push('/risk-details'),
                          style: TextButton.styleFrom(
                            foregroundColor: RiskMapTheme.accent,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            minimumSize: const Size(0, 48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(11),
                              side: BorderSide(
                                color: RiskMapTheme.accent.withValues(
                                  alpha: 0.45,
                                ),
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
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }
}

/// Hosts the sheet's content.
///
/// With a [controller] (the draggable sheet's) the content lives in a scroll
/// view that always accepts a drag — `AlwaysScrollableScrollPhysics` matters
/// here, because at the resting extent the content is taller than the sheet but
/// at full extent it may not be, and without it the sheet would stop responding
/// to a pull once the content fits. Without a controller it lays out at its
/// natural height, unchanged.
class _SheetBody extends StatelessWidget {
  const _SheetBody({required this.child, this.controller});

  final Widget child;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    if (controller == null) return child;
    return SingleChildScrollView(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(),
      child: child,
    );
  }
}

/// Normalised driver values for the WHY THIS RISK strip, using the prototype's
/// own ramp over the estimate's stored readings. Purely a restatement of the
/// numbers shown directly above it.
List<double> _driversFor(RiskEstimateModel e) => [
  (e.aqi / 200).clamp(0.0, 1.0),
  ((e.temperature - 24) / 16).clamp(0.0, 1.0),
  (e.humidity / 100).clamp(0.0, 1.0),
];

/// The Area Insight body: primary contributor, recent trend, and a cited
/// recommendation — genuine signals for the TAPPED city (Geospatial
/// Intelligence sprint), sourced from [areaInsightProvider].
class _AreaInsightExtras extends StatelessWidget {
  const _AreaInsightExtras({required this.view});

  final AreaInsightView view;

  @override
  Widget build(BuildContext context) {
    final t = RiskMapTheme.of(context);
    final text = context.fsmText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Container(height: 1, color: t.hair),
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
                    style: mapMono(context, size: 9, em: 0.16, color: t.ink2),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    view.primaryDriver?.label ?? 'Not available',
                    style: text.bodyMedium?.copyWith(
                      fontSize: 12.5,
                      color: t.ink,
                      fontWeight: FontWeight.w600,
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
                  style: mapMono(context, size: 9, em: 0.16, color: t.ink2),
                ),
                const SizedBox(height: 5),
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
    final t = RiskMapTheme.of(context);
    final text = context.fsmText;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.sheetCell,
        borderRadius: BorderRadius.circular(ForeSeeMeRadius.sm),
        border: Border.all(color: t.hair),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            recommendation.text,
            style: text.bodyMedium?.copyWith(
              fontSize: 12.5,
              height: 1.5,
              color: t.ink,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.verified_outlined, size: 13, color: t.ink2),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Source: ${recommendation.source}',
                  style: mapMono(context, size: 9, em: 0.06, color: t.ink2),
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
        foregroundColor: RiskMapTheme.accent,
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
