import 'dart:ui';
import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/features/admin/presentation/widgets/admin_nav_destination.dart';

/// Bottom navigation for the admin shell (Sprint M8.1) — same floating-glass
/// visual language as [AppBottomNavBar], data-driven over [kAdminDestinations]
/// instead of a hardcoded item list, since new admin modules append to that
/// list rather than editing this widget.
class AdminBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTabSelected;

  const AdminBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;

    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.only(
        bottom: 24.0,
        left: 20.0,
        right: 20.0,
        top: 8.0,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: 68,
            decoration: BoxDecoration(
              color: palette.surface.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: palette.onSurface.withValues(alpha: 0.08),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: palette.shadow.withValues(alpha: 0.2),
                  blurRadius: 32,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (var i = 0; i < kAdminDestinations.length; i++)
                  _NavBarItem(
                    icon: kAdminDestinations[i].icon,
                    label: kAdminDestinations[i].label,
                    isSelected: currentIndex == i,
                    onTap: () => onTabSelected(i),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavBarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavBarItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final accent = palette.primary;

    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(
            horizontal: isSelected ? 16.0 : 8.0,
            vertical: 8.0,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? accent.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? accent.withValues(alpha: 0.3) : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isSelected ? accent : palette.textTertiary,
                size: 24,
              ),
              if (isSelected) ...[
                const SizedBox(width: 6),
                Text(
                  label,
                  style: context.fsmText.labelMedium?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
