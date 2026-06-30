import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/app_design_v2.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/resource_article.dart';

/// Icon + accent colour for a [ResourceTopic] (presentation-only mapping).
class ResourceTopicVisual {
  final IconData icon;
  final Color color;

  const ResourceTopicVisual(this.icon, this.color);

  static ResourceTopicVisual of(ResourceTopic topic) => switch (topic) {
    ResourceTopic.lungs => const ResourceTopicVisual(
      Icons.air_rounded,
      AppColorsV2.teal,
    ),
    ResourceTopic.asthma => const ResourceTopicVisual(
      Icons.monitor_heart_outlined,
      AppColorsV2.violet,
    ),
    ResourceTopic.airQuality => const ResourceTopicVisual(
      Icons.wb_sunny_outlined,
      AppColorsV2.riskMedium,
    ),
    ResourceTopic.heat => const ResourceTopicVisual(
      Icons.device_thermostat_rounded,
      AppColorsV2.riskHigh,
    ),
  };
}
