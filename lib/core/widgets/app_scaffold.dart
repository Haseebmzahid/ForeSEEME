import 'package:flutter/material.dart';
import 'package:fyp_foreseeme/core/theme/app_colors.dart';
import 'package:fyp_foreseeme/core/theme/app_theme.dart';

/// A premium, Stitch-inspired standard scaffold for all main screens.
/// Enforces background color, removes focus on tap, and standardizes spacing.
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
    return GestureDetector(
      // Unfocus inputs when tapping outside
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: appBar,
        backgroundColor: backgroundColor ?? AppColors.background,
        body: DecoratedBox(
          decoration: BoxDecoration(
            color: backgroundColor,
            gradient: backgroundColor == null ? AppGradients.background : null,
          ),
          child: useSafeArea ? SafeArea(child: body) : body,
        ),
        bottomNavigationBar: bottomNavigationBar,
      ),
    );
  }
}
