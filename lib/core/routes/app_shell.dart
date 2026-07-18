import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fyp_foreseeme/core/routes/bottom_nav_bar.dart';
import 'package:fyp_foreseeme/features/medication/presentation/notification_refresh_provider.dart';

class AppShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const AppShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Activates the medication-coaching notification refresh listener for
    // the lifetime of the authenticated session (Sprint UX-M2.5, Phase 8) —
    // AppShell is mounted for every tab, so this fires once per session
    // rather than per screen.
    ref.watch(notificationRefreshProvider);

    return Scaffold(
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: AppBottomNavBar(
        currentIndex: navigationShell.currentIndex,
        onTabSelected: (index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
      ),
    );
  }
}
