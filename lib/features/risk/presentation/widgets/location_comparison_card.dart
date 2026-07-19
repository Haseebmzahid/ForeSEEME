import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/location_comparison.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/trend_direction.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_visuals.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/trend_badge.dart';

/// **Location Intelligence** (Geospatial Intelligence sprint): "your area vs.
/// the nearest region", a real two-city comparison — never a fabricated
/// device-to-neighbourhood reading. Pure presentation over a
/// [LocationComparison]; every number is a stored estimate or a genuine
/// distance/AQI delta.
class LocationComparisonCard extends StatelessWidget {
  const LocationComparisonCard({
    super.key,
    required this.comparison,
    this.onDismiss,
  });

  final LocationComparison comparison;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final yourAppearance = RiskVisuals.resolve(
      context,
      comparison.yourEstimate.riskLevel,
    );
    final nearbyAppearance = RiskVisuals.resolve(
      context,
      comparison.nearbyEstimate.riskLevel,
    );
    final delta = comparison.aqiDelta;
    final deltaLabel = delta == 0
        ? 'Same AQI'
        : delta > 0
        ? 'AQI +$delta there'
        : 'AQI $delta there';

    return Semantics(
      container: true,
      label:
          'Location intelligence. Your area, ${comparison.yourCity}: '
          '${yourAppearance.label} risk. Nearby, ${comparison.nearbyCity}: '
          '${nearbyAppearance.label} risk. $deltaLabel.',
      child: ExcludeSemantics(
        child: Container(
          // Wide enough for the longest trend label ("Insufficient data")
          // inside TrendBadge's own padding without crowding it.
          width: 300,
          padding: const EdgeInsets.all(16),
          decoration: ForeSeeMeSurface.card(context, radius: ForeSeeMeRadius.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.my_location_rounded,
                    size: 16,
                    color: palette.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'LOCATION INTELLIGENCE',
                      style: text.labelSmall?.copyWith(
                        letterSpacing: 1.0,
                        color: palette.textTertiary,
                      ),
                    ),
                  ),
                  if (onDismiss != null)
                    InkWell(
                      onTap: onDismiss,
                      borderRadius: BorderRadius.circular(ForeSeeMeRadius.full),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: palette.textTertiary,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _AreaRow(
                label: 'Your Area',
                city: comparison.yourCity,
                appearance: yourAppearance,
                trend: comparison.yourTrend,
              ),
              const SizedBox(height: 10),
              _AreaRow(
                label: 'Nearby Region',
                city: comparison.nearbyCity,
                appearance: nearbyAppearance,
                trend: comparison.nearbyTrend,
              ),
              const SizedBox(height: 10),
              Divider(height: 1, color: palette.outlineVariant),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.air_rounded, size: 14, color: palette.textTertiary),
                  const SizedBox(width: 6),
                  Text(
                    deltaLabel,
                    style: text.bodySmall?.copyWith(
                      color: palette.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AreaRow extends StatelessWidget {
  const _AreaRow({
    required this.label,
    required this.city,
    required this.appearance,
    required this.trend,
  });

  final String label;
  final String city;
  final RiskAppearance appearance;
  final TrendDirection trend;

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    // Two lines rather than one crammed row: the trend badge's text (e.g.
    // "Insufficient data") can be long, so it gets its own row rather than
    // fighting the city name and risk chip for horizontal space.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: text.labelSmall?.copyWith(
                      color: palette.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    city,
                    style: text.bodyMedium?.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: appearance.fill,
                borderRadius: BorderRadius.circular(ForeSeeMeRadius.full),
                border: Border.all(color: appearance.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(appearance.icon, size: 12, color: appearance.color),
                  const SizedBox(width: 4),
                  Text(
                    appearance.label,
                    style: text.labelSmall?.copyWith(
                      color: appearance.color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TrendBadge(direction: trend),
      ],
    );
  }
}
