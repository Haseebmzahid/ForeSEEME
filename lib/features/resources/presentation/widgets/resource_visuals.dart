import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/resource_article.dart';

/// Icon + accent colour for a [ResourceTopic] (presentation-only mapping).
///
/// Colours resolve from the active theme's tokens for the ambient brightness, so
/// topic accents stay legible in light and dark: lungs → `secondary`,
/// asthma → `tertiary`, air quality → `warning`, heat → `error`.
class ResourceTopicVisual {
  final IconData icon;
  final Color color;

  const ResourceTopicVisual(this.icon, this.color);

  static ResourceTopicVisual of(BuildContext context, ResourceTopic topic) {
    final palette = context.fsmPalette;
    return switch (topic) {
      ResourceTopic.lungs => ResourceTopicVisual(
        Icons.air_rounded,
        palette.secondary,
      ),
      ResourceTopic.asthma => ResourceTopicVisual(
        Icons.monitor_heart_outlined,
        palette.tertiary,
      ),
      ResourceTopic.airQuality => ResourceTopicVisual(
        Icons.wb_sunny_outlined,
        context.fsmColors.warning,
      ),
      ResourceTopic.heat => ResourceTopicVisual(
        Icons.device_thermostat_rounded,
        palette.error,
      ),
    };
  }
}

/// Short display label for a [ResourceTopic] — the one place this mapping
/// lives, reused by the category filter row and anywhere else a topic needs a
/// human name.
String resourceTopicLabel(ResourceTopic topic) => switch (topic) {
  ResourceTopic.lungs => 'Lungs',
  ResourceTopic.asthma => 'Asthma',
  ResourceTopic.airQuality => 'Air Quality',
  ResourceTopic.heat => 'Heat',
};
