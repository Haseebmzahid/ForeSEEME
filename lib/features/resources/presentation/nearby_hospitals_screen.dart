import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/core/widgets/brand_loading.dart';
import 'package:fyp_foreseeme/core/widgets/empty_state.dart';
import 'package:fyp_foreseeme/core/widgets/error_state.dart';
import 'package:fyp_foreseeme/core/widgets/offline_state.dart';
import 'package:fyp_foreseeme/features/resources/domain/exceptions/places_exception.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/hospital.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/nearby_hospitals_result.dart';
import 'package:fyp_foreseeme/features/resources/presentation/nearby_hospitals_providers.dart';
import 'package:fyp_foreseeme/features/resources/presentation/services/hospital_actions.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/hospital_detail_sheet.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/hospital_list.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';

/// Nearby hospitals — a live Google Places lookup centred on the user's device
/// location (or, on their choice after a denial, their profile city). Every
/// visible state maps to a real runtime condition: loading, permission denied,
/// no results, network error, API error, or a successful list — searchable and
/// filterable **over the real fetched set** (no new API calls, nothing invented).
class NearbyHospitalsScreen extends ConsumerStatefulWidget {
  const NearbyHospitalsScreen({super.key});

  @override
  ConsumerState<NearbyHospitalsScreen> createState() =>
      _NearbyHospitalsScreenState();
}

class _NearbyHospitalsScreenState extends ConsumerState<NearbyHospitalsScreen> {
  // Owned here (not recreated per build) so typing keeps focus/cursor
  // position; the listener re-renders on every keystroke via setState.
  final TextEditingController _searchController = TextEditingController();
  bool _openNowOnly = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() => setState(() {});

  void _clearFilters() {
    _searchController.clear();
    setState(() => _openNowOnly = false);
  }

  List<Hospital> _visible(List<Hospital> all) {
    final q = _searchController.text.trim().toLowerCase();
    return [
      for (final h in all)
        if ((q.isEmpty ||
                h.name.toLowerCase().contains(q) ||
                h.address.toLowerCase().contains(q)) &&
            (!_openNowOnly || h.openNow == true))
          h,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final async = ref.watch(nearbyHospitalsProvider);
    final isHigh =
        ref.watch(currentCityRiskProvider).value?.riskLevel == RiskLevel.high;

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        foregroundColor: palette.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => context.pop(),
        ),
        title: Text('Nearby Hospitals', style: context.fsmText.titleLarge),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: async.isLoading ? null : () => _refresh(ref),
          ),
        ],
      ),
      body: SafeArea(
        child: AppMotion.stateSwitcher(
          context,
          async.when(
            loading: () => const _Centered(
              spinner: true,
              icon: Icons.local_hospital_outlined,
              title: 'Finding nearby hospitals…',
              message:
                  'Getting your location and searching facilities near you.',
            ),
            error: (error, _) => _errorView(context, ref, error),
            data: (result) => _dataView(context, ref, result, isHigh),
          ),
        ),
      ),
    );
  }

  // ── Data / empty ─────────────────────────────────────────────────────────--

  Widget _dataView(
    BuildContext context,
    WidgetRef ref,
    NearbyHospitalsResult result,
    bool isHigh,
  ) {
    if (result.hospitals.isEmpty) {
      return _RefreshWrap(
        onRefresh: () => _refresh(ref),
        child: const EmptyState(
          icon: Icons.search_off_rounded,
          title: 'No hospitals found nearby',
          description:
              'We could not find facilities within range. Pull down to refresh '
              'or move to a different area.',
        ),
      );
    }

    final visible = _visible(result.hospitals);
    final anyOpenNowData = result.hospitals.any((h) => h.openNow != null);

    return RefreshIndicator(
      color: context.fsmPalette.primary,
      backgroundColor: context.fsmPalette.surfaceContainerHigh,
      onRefresh: () => _refresh(ref),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          if (isHigh) ...[const _HighRiskBanner(), const SizedBox(height: 16)],
          _SearchField(controller: _searchController),
          if (anyOpenNowData) ...[
            const SizedBox(height: 10),
            _OpenNowFilterChip(
              selected: _openNowOnly,
              onSelected: (v) => setState(() => _openNowOnly = v),
            ),
          ],
          const SizedBox(height: 16),
          if (visible.isEmpty)
            _FilteredEmptyState(onClear: _clearFilters)
          else ...[
            _ViewOnMapButton(onTap: () => _openMap(context, visible)),
            const SizedBox(height: 16),
            HospitalList(
              hospitals: visible,
              onTap: (h) => _openDetail(context, ref, h),
              onCall: (h) => callHospital(context, ref, h),
              onDirections: (h) => openHospitalDirections(ref, h),
            ),
          ],
          const SizedBox(height: 8),
          Center(
            child: Text(
              '${_freshnessLabel(result)} · Google Places',
              style: context.fsmText.bodySmall?.copyWith(
                color: context.fsmPalette.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Errors → real runtime states ──────────────────────────────────────────--

  Widget _errorView(BuildContext context, WidgetRef ref, Object error) {
    if (error is LocationPermissionDeniedException) {
      return _RefreshWrap(
        onRefresh: () => _refresh(ref),
        child: _PermissionDeniedView(
          servicesDisabled: error.servicesDisabled,
          fallbackCity: error.hasCityFallback ? error.fallbackCity : null,
          onEnableLocation: () =>
              _enableLocation(ref, servicesDisabled: error.servicesDisabled),
          onSearchNearCity: () => _searchNearCity(ref),
          onRetry: () => _retry(ref),
        ),
      );
    }

    if (error is LocationUnavailableException) {
      return _RefreshWrap(
        onRefresh: () => _refresh(ref),
        child: _Centered(
          icon: Icons.location_off_rounded,
          title: 'Location needed',
          message:
              'Enable location, or set your city in your profile, to find '
              'nearby hospitals.',
          onRetry: () => _retry(ref),
          retryLabel: 'Try again',
        ),
      );
    }

    if (error is PlacesNetworkException) {
      // Genuine connectivity loss → the shared offline surface.
      return _RefreshWrap(
        onRefresh: () => _refresh(ref),
        child: OfflineState(onRetry: () => _retry(ref)),
      );
    }

    // PlacesRequestException / PlacesQuotaExceededException / anything else →
    // a service-side error (never a "not configured" placeholder).
    final quota = error is PlacesQuotaExceededException;
    return _RefreshWrap(
      onRefresh: () => _refresh(ref),
      child: ErrorState(
        icon: Icons.cloud_off_rounded,
        title: quota ? 'Search limit reached' : "Couldn't load hospitals",
        explanation: quota
            ? 'You have reached the lookup limit for now. Please try again '
                  'later.'
            : 'The hospital service is temporarily unavailable. Please try '
                  'again.',
        onRetry: () => _retry(ref),
        detail: '$error',
      ),
    );
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(nearbyHospitalsProvider);
    try {
      await ref.read(nearbyHospitalsProvider.future);
    } catch (_) {
      // The error is rendered by the `when` builder; swallow here so the
      // RefreshIndicator spinner completes.
    }
  }

  void _retry(WidgetRef ref) {
    ref.read(cityFallbackRequestedProvider.notifier).reset();
    ref.invalidate(nearbyHospitalsProvider);
  }

  void _searchNearCity(WidgetRef ref) {
    ref.read(cityFallbackRequestedProvider.notifier).useCity();
    ref.invalidate(nearbyHospitalsProvider);
  }

  Future<void> _enableLocation(
    WidgetRef ref, {
    required bool servicesDisabled,
  }) async {
    final service = ref.read(locationServiceProvider);
    if (servicesDisabled) {
      await service.openLocationServiceSettings();
    } else {
      await service.openAppSettings();
    }
    _retry(ref);
  }

  void _openMap(BuildContext context, List<Hospital> hospitals) {
    context.push('/nearby-hospitals/map', extra: hospitals);
  }

  void _openDetail(BuildContext context, WidgetRef ref, Hospital hospital) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => HospitalDetailSheet(
        hospital: hospital,
        onCall: () => callHospital(context, ref, hospital),
        onDirections: () => openHospitalDirections(ref, hospital),
      ),
    );
  }

  String _freshnessLabel(NearbyHospitalsResult result) {
    if (!result.servedFromCache) return 'Updated just now';
    final mins = DateTime.now().difference(result.fetchedAt).inMinutes;
    if (mins <= 0) return 'Cached just now';
    return 'Cached $mins min ago';
  }
}

// ── Search + filter ───────────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  const _SearchField({required this.controller});

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    return Semantics(
      textField: true,
      label: 'Search hospitals by name or address',
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: ForeSeeMeSurface.card(context, radius: ForeSeeMeRadius.sm),
        child: Row(
          children: [
            Icon(Icons.search_rounded, size: 20, color: palette.textTertiary),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                style: context.fsmText.bodyMedium?.copyWith(
                  color: palette.textPrimary,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Search hospitals…',
                  hintStyle: context.fsmText.bodyMedium?.copyWith(
                    color: palette.textTertiary,
                  ),
                ),
              ),
            ),
            if (controller.text.isNotEmpty)
              Semantics(
                button: true,
                label: 'Clear search',
                child: InkWell(
                  onTap: controller.clear,
                  borderRadius: BorderRadius.circular(ForeSeeMeRadius.full),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: palette.textTertiary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _OpenNowFilterChip extends StatelessWidget {
  final bool selected;
  final ValueChanged<bool> onSelected;
  const _OpenNowFilterChip({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final accent = context.fsmColors.success;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Filter: open now',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onSelected(!selected),
          borderRadius: BorderRadius.circular(ForeSeeMeRadius.full),
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? accent.withValues(alpha: 0.16) : Colors.transparent,
              borderRadius: BorderRadius.circular(ForeSeeMeRadius.full),
              border: Border.all(
                color: selected ? accent.withValues(alpha: 0.5) : palette.outlineVariant,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected ? Icons.check_circle_rounded : Icons.schedule_rounded,
                  size: 15,
                  color: selected ? accent : palette.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Open now',
                  style: context.fsmText.labelMedium?.copyWith(
                    color: selected ? accent : palette.textSecondary,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
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

class _FilteredEmptyState extends StatelessWidget {
  final VoidCallback onClear;
  const _FilteredEmptyState({required this.onClear});

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          Icon(Icons.filter_alt_off_outlined, size: 40, color: palette.textTertiary),
          const SizedBox(height: 12),
          Text(
            'No hospitals match your search',
            style: context.fsmText.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'Try a different name, or clear your filters.',
            style: context.fsmText.bodyMedium?.copyWith(
              color: palette.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          TextButton(
            onPressed: onClear,
            style: TextButton.styleFrom(foregroundColor: palette.primary),
            child: const Text('Clear filters'),
          ),
        ],
      ),
    );
  }
}

// ── View-on-map affordance ────────────────────────────────────────────────────

class _ViewOnMapButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ViewOnMapButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = context.fsmPalette.secondary;
    return Semantics(
      button: true,
      label: 'View on map',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(ForeSeeMeRadius.sm),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(ForeSeeMeRadius.sm),
              border: Border.all(color: accent.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.map_outlined, size: 18, color: accent),
                const SizedBox(width: 10),
                Text(
                  'View on map',
                  style: context.fsmText.bodyMedium?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Icon(Icons.chevron_right_rounded, size: 20, color: accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Permission-denied state ───────────────────────────────────────────────────

class _PermissionDeniedView extends StatelessWidget {
  final bool servicesDisabled;
  final String? fallbackCity;
  final VoidCallback onEnableLocation;
  final VoidCallback onSearchNearCity;
  final VoidCallback onRetry;

  const _PermissionDeniedView({
    required this.servicesDisabled,
    required this.fallbackCity,
    required this.onEnableLocation,
    required this.onSearchNearCity,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Icon(
                Icons.location_disabled_rounded,
                size: 56,
                color: palette.textTertiary,
              ),
            ),
            const SizedBox(height: 18),
            Semantics(
              header: true,
              child: Text(
                servicesDisabled
                    ? 'Location is turned off'
                    : 'Location permission needed',
                style: context.fsmText.titleLarge,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              servicesDisabled
                  ? 'Turn on location services so we can find hospitals near '
                        'you.'
                  : 'Allow location access so we can find hospitals near you.',
              style: context.fsmText.bodyMedium?.copyWith(
                color: palette.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 22),
            _PrimaryAction(
              icon: Icons.my_location_rounded,
              label: servicesDisabled
                  ? 'Open location settings'
                  : 'Enable location',
              onTap: onEnableLocation,
            ),
            if (fallbackCity != null) ...[
              const SizedBox(height: 12),
              _SecondaryAction(
                icon: Icons.location_city_rounded,
                label: 'Search near $fallbackCity instead',
                onTap: onSearchNearCity,
              ),
            ],
            const SizedBox(height: 8),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(foregroundColor: palette.primary),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _PrimaryAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(ForeSeeMeRadius.sm),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
            decoration: BoxDecoration(
              gradient: context.fsmColors.gradients.brand,
              borderRadius: BorderRadius.circular(ForeSeeMeRadius.sm),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: palette.onPrimary),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: context.fsmText.bodyMedium?.copyWith(
                    color: palette.onPrimary,
                    fontWeight: FontWeight.w700,
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

class _SecondaryAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SecondaryAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(ForeSeeMeRadius.sm),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: palette.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(ForeSeeMeRadius.sm),
              border: Border.all(color: palette.outlineVariant),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 17, color: palette.textPrimary),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    style: context.fsmText.bodySmall?.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
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

/// Makes a non-scrolling state pull-to-refreshable.
class _RefreshWrap extends StatelessWidget {
  final Future<void> Function() onRefresh;
  final Widget child;
  const _RefreshWrap({required this.onRefresh, required this.child});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: context.fsmPalette.primary,
      backgroundColor: context.fsmPalette.surfaceContainerHigh,
      onRefresh: onRefresh,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _HighRiskBanner extends StatelessWidget {
  const _HighRiskBanner();

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final urgent = palette.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: urgent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(ForeSeeMeRadius.md),
        border: Border.all(color: urgent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: urgent),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: context.fsmText.bodySmall?.copyWith(
                  color: palette.textPrimary,
                ),
                children: const [
                  TextSpan(text: 'Surfaced because risk is '),
                  TextSpan(
                    text: 'High',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  TextSpan(text: ' in your area'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final bool spinner;
  final VoidCallback? onRetry;
  final String retryLabel;

  const _Centered({
    required this.icon,
    required this.title,
    required this.message,
    this.spinner = false,
    this.onRetry,
    this.retryLabel = 'Retry',
  });

  @override
  Widget build(BuildContext context) {
    // Full-screen wait → the unified branded loader (never a bare spinner).
    if (spinner) return BrandLoading(message: title);

    final palette = context.fsmPalette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Icon(icon, size: 56, color: palette.textTertiary),
            ),
            const SizedBox(height: 18),
            Semantics(
              header: true,
              child: Text(
                title,
                style: context.fsmText.titleLarge,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: context.fsmText.bodyMedium?.copyWith(
                color: palette.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 18),
              TextButton.icon(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: palette.primary,
                  side: BorderSide(
                    color: palette.primary.withValues(alpha: 0.4),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ForeSeeMeRadius.xs),
                  ),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: Text(retryLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
