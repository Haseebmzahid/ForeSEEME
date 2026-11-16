import 'package:flutter/material.dart';
import '../../../../core/theme/foreseeme_theme.dart';
import '../../../../core/theme/foreseeme_tokens.dart';
import '../../../../core/widgets/app_motion.dart';
import '../../../risk/domain/models/risk_estimate_model.dart';
import '../../../risk/domain/services/risk_staleness.dart';
import '../../../risk/presentation/widgets/risk_visuals.dart';
import '../../domain/models/disease_risk_estimate.dart';
import 'disease_glass.dart';

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
      _ => p.info,
    };
    final icon = switch (disease) {
      'dengue' => Icons.water_drop_outlined,
      'smog' => Icons.air_rounded,
      _ => Icons.coronavirus_outlined,
    };
    final risk = e == null ? 'Not available' : '${e.riskLevel} risk';
    final freshness = e == null
        ? 'View data availability'
        : '${isRiskStale(e.generatedAt) ? 'Stale · ' : 'Updated '}${riskAgeLabel(e.generatedAt)}';
    return Semantics(
      button: true,
      label: '${diseaseNames[disease]}, $risk. View details.',
      onTap: onTap,
      child: PressableScale(
        child: DiseaseGlass(
          accent: accent,
          padding: EdgeInsets.zero,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(ForeSeeMeRadius.xl),
              child: Padding(
                padding: const EdgeInsets.all(ForeSeeMeSpacing.lg),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ExcludeSemantics(
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          borderRadius: ForeSeeMeRadius.control,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              accent.withValues(alpha: .22),
                              accent.withValues(alpha: .06),
                            ],
                          ),
                          border: Border.all(
                            color: accent.withValues(alpha: .22),
                          ),
                        ),
                        child: Icon(icon, color: accent, size: 23),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            diseaseNames[disease]!,
                            style: context.fsmText.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                visual?.icon ?? Icons.help_outline_rounded,
                                color: visual?.color ?? p.textSecondary,
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  risk,
                                  style: context.fsmText.headlineSmall
                                      ?.copyWith(
                                        color: visual?.color ?? p.textSecondary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            e == null
                                ? 'No independent estimate recorded'
                                : 'Model confidence  ${(e.confidence * 100).toStringAsFixed(1)}%',
                            style: context.fsmText.bodySmall?.copyWith(
                              color: p.textSecondary,
                            ),
                          ),
                          if (e?.lowConfidence == true) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Low confidence · interpret cautiously',
                              style: context.fsmText.bodySmall?.copyWith(
                                color: p.warning,
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            freshness,
                            style: context.fsmText.labelSmall?.copyWith(
                              color: e != null && isRiskStale(e.generatedAt)
                                  ? p.warning
                                  : p.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    ExcludeSemantics(
                      child: Icon(
                        Icons.arrow_outward_rounded,
                        color: p.textSecondary,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
