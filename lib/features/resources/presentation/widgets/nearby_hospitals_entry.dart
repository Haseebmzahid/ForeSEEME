import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';

/// Entry point to the Hospital Directory from the Resource Center's
/// Preparedness section.
///
/// [prominent] (used on High risk) renders an `error`-tinted "Nearest Care"
/// card explaining why it surfaced; otherwise it is a calm `secondary`
/// "Hospital Directory" teaser. Both tones come from the design system,
/// resolved for the ambient brightness — the urgency is reused from the same
/// risk signal already computed elsewhere, never a second business rule.
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
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final accent = prominent ? palette.error : palette.secondary;
    final title = prominent ? 'Nearest Care' : 'Hospital Directory';
    final subtitle = prominent
        ? 'Surfaced because risk is High in your area'
        : 'Browse nearby hospitals, ready when you need them';

    return Semantics(
      button: true,
      label: '$title. $subtitle',
      child: PressableScale(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: prominent ? 0.10 : 0.08),
            borderRadius: BorderRadius.circular(ForeSeeMeRadius.md),
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
                      title,
                      style: text.bodyMedium?.copyWith(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: text.bodySmall?.copyWith(
                        fontSize: 11,
                        color: palette.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                'View →',
                style: text.bodySmall?.copyWith(
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
