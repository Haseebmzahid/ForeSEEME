import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/hospital.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/hospital_shared.dart';

/// The premium "selecting a hospital" experience (Goal 3): name, distance,
/// address, phone/rating/open-now — each shown only when Places actually
/// returned it — plus Call and Directions. Shared by both entry points so the
/// detail never drifts: the map's persistent bottom sheet on marker
/// selection, and the list's modal on card tap.
class HospitalDetailSheet extends StatelessWidget {
  final Hospital hospital;
  final VoidCallback onCall;
  final VoidCallback onDirections;

  const HospitalDetailSheet({
    super.key,
    required this.hospital,
    required this.onCall,
    required this.onDirections,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final canCall = hospital.hasPhone;

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: palette.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(ForeSeeMeRadius.full),
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: palette.secondary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  Icons.local_hospital_rounded,
                  color: palette.secondary,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(hospital.name, style: text.titleLarge),
                ),
              ),
            ],
          ),
          if (hospital.address.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 16,
                  color: palette.textTertiary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hospital.address,
                    style: text.bodyMedium?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              DistanceChip(distanceKm: hospital.distanceKm),
              if (hospital.hasRating)
                RatingChip(
                  rating: hospital.rating!,
                  count: hospital.userRatingCount,
                ),
              if (hospital.openNow != null) OpenNowChip(open: hospital.openNow!),
            ],
          ),
          if (canCall) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.call_outlined, size: 16, color: palette.textTertiary),
                const SizedBox(width: 8),
                Text(
                  hospital.phoneNumber!,
                  style: text.bodyMedium?.copyWith(color: palette.textSecondary),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
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
