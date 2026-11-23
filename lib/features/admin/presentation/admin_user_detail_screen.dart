import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/repositories/admin_api_client.dart';
import 'activity_log_providers.dart';
import 'admin_users_providers.dart';
import 'admin_providers.dart';
import 'admin_read.dart';
import 'widgets/not_authorized_view.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/features/auth/domain/models/user_directory_entry.dart';
import 'package:fyp_foreseeme/features/risk/domain/services/risk_staleness.dart';

class AdminUserDetailScreen extends ConsumerStatefulWidget {
  final UserDirectoryEntry entry;
  const AdminUserDetailScreen({super.key, required this.entry});

  @override
  ConsumerState<AdminUserDetailScreen> createState() =>
      _AdminUserDetailScreenState();
}

class _AdminUserDetailScreenState extends ConsumerState<AdminUserDetailScreen> {
  bool _busy = false;
  UserDirectoryEntry get entry => widget.entry;

  Future<void> _change(String action, String label) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$label account?'),
        content: Text(switch (action) {
          'delete' =>
            'Permanently delete the Firebase Authentication account for '
                '${entry.email.isEmpty ? entry.uid : entry.email}? '
                'The directory entry will be removed. Firestore records and subcollections will be retained.',
          'suspend' =>
            'Disable new sign-ins and revoke refresh tokens for this account?',
          _ => 'Allow this account to sign in again?',
        }),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(label),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(adminApiClientProvider)
          .post(
            ['users', entry.uid],
            {
              'action': action,
              if (action == 'delete') ...{
                'confirmUid': entry.uid,
                'retention': 'retain_firestore',
              },
            },
          );
      if (!mounted) return;
      ref.invalidate(userDirectoryListProvider);
      ref.invalidate(recentActivityLogProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Account updated.')));
      context.pop();
    } catch (error) {
      if (!mounted) return;
      ref.invalidate(userDirectoryListProvider);
      ref.invalidate(recentActivityLogProvider);
      final message = error is AdminApiException
          ? error.toString()
          : 'Could not update the account.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
        child: ref
            .watch(isAdminProvider)
            .when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: AdminReadError(
                  message: 'Could not verify the administrator session.',
                  error: error,
                  retry: () => ref.invalidate(isAdminProvider),
                ),
              ),
              data: (allowed) => !allowed
                  ? const NotAuthorizedView()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(
                        ForeSeeMeSpacing.gutter,
                        ForeSeeMeSpacing.md,
                        ForeSeeMeSpacing.gutter,
                        ForeSeeMeSpacing.xxxl,
                      ),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(ForeSeeMeSpacing.lg),
                          decoration: ForeSeeMeSurface.card(
                            context,
                            radius: ForeSeeMeRadius.md,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _row(context, 'Name', entry.name ?? '—'),
                              _divider(context),
                              _row(context, 'Email', entry.email),
                              _divider(context),
                              _row(context, 'Status', entry.status.label),
                              _divider(context),
                              _row(
                                context,
                                'Registered',
                                riskAgeLabel(entry.createdAt),
                              ),
                              _divider(context),
                              _row(context, 'User ID', entry.uid),
                            ],
                          ),
                        ),
                        const SizedBox(height: ForeSeeMeSpacing.lg),
                        if (_busy) const LinearProgressIndicator(),
                        Wrap(
                          spacing: ForeSeeMeSpacing.sm,
                          children: [
                            if (entry.status == UserStatus.blocked)
                              OutlinedButton(
                                onPressed: _busy
                                    ? null
                                    : () => _change('reactivate', 'Reactivate'),
                                child: const Text('Reactivate account'),
                              )
                            else
                              OutlinedButton(
                                onPressed: _busy
                                    ? null
                                    : () => _change('suspend', 'Suspend'),
                                child: const Text('Suspend account'),
                              ),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _change('delete', 'Delete'),
                              child: const Text('Delete account'),
                            ),
                          ],
                        ),
                      ],
                    ),
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
