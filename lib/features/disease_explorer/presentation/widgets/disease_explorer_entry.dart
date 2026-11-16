import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/foreseeme_theme.dart';
import '../../../../core/theme/foreseeme_tokens.dart';
import '../../../../core/widgets/app_motion.dart';
import 'disease_glass.dart';
import 'environment_orb.dart';

/// One additive Home destination; the existing router owns the navigation.
class DiseaseExplorerEntry extends StatelessWidget {
  const DiseaseExplorerEntry({super.key});
  @override
  Widget build(BuildContext context) {
    void open() => context.push('/disease-explorer');
    return Semantics(
      button: true,
      label: 'Explore Disease Risks. Dengue, Smog and Influenza. Explore now.',
      onTap: open,
      child: ExcludeSemantics(
        child: PressableScale(
          child: DiseaseGlass(
            blur: true,
            padding: EdgeInsets.zero,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: open,
                borderRadius: BorderRadius.circular(ForeSeeMeRadius.xl),
                child: Padding(
                  padding: const EdgeInsets.all(ForeSeeMeSpacing.lg),
                  child: Row(
                    children: [
                      const EnvironmentOrb(size: 76),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Explore Disease Risks',
                              style: context.fsmText.titleLarge,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Dengue · Smog · Influenza',
                              style: context.fsmText.labelMedium?.copyWith(
                                color: context.fsmPalette.secondary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Explore independent environmental estimates for your city.',
                              style: context.fsmText.bodySmall,
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              children: [
                                Text(
                                  'Explore now',
                                  style: context.fsmText.labelLarge?.copyWith(
                                    color: context.fsmPalette.secondary,
                                  ),
                                ),
                                Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 18,
                                  color: context.fsmPalette.secondary,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Labelled map affordance; preserves the selected-city query exactly.
class DiseaseExplorerMapAction extends StatelessWidget {
  const DiseaseExplorerMapAction({super.key, this.city});
  final String? city;
  @override
  Widget build(BuildContext context) => DiseaseGlass(
    blur: true,
    radius: ForeSeeMeRadius.md,
    padding: EdgeInsets.zero,
    child: TextButton.icon(
      onPressed: () => context.push(
        Uri(
          path: '/disease-explorer',
          queryParameters: city == null ? null : {'city': city!},
        ).toString(),
      ),
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: context.fsmPalette.textPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      icon: const Icon(Icons.biotech_rounded, size: 20),
      label: const Text('Disease Explorer'),
    ),
  );
}
