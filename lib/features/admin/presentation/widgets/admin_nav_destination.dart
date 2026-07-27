import 'package:flutter/material.dart';

/// One destination in the admin shell's navigation (Sprint M8.1).
///
/// Single source of truth for [AdminShell]'s app-bar title and
/// [AdminBottomNavBar]'s items, so a future admin module (content management,
/// user management, activity log — SDS FR8.3/8.4/8.5) plugs in by adding one
/// entry here + one branch in the router, never by touching the shell itself.
@immutable
class AdminNavDestination {
  final IconData icon;
  final String label;

  const AdminNavDestination({required this.icon, required this.label});
}

/// The admin shell's destinations, in branch-index order (must match the
/// `StatefulShellRoute` branches in `app_router.dart`).
const List<AdminNavDestination> kAdminDestinations = [
  AdminNavDestination(icon: Icons.dashboard_outlined, label: 'Dashboard'),
  AdminNavDestination(icon: Icons.rule_outlined, label: 'Override'),
  AdminNavDestination(icon: Icons.article_outlined, label: 'Content'),
  AdminNavDestination(icon: Icons.people_outline_rounded, label: 'Users'),
  AdminNavDestination(icon: Icons.history_rounded, label: 'Logs'),
];
