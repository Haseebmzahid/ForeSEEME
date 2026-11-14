import 'package:flutter/material.dart';
import '../../../../core/theme/foreseeme_theme.dart';
import '../../../../core/theme/foreseeme_surface.dart';
import '../../../../core/theme/foreseeme_tokens.dart';
import '../../../../core/widgets/app_motion.dart';
import '../../../risk/domain/models/risk_estimate_model.dart';
import '../../../risk/domain/services/risk_staleness.dart';
import '../../../risk/presentation/widgets/risk_visuals.dart';
import '../../domain/models/disease_risk_estimate.dart';

class DiseaseRiskCard extends StatelessWidget {
  final String disease;
  final DiseaseRiskEstimate? estimate;
  final VoidCallback onTap;
  const DiseaseRiskCard({
    super.key,
    required this.disease,
    required this.estimate,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.fsmPalette;
    final e = estimate;
    final visual = e == null
        ? null
        : RiskVisuals.resolve(context, RiskLevelX.fromJson(e.riskLevel));
    final accent = switch (disease) {
      'dengue' => p.tertiary,
      'smog' => p.secondary,
      _ => p.primary,
    };
    final icon = switch (disease) {
      'dengue' => Icons.water_drop_outlined,
      'smog' => Icons.air_rounded,
      _ => Icons.coronavirus_outlined,
    };
    return PressableScale(
      child: Container(
        decoration: ForeSeeMeSurface.card(context),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: ForeSeeMeRadius.card,
            child: Padding(
              padding: const EdgeInsets.all(ForeSeeMeSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: .12),
                          borderRadius: ForeSeeMeRadius.control,
                        ),
                        child: Icon(icon, color: accent),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          diseaseNames[disease]!,
                          style: context.fsmText.titleLarge,
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Icon(
                        visual?.icon ?? Icons.help_outline_rounded,
                        color: visual?.color ?? p.textSecondary,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          e == null ? 'Not available' : '${e.riskLevel} risk',
                          style: context.fsmText.headlineSmall?.copyWith(
                            color: visual?.color ?? p.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    e == null
                        ? 'No independent estimate recorded'
                        : 'Model confidence  ${(e.confidence * 100).toStringAsFixed(1)}%',
                    style: context.fsmText.bodyMedium,
                  ),
                  if (e?.lowConfidence == true) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Low confidence · interpret cautiously',
                      style: context.fsmText.bodySmall?.copyWith(
                        color: p.warning,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    e == null
                        ? 'View data availability'
                        : '${isRiskStale(e.generatedAt) ? 'Stale · ' : 'Updated '}${riskAgeLabel(e.generatedAt)}',
                    style: context.fsmText.bodySmall?.copyWith(
                      color: e != null && isRiskStale(e.generatedAt)
                          ? p.warning
                          : p.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
