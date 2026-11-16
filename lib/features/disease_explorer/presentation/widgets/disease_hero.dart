import 'package:flutter/material.dart';
import '../../../../core/theme/foreseeme_theme.dart';
import '../../../../core/widgets/app_motion.dart';
import 'disease_glass.dart';
import 'environment_orb.dart';

class DiseaseHero extends StatelessWidget {
  const DiseaseHero({super.key});
  @override
  Widget build(BuildContext context) => AppReveal(
    child: DiseaseGlass(
      blur: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ENVIRONMENT & HEALTH',
                      style: context.fsmText.labelSmall?.copyWith(
                        color: context.fsmPalette.secondary,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'One city.\nThree perspectives.',
                      style: context.fsmText.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.7,
                      ),
                    ),
                  ],
                ),
              ),
              const EnvironmentOrb(size: 96),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Explore each environmental risk independently and understand the evidence behind every estimate.',
            style: context.fsmText.bodySmall,
          ),
        ],
      ),
    ),
  );
}
