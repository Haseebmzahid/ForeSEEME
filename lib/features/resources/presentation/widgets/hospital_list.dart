import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
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
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final canCall = hospital.hasPhone;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: ForeSeeMeSurface.card(context, radius: ForeSeeMeRadius.md),
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
              Expanded(child: _CallButton(enabled: canCall, onTap: onCall)),
              const SizedBox(width: 10),
              Expanded(child: _DirectionsButton(onTap: onDirections)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shared pill for the hospital meta chips.
class _MetaChip extends StatelessWidget {
  final Color color;
  final IconData? icon;
  final String label;

  const _MetaChip({required this.color, required this.label, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: icon == null ? 10 : 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(ForeSeeMeRadius.full),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: context.fsmText.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
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
  Widget build(BuildContext context) => _MetaChip(
    color: context.fsmPalette.secondary,
    label: '${distanceKm.toStringAsFixed(1)} km',
  );
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
      child: _MetaChip(
        color: context.fsmColors.warning,
        icon: Icons.star_rounded,
        label: label,
      ),
    );
  }
}

class _OpenNowChip extends StatelessWidget {
  final bool open;
  const _OpenNowChip({required this.open});

  @override
  Widget build(BuildContext context) => _MetaChip(
    color: open ? context.fsmColors.success : context.fsmPalette.textTertiary,
    icon: open ? Icons.schedule_rounded : Icons.schedule_outlined,
    label: open ? 'Open now' : 'Closed',
  );
}

class _CallButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;

  const _CallButton({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
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
              gradient: context.fsmColors.gradients.brand,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.call_rounded, size: 15, color: palette.onPrimary),
                const SizedBox(width: 7),
                Text(
                  'Call',
                  style: context.fsmText.bodySmall?.copyWith(
                    color: palette.onPrimary,
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
    final palette = context.fsmPalette;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: palette.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: palette.outlineVariant),
          ),
          child: Text(
            'Directions',
            textAlign: TextAlign.center,
            style: context.fsmText.bodySmall?.copyWith(
              color: palette.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
