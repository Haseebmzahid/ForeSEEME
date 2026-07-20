import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/resource_article.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/resource_visuals.dart';

/// A horizontally-scrollable "All / topic" filter row for browsing the
/// self-care guides by category (Goal 1). Pure UI-state — the selected filter
/// lives in the screen's local state, not a provider (Playbook §4.2 rule 2:
/// selection state is presentation state).
class CategoryChipRow extends StatelessWidget {
  final List<ResourceTopic> topics;
  final ResourceTopic? selected;
  final ValueChanged<ResourceTopic?> onSelected;

  const CategoryChipRow({
    super.key,
    required this.topics,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _Chip(
            label: 'All',
            selected: selected == null,
            color: context.fsmPalette.primary,
            onTap: () => onSelected(null),
          ),
          for (final topic in topics)
            Padding(
              padding: const EdgeInsets.only(left: ForeSeeMeSpacing.sm),
              child: _Chip(
                label: resourceTopicLabel(topic),
                selected: selected == topic,
                color: ResourceTopicVisual.of(context, topic).color,
                onTap: () => onSelected(topic),
              ),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(ForeSeeMeRadius.full),
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? color.withValues(alpha: 0.16) : Colors.transparent,
              borderRadius: BorderRadius.circular(ForeSeeMeRadius.full),
              border: Border.all(
                color: selected
                    ? color.withValues(alpha: 0.5)
                    : palette.outlineVariant,
              ),
            ),
            child: Text(
              label,
              style: context.fsmText.labelMedium?.copyWith(
                color: selected ? color : palette.textSecondary,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
