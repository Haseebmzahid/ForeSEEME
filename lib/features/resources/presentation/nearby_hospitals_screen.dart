import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
import 'package:fyp_foreseeme/features/resources/presentation/resources_providers.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/hospital_list.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/hospitals_map_screen.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';

/// Nearby hospitals — a live Google Places lookup centred on the user's device
/// location (or, on their choice after a denial, their profile city). Every
/// visible state maps to a real runtime condition: loading, permission denied,
/// no results, network error, API error, or a successful list.
class NearbyHospitalsScreen extends ConsumerWidget {
  const NearbyHospitalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    return RefreshIndicator(
      color: context.fsmPalette.primary,
      backgroundColor: context.fsmPalette.surfaceContainerHigh,
      onRefresh: () => _refresh(ref),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          if (isHigh) ...[const _HighRiskBanner(), const SizedBox(height: 16)],
          _ViewOnMapButton(
            onTap: () => _openMap(context, ref, result.hospitals),
          ),
          const SizedBox(height: 16),
          HospitalList(
            hospitals: result.hospitals,
            onCall: (h) => _call(context, ref, h),
            onDirections: (h) => _directions(ref, h),
          ),
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

  void _openMap(BuildContext context, WidgetRef ref, List<Hospital> hospitals) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => HospitalsMapScreen(
          hospitals: hospitals,
          onDirections: (h) => _directions(ref, h),
        ),
      ),
    );
  }

  Future<void> _call(BuildContext context, WidgetRef ref, Hospital h) async {
    final phone = h.phoneNumber;
    if (phone == null) return;
    final ok = await ref.read(launcherServiceProvider).dialPhone(phone);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the dialer.')),
      );
    }
  }

  void _directions(WidgetRef ref, Hospital h) {
    final url =
        'https://www.google.com/maps/dir/?api=1&destination='
        '${h.latitude},${h.longitude}';
    ref.read(launcherServiceProvider).openExternalUrl(url);
  }

  String _freshnessLabel(NearbyHospitalsResult result) {
    if (!result.servedFromCache) return 'Updated just now';
    final mins = DateTime.now().difference(result.fetchedAt).inMinutes;
    if (mins <= 0) return 'Cached just now';
    return 'Cached $mins min ago';
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
