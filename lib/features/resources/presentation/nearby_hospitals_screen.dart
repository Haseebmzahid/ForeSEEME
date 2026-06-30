import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/app_design_v2.dart';
import 'package:fyp_foreseeme/features/resources/domain/exceptions/places_exception.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/hospital.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/nearby_hospitals_result.dart';
import 'package:fyp_foreseeme/features/resources/presentation/nearby_hospitals_providers.dart';
import 'package:fyp_foreseeme/features/resources/presentation/resources_providers.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/hospital_list.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';

/// Nearby hospitals (Sprint 3, Prompt 6) — cached Google Places lookup, surfaced
/// prominently when the user's city risk is High. Handles loading, empty,
/// error, not-configured and location-unavailable states gracefully.
class NearbyHospitalsScreen extends ConsumerWidget {
  const NearbyHospitalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(nearbyHospitalsProvider);
    final isHigh =
        ref.watch(currentCityRiskProvider).value?.riskLevel == RiskLevel.high;

    return Scaffold(
      backgroundColor: AppColorsV2.shell,
      appBar: AppBar(
        backgroundColor: AppColorsV2.shell,
        elevation: 0,
        foregroundColor: AppColorsV2.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: Text('Nearby Hospitals', style: AppTextStylesV2.cardTitle),
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const _Centered(
            spinner: true,
            icon: Icons.local_hospital_outlined,
            title: 'Finding nearby hospitals…',
            message: 'Searching facilities around you.',
          ),
          error: (error, _) => _errorView(ref, error),
          data: (result) => _dataView(context, ref, result, isHigh),
        ),
      ),
    );
  }

  Widget _dataView(
    BuildContext context,
    WidgetRef ref,
    NearbyHospitalsResult result,
    bool isHigh,
  ) {
    if (result.hospitals.isEmpty) {
      return const _Centered(
        icon: Icons.search_off_rounded,
        title: 'No hospitals found nearby',
        message: 'We could not find facilities within range of your location.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        if (isHigh) ...[const _HighRiskBanner(), const SizedBox(height: 16)],
        HospitalList(
          hospitals: result.hospitals,
          onCall: (h) => _call(context, ref, h),
          onDirections: (h) => _directions(ref, h),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            '${_freshnessLabel(result)} · Google Places',
            style: AppTextStylesV2.caption.copyWith(
              color: AppColorsV2.textFaint,
            ),
          ),
        ),
      ],
    );
  }

  Widget _errorView(WidgetRef ref, Object error) {
    if (error is PlacesNotConfiguredException) {
      return const _Centered(
        icon: Icons.vpn_key_off_rounded,
        title: 'Hospital lookup unavailable',
        message: 'The maps service is not configured in this build.',
      );
    }
    if (error is LocationUnavailableException) {
      return const _Centered(
        icon: Icons.location_off_rounded,
        title: 'Location needed',
        message:
            'Enable location, or set your city in your profile, to find '
            'nearby hospitals.',
      );
    }
    return _Centered(
      icon: Icons.error_outline_rounded,
      title: "Couldn't load hospitals",
      message: 'You may be offline. Try again when your connection is back.',
      onRetry: () => ref.invalidate(nearbyHospitalsProvider),
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

class _HighRiskBanner extends StatelessWidget {
  const _HighRiskBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: AppColorsV2.riskHigh.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColorsV2.riskHigh.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: AppColorsV2.riskHigh,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: AppTextStylesV2.body.copyWith(
                  color: AppColorsV2.textPrimary,
                  fontSize: 12,
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

  const _Centered({
    required this.icon,
    required this.title,
    required this.message,
    this.spinner = false,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (spinner)
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColorsV2.teal),
                strokeWidth: 2.5,
              )
            else
              Icon(icon, size: 56, color: AppColorsV2.textTertiary),
            const SizedBox(height: 18),
            Text(
              title,
              style: AppTextStylesV2.cardTitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: AppTextStylesV2.body,
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 18),
              TextButton.icon(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: AppColorsV2.teal,
                  side: BorderSide(
                    color: AppColorsV2.teal.withValues(alpha: 0.4),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
