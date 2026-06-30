import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/app_design_v2.dart';

/// Entry point to the nearby-hospitals screen from the Resource Center.
///
/// [prominent] (used on High risk) renders a red-tinted card explaining why it
/// surfaced; otherwise it is a calm teal teaser row.
class NearbyHospitalsEntry extends StatelessWidget {
  final bool prominent;
  final VoidCallback onTap;

  const NearbyHospitalsEntry({
    super.key,
    required this.prominent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = prominent ? AppColorsV2.riskHigh : AppColorsV2.teal;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: prominent ? 0.10 : 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.local_hospital_outlined, size: 20, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nearby hospitals',
                      style: AppTextStylesV2.body.copyWith(
                        color: AppColorsV2.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    if (prominent) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Surfaced because risk is High in your area',
                        style: AppTextStylesV2.caption.copyWith(fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                'View →',
                style: AppTextStylesV2.caption.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
