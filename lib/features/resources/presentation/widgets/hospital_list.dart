import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/hospital.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/hospital_shared.dart';

/// A list of nearby-hospital cards. Pure widget — call/directions/detail
/// actions are injected so it is testable without a launcher or live Places.
class HospitalList extends StatelessWidget {
  final List<Hospital> hospitals;
  final void Function(Hospital) onCall;
  final void Function(Hospital) onDirections;
  final void Function(Hospital) onTap;

  const HospitalList({
    super.key,
    required this.hospitals,
    required this.onCall,
    required this.onDirections,
    required this.onTap,
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
              onTap: () => onTap(h),
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
  final VoidCallback onTap;

  const HospitalCard({
    super.key,
    required this.hospital,
    required this.onCall,
    required this.onDirections,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final canCall = hospital.hasPhone;

    // The tap region covers only the info area (name/address/chips) — the
    // Call/Directions row sits outside it, so there is never a gesture-arena
    // ambiguity between "open details" and "take a quick action" (no nested
    // tap targets competing for the same pointer).
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: ForeSeeMeSurface.card(context, radius: ForeSeeMeRadius.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            label:
                '${hospital.name}, ${hospital.distanceKm.toStringAsFixed(1)} '
                'kilometres away. Double tap for details.',
            child: PressableScale(
              onTap: onTap,
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
                              style: text.bodyMedium?.copyWith(
                                color: palette.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            if (hospital.address.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                hospital.address,
                                style: text.bodySmall?.copyWith(
                                  color: palette.textTertiary,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      DistanceChip(distanceKm: hospital.distanceKm),
                    ],
                  ),
                  if (hospital.hasRating || hospital.openNow != null) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (hospital.hasRating)
                          RatingChip(
                            rating: hospital.rating!,
                            count: hospital.userRatingCount,
                          ),
                        if (hospital.openNow != null)
                          OpenNowChip(open: hospital.openNow!),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: CallActionButton(enabled: canCall, onTap: onCall),
              ),
              const SizedBox(width: 10),
              Expanded(child: DirectionsActionButton(onTap: onDirections)),
            ],
          ),
        ],
      ),
    );
  }
}
