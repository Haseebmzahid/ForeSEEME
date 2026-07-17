import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
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
    final bandColor = _aqiBandColor(context, band);

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
                iconColor: context.fsmColors.info,
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

  /// Reuses the semantic three-tier vocabulary from the active theme — never a
  /// new hue — so AQI severity reads consistently with the rest of the risk
  /// surfaces (good→success, unhealthy→warning, hazardous→error).
  Color _aqiBandColor(BuildContext context, AqiBand band) {
    final colors = context.fsmColors;
    return switch (band) {
      AqiBand.good || AqiBand.moderate => colors.success,
      AqiBand.unhealthyForSensitiveGroups ||
      AqiBand.unhealthy => colors.warning,
      AqiBand.veryUnhealthy || AqiBand.hazardous => context.fsmPalette.error,
    };
  }
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
    final palette = context.fsmPalette;
    final text = context.fsmText;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: ForeSeeMeSurface.card(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(ForeSeeMeRadius.xs),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: text.labelSmall?.copyWith(
              letterSpacing: 1.2,
              color: palette.textTertiary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: text.titleLarge,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            bandLabel,
            style: text.bodySmall?.copyWith(
              color: bandColor ?? palette.textSecondary,
              fontWeight: bandColor != null ? FontWeight.w700 : FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
