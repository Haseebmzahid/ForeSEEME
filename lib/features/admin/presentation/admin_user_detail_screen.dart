import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/features/auth/domain/models/user_directory_entry.dart';
import 'package:fyp_foreseeme/features/risk/domain/services/risk_staleness.dart';

/// Read-only user detail (Sprint M8.4, SDS FR8.5 "View User Details" —
/// business rule: "User details must be read-only unless editing is
/// permitted"; this sprint permits no editing, so the screen is entirely
/// read-only). Pushed from [AdminUsersScreen] with the tapped
/// [UserDirectoryEntry] as `extra`.
class AdminUserDetailScreen extends StatelessWidget {
  final UserDirectoryEntry entry;
  const AdminUserDetailScreen({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;

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
        title: Text('User Details', style: text.titleLarge),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            ForeSeeMeSpacing.gutter,
            ForeSeeMeSpacing.md,
            ForeSeeMeSpacing.gutter,
            ForeSeeMeSpacing.xxxl,
          ),
          children: [
            Container(
              padding: const EdgeInsets.all(ForeSeeMeSpacing.lg),
              decoration: ForeSeeMeSurface.card(context, radius: ForeSeeMeRadius.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row(context, 'Name', entry.name ?? '—'),
                  _divider(context),
                  _row(context, 'Email', entry.email),
                  _divider(context),
                  _row(context, 'Status', entry.status.label),
                  _divider(context),
                  _row(context, 'Registered', riskAgeLabel(entry.createdAt)),
                  _divider(context),
                  _row(context, 'User ID', entry.uid),
                ],
              ),
            ),
            const SizedBox(height: ForeSeeMeSpacing.lg),
            Container(
              padding: const EdgeInsets.all(ForeSeeMeSpacing.lg),
              decoration: BoxDecoration(
                color: palette.tertiary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(ForeSeeMeRadius.md),
                border: Border.all(color: palette.tertiary.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: palette.tertiary),
                  const SizedBox(width: ForeSeeMeSpacing.sm),
                  Expanded(
                    child: Text(
                      'This view is read-only. Suspending, reactivating, or '
                      'deleting this account requires an operator script — see '
                      'docs/user_management.md.',
                      style: text.bodySmall?.copyWith(color: palette.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ForeSeeMeSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: text.labelSmall?.copyWith(color: palette.textTertiary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: text.bodyMedium?.copyWith(color: palette.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider(BuildContext context) =>
      Container(height: 1, color: ForeSeeMeSurface.stroke(context));
}
