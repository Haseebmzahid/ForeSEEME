import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_map_chrome.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_map_style.dart';

/// A floating risk-field legend that collapses to a small key control when not
/// needed (Geospatial Intelligence sprint) — so it never competes for space
/// with the map's tapped-city sheet.
///
/// Used only by the Risk Map. The expanded body is [RiskFieldLegendBody], the
/// approved prototype's legend (swatch + elevation glyph + level), and the
/// collapsed state matches the prototype's 48dp control shape. The
/// expand/collapse behaviour, semantics and haptic are unchanged.
class CollapsibleRiskLegend extends StatefulWidget {
  const CollapsibleRiskLegend({super.key, this.initiallyExpanded = true});

  final bool initiallyExpanded;

  @override
  State<CollapsibleRiskLegend> createState() => _CollapsibleRiskLegendState();
}

class _CollapsibleRiskLegendState extends State<CollapsibleRiskLegend> {
  late bool _expanded = widget.initiallyExpanded;

  void _toggle() {
    HapticFeedback.selectionClick();
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: _expanded ? 'Collapse risk legend' : 'Expand risk legend',
      child: ExcludeSemantics(
        child: PressableScale(
          onTap: _toggle,
          child: AnimatedSize(
            duration: AppMotion.medium,
            curve: AppMotion.curve,
            alignment: Alignment.bottomLeft,
            child: _expanded
                ? const RiskFieldLegendBody()
                : MapGlassPanel(
                    radius: 15,
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Icon(
                        Icons.palette_outlined,
                        size: 19,
                        color: RiskMapTheme.of(context).ink,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
