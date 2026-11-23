import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin_providers.dart';
import 'admin_read.dart';
import 'widgets/not_authorized_view.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/features/admin/presentation/widgets/admin_bottom_nav_bar.dart';
import 'package:fyp_foreseeme/features/admin/presentation/widgets/admin_nav_destination.dart';

/// Shared navigation for a verified admin session.
class AdminShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const AdminShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.fsmPalette;
    final destination = kAdminDestinations[navigationShell.currentIndex];
    final session = ref.watch(isAdminProvider);
    final authorized = session.asData?.value == true;

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
        title: Text(
          authorized ? destination.label : 'Admin Panel',
          style: context.fsmText.titleLarge,
        ),
      ),
      extendBody: true,
      body: session.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: AdminReadError(
            message: 'Could not verify the administrator session.',
            error: error,
            retry: () => ref.invalidate(isAdminProvider),
          ),
        ),
        data: (allowed) =>
            allowed ? navigationShell : const NotAuthorizedView(),
      ),
      bottomNavigationBar: authorized
          ? AdminBottomNavBar(
              currentIndex: navigationShell.currentIndex,
              onTabSelected: (index) => navigationShell.goBranch(
                index,
                initialLocation: index == navigationShell.currentIndex,
              ),
            )
          : null,
    );
  }
}
