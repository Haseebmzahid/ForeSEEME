import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/app_design_v2.dart';
import 'package:fyp_foreseeme/features/risk/domain/services/risk_staleness.dart';

/// Shared, self-guarding "this estimate may be out of date" notice.
///
/// One staleness language across every risk surface (dashboard [RiskCard], Risk
/// Details, national map) — the user-facing complement to backend observability
/// (SPRINT_5 Prompts 11–12): a health app must never present an old estimate as
/// current. It renders the amber notice **only** when [generatedAt] is older than
/// [kRiskStaleAfter] (see [isRiskStale]); otherwise it collapses to nothing, so a
/// surface can drop it in unconditionally next to its "current risk" content.
///
/// * **Accessible** — pairs the amber tint with an icon + text (never colour
///   alone) and groups them as one semantic node.
/// * **Pure presentation** — no providers or I/O; classification is the
///   framework-free [isRiskStale], keeping the threshold identical everywhere.
class RiskStalenessNotice extends StatelessWidget {
  /// When the estimate was generated (UTC-normalised in the model).
  final DateTime generatedAt;

  /// Injectable clock for deterministic tests; defaults to now.
  final DateTime? now;

  /// Leading gap applied **only** when the notice is visible, so a fresh
  /// estimate leaves no dangling space in a Column.
  final double topGap;

  const RiskStalenessNotice({
    super.key,
    required this.generatedAt,
    this.now,
    this.topGap = 10,
  });

  static const String message = 'This estimate may be out of date';

  @override
  Widget build(BuildContext context) {
    if (!isRiskStale(generatedAt, now: now)) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(top: topGap),
      child: Semantics(
        container: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: AppColorsV2.riskMedium.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppColorsV2.riskMedium.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.history_toggle_off_rounded,
                size: 14,
                color: AppColorsV2.riskMedium,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  message,
                  style: AppTextStylesV2.caption.copyWith(
                    color: AppColorsV2.riskMedium,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
