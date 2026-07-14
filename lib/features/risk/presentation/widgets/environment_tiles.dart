import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/a11y.dart';
import 'package:fyp_foreseeme/core/theme/app_design_v2.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/domain/services/aqi_band.dart';

/// Two always-visible environment tiles — AQI and weather — sourced directly
/// from the estimate's stored feature values (Playbook M-1 item 6). Unlike the
/// single "primary driver" card, both signals are shown regardless of which one
/// is dominant, each with a plain-language band label so the number carries
/// meaning without inventing new data.
class EnvironmentTiles extends StatelessWidget {
  final RiskEstimateModel estimate;
  const EnvironmentTiles({super.key, required this.estimate});

  @override
  Widget build(BuildContext context) {
    final band = aqiBandFor(estimate.aqi);
    final bandColor = _aqiBandColor(band);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Semantics(
              label:
                  'Air quality index ${estimate.aqi.round()}, '
                  '${band.label}',
              child: _EnvTile(
                icon: Icons.air_rounded,
                iconColor: bandColor,
                label: 'AIR QUALITY',
                value: estimate.aqi.round().toString(),
                bandLabel: band.label,
                bandColor: bandColor,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Semantics(
              label:
                  'Weather: ${estimate.temperature.round()} degrees Celsius, '
                  '${estimate.humidity.round()} percent humidity',
              child: _EnvTile(
                icon: Icons.thermostat_rounded,
                iconColor: AppColorsV2.blue,
                label: 'WEATHER',
                value: '${estimate.temperature.round()}°C',
                bandLabel: '${estimate.humidity.round()}% humidity',
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Reuses the single three-tier risk color vocabulary — never a new hue —
  /// so AQI severity reads consistently with the rest of the risk surfaces.
  Color _aqiBandColor(AqiBand band) => switch (band) {
    AqiBand.good || AqiBand.moderate => AppColorsV2.riskLow,
    AqiBand.unhealthyForSensitiveGroups ||
    AqiBand.unhealthy => AppColorsV2.riskMedium,
    AqiBand.veryUnhealthy || AqiBand.hazardous => AppColorsV2.riskHigh,
  };
}

class _EnvTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String bandLabel;
  final Color? bandColor;

  const _EnvTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.bandLabel,
    this.bandColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: A11y.glassFill(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: A11y.stroke(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(height: 12),
          Text(label, style: AppTextStylesV2.microLabel),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTextStylesV2.cardTitle.copyWith(fontSize: 18),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            bandLabel,
            style: AppTextStylesV2.caption.copyWith(
              color: bandColor ?? AppColorsV2.textSecondary,
              fontWeight: bandColor != null ? FontWeight.w700 : FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
