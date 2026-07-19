import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_legend.dart';

/// A floating glass [RiskLegend] that collapses to a small round key icon when
/// not needed (Geospatial Intelligence sprint) — so it never competes for
/// space with the map's tapped-city sheet. Wraps the existing [RiskLegend]
/// unchanged; this only owns the expand/collapse chrome and motion.
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
    final palette = context.fsmPalette;
    return Semantics(
      button: true,
      label: _expanded ? 'Collapse risk legend' : 'Expand risk legend',
      child: ExcludeSemantics(
        child: PressableScale(
          onTap: _toggle,
          child: AnimatedSize(
            duration: AppMotion.medium,
            curve: AppMotion.curve,
            alignment: Alignment.topLeft,
            child: _expanded
                ? const RiskLegend(direction: Axis.vertical)
                : Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: ForeSeeMeSurface.card(
                      context,
                      radius: ForeSeeMeRadius.full,
                    ),
                    child: Icon(
                      Icons.palette_outlined,
                      size: 20,
                      color: palette.primary,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
