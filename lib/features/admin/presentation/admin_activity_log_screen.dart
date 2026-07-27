import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/features/admin/domain/models/admin_activity_log_entry.dart';
import 'package:fyp_foreseeme/features/admin/presentation/activity_log_providers.dart';
import 'package:fyp_foreseeme/features/admin/presentation/admin_providers.dart';
import 'package:fyp_foreseeme/features/admin/presentation/widgets/not_authorized_view.dart';
import 'package:fyp_foreseeme/features/risk/domain/services/risk_staleness.dart';

/// Admin Activity Log (Sprint M8.2, SDS FR8.4): a read-only, newest-first view
/// of recorded admin actions — currently risk overrides (set/clear); future
/// admin modules (content management, user management) append here too via
/// [AdminActivityLogRepository.append], with no change needed to this screen.
///
/// Hosted as a branch of [AdminShell] — it renders only its body content; the
/// shell provides the shared app bar/back button/bottom nav. Gates its own
/// content on `isAdminProvider`, matching the dashboard/override screens; the
/// authoritative enforcement is server-side (`firestore.rules` denies
/// `adminActivityLog` reads to non-admins regardless).
class AdminActivityLogScreen extends ConsumerWidget {
  const AdminActivityLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdminAsync = ref.watch(isAdminProvider);
    return SafeArea(
      child: isAdminAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const NotAuthorizedView(),
        data: (isAdmin) =>
            isAdmin ? const _LogList() : const NotAuthorizedView(),
      ),
    );
  }
}

class _LogList extends ConsumerWidget {
  const _LogList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(recentActivityLogProvider);
    final palette = context.fsmPalette;
    final text = context.fsmText;

    return entriesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Center(
        child: Text(
          'Could not load the activity log.',
          style: text.bodyMedium?.copyWith(color: palette.error),
        ),
      ),
      data: (entries) {
        if (entries.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(ForeSeeMeSpacing.xxxl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.history_toggle_off_rounded,
                    size: 48,
                    color: palette.textTertiary,
                  ),
                  const SizedBox(height: ForeSeeMeSpacing.md),
                  Text(
                    'No admin actions yet',
                    style: text.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: ForeSeeMeSpacing.sm),
                  Text(
                    'Overrides and other admin actions will appear here as '
                    'they happen.',
                    style: text.bodyLarge?.copyWith(
                      color: palette.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(
            ForeSeeMeSpacing.gutter,
            ForeSeeMeSpacing.md,
            ForeSeeMeSpacing.gutter,
            ForeSeeMeSpacing.xxxl,
          ),
          itemCount: entries.length,
          separatorBuilder: (_, _) =>
              const SizedBox(height: ForeSeeMeSpacing.sm),
          itemBuilder: (context, i) => _LogEntryTile(entry: entries[i]),
        );
      },
    );
  }
}

class _LogEntryTile extends StatelessWidget {
  final AdminActivityLogEntry entry;
  const _LogEntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;

    return Container(
      padding: const EdgeInsets.all(ForeSeeMeSpacing.lg),
      decoration: ForeSeeMeSurface.card(context, radius: ForeSeeMeRadius.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: palette.secondary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _iconForAction(entry.action),
              color: palette.secondary,
              size: 18,
            ),
          ),
          const SizedBox(width: ForeSeeMeSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.summary,
                  style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  '${entry.authorEmail} · ${riskAgeLabel(entry.createdAt)}',
                  style: text.bodySmall?.copyWith(color: palette.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Icon per action family. Falls back to a generic admin icon for any
  /// action code this screen doesn't yet recognise, so a future module's new
  /// action codes render sensibly without a matching change here.
  static IconData _iconForAction(String action) {
    if (action.startsWith('override')) return Icons.rule_outlined;
    if (action.startsWith('article')) return Icons.article_outlined;
    return Icons.admin_panel_settings_outlined;
  }
}
