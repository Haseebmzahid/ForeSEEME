import 'package:flutter/material.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';

/// A premium standard scaffold for main screens.
///
/// Enforces the design-system background (a subtle surface gradient), removes
/// focus on tap, and standardises the shell. Background colour/gradient come
/// from the ForeSeeMe design system for the ambient brightness — never guessed.
class AppScaffold extends StatelessWidget {
  final Widget body;
  final Widget? bottomNavigationBar;
  final PreferredSizeWidget? appBar;
  final bool useSafeArea;
  final Color? backgroundColor;

  const AppScaffold({
    super.key,
    required this.body,
    this.bottomNavigationBar,
    this.appBar,
    this.useSafeArea = true,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;

    return GestureDetector(
      // Unfocus inputs when tapping outside
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: appBar,
        backgroundColor: backgroundColor ?? palette.background,
        body: DecoratedBox(
          decoration: BoxDecoration(
            color: backgroundColor,
            gradient:
                backgroundColor == null ? context.fsmColors.gradients.surface : null,
          ),
          child: useSafeArea ? SafeArea(child: body) : body,
        ),
        bottomNavigationBar: bottomNavigationBar,
      ),
    );
  }
}
