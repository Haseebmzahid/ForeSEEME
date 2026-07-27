import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/features/admin/presentation/widgets/admin_bottom_nav_bar.dart';
import 'package:fyp_foreseeme/features/admin/presentation/widgets/admin_nav_destination.dart';

/// Shared chrome for the operator-only admin area (Sprint M8.1): one app bar
/// (title follows the active branch) + one bottom nav over a
/// [StatefulNavigationShell], so a new admin module (content management, user
/// management, activity log) plugs in by adding a branch to the router + an
/// entry to [kAdminDestinations] — never by touching this widget or duplicating
/// its back button / app bar per screen.
///
/// Each hosted screen (e.g. [AdminDashboardScreen], [AdminOverrideScreen])
/// still individually gates its own content on `isAdminProvider` (matching the
/// existing admin-override convention) — this shell only provides chrome, not
/// authorization; the authoritative gate remains server-side in
/// `firestore.rules`.
class AdminShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const AdminShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final destination = kAdminDestinations[navigationShell.currentIndex];

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        foregroundColor: palette.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => context.pop(),
        ),
        title: Text(destination.label, style: context.fsmText.titleLarge),
      ),
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: AdminBottomNavBar(
        currentIndex: navigationShell.currentIndex,
        onTabSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
      ),
    );
  }
}
