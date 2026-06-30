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
    final canCall = hospital.phoneNumber != null;

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
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppColorsV2.teal.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: AppColorsV2.teal.withValues(alpha: 0.32),
                  ),
                ),
                child: Text(
                  '${hospital.distanceKm.toStringAsFixed(1)} km',
                  style: AppTextStylesV2.caption.copyWith(
                    color: AppColorsV2.teal,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
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
