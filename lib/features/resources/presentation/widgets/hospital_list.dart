import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/app_design_v2.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/hospital.dart';

/// A list of nearby-hospital cards. Pure widget — call/directions actions are
/// injected so it is testable without a launcher or live Places.
class HospitalList extends StatelessWidget {
  final List<Hospital> hospitals;
  final void Function(Hospital) onCall;
  final void Function(Hospital) onDirections;

  const HospitalList({
    super.key,
    required this.hospitals,
    required this.onCall,
    required this.onDirections,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final h in hospitals)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: HospitalCard(
              hospital: h,
              onCall: () => onCall(h),
              onDirections: () => onDirections(h),
            ),
          ),
      ],
    );
  }
}

class HospitalCard extends StatelessWidget {
  final Hospital hospital;
  final VoidCallback onCall;
  final VoidCallback onDirections;

  const HospitalCard({
    super.key,
    required this.hospital,
    required this.onCall,
    required this.onDirections,
  });

  @override
  Widget build(BuildContext context) {
    final canCall = hospital.hasPhone;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColorsV2.glassFill,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColorsV2.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hospital.name,
                      style: AppTextStylesV2.body.copyWith(
                        color: AppColorsV2.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    if (hospital.address.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        hospital.address,
                        style: AppTextStylesV2.caption,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _DistanceChip(distanceKm: hospital.distanceKm),
            ],
          ),
          if (hospital.hasRating || hospital.openNow != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (hospital.hasRating)
                  _RatingChip(
                    rating: hospital.rating!,
                    count: hospital.userRatingCount,
                  ),
                if (hospital.openNow != null)
                  _OpenNowChip(open: hospital.openNow!),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _CallButton(enabled: canCall, onTap: onCall),
              ),
              const SizedBox(width: 10),
              Expanded(child: _DirectionsButton(onTap: onDirections)),
            ],
          ),
        ],
      ),
    );
  }
}

class _DistanceChip extends StatelessWidget {
  final double distanceKm;
  const _DistanceChip({required this.distanceKm});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColorsV2.teal.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColorsV2.teal.withValues(alpha: 0.32)),
      ),
      child: Text(
        '${distanceKm.toStringAsFixed(1)} km',
        style: AppTextStylesV2.caption.copyWith(
          color: AppColorsV2.teal,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _RatingChip extends StatelessWidget {
  final double rating;
  final int? count;
  const _RatingChip({required this.rating, this.count});

  @override
  Widget build(BuildContext context) {
    final label = count != null && count! > 0
        ? '${rating.toStringAsFixed(1)} (${count!})'
        : rating.toStringAsFixed(1);
    return Semantics(
      label: 'Rated $label out of 5',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: AppColorsV2.riskMedium.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: AppColorsV2.riskMedium.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.star_rounded,
              size: 14,
              color: AppColorsV2.riskMedium,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: AppTextStylesV2.caption.copyWith(
                color: AppColorsV2.riskMedium,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpenNowChip extends StatelessWidget {
  final bool open;
  const _OpenNowChip({required this.open});

  @override
  Widget build(BuildContext context) {
    final color = open ? AppColorsV2.riskLow : AppColorsV2.textTertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            open ? Icons.schedule_rounded : Icons.schedule_outlined,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            open ? 'Open now' : 'Closed',
            style: AppTextStylesV2.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;

  const _CallButton({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(11),
          child: Ink(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              gradient: AppGradientsV2.brand,
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.call_rounded, size: 15, color: Colors.white),
                SizedBox(width: 7),
                Text(
                  'Call',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
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

class _DirectionsButton extends StatelessWidget {
  final VoidCallback onTap;

  const _DirectionsButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          ),
          child: Text(
            'Directions',
            textAlign: TextAlign.center,
            style: AppTextStylesV2.body.copyWith(
              color: AppColorsV2.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
