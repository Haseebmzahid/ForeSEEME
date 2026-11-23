import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/core/widgets/empty_state.dart';
import 'package:fyp_foreseeme/features/admin/presentation/admin_providers.dart';
import '../data/repositories/admin_api_client.dart';
import 'activity_log_providers.dart';
import 'admin_read.dart';
import 'package:fyp_foreseeme/features/admin/presentation/admin_users_providers.dart';
import 'package:fyp_foreseeme/features/admin/presentation/widgets/not_authorized_view.dart';
import 'package:fyp_foreseeme/features/auth/domain/models/user_directory_entry.dart';

class AdminUsersScreen extends ConsumerWidget {
  const AdminUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdminAsync = ref.watch(isAdminProvider);
    return SafeArea(
      child: isAdminAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: AdminReadError(
            message: 'Could not verify the administrator session.',
            error: error,
            retry: () => ref.invalidate(isAdminProvider),
          ),
        ),
        data: (isAdmin) =>
            isAdmin ? const _UsersBody() : const NotAuthorizedView(),
      ),
    );
  }
}

class _UsersBody extends ConsumerStatefulWidget {
  const _UsersBody();

  @override
  ConsumerState<_UsersBody> createState() => _UsersBodyState();
}

class _UsersBodyState extends ConsumerState<_UsersBody> {
  String _query = '';
  UserStatus? _statusFilter;

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(userDirectoryListProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            ForeSeeMeSpacing.gutter,
            ForeSeeMeSpacing.md,
            ForeSeeMeSpacing.gutter,
            ForeSeeMeSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _SearchField(
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh directory',
                    onPressed: () => ref.invalidate(userDirectoryListProvider),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: ForeSeeMeSpacing.sm),
              _StatusFilterRow(
                value: _statusFilter,
                onChanged: (s) => setState(() => _statusFilter = s),
              ),
              if (const bool.fromEnvironment('ADMIN_INVITATIONS_ENABLED'))
                const Align(
                  alignment: Alignment.centerRight,
                  child: _InviteUserButton(),
                ),
              const SizedBox(height: ForeSeeMeSpacing.sm),
            ],
          ),
        ),
        Expanded(
          child: usersAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: AdminReadError(
                message: 'Could not load the user directory.',
                error: error,
                retry: () => ref.invalidate(userDirectoryListProvider),
              ),
            ),
            data: (users) {
              if (users.isEmpty) {
                return const EmptyState(
                  icon: Icons.people_outline_rounded,
                  title: 'No registered users yet',
                  description: 'Users appear here once they create an account.',
                );
              }
              final filtered = users.where(_matches).toList();
              if (filtered.isEmpty) {
                return const EmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'No matching users',
                  description: 'Try a different search or filter.',
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  ForeSeeMeSpacing.gutter,
                  0,
                  ForeSeeMeSpacing.gutter,
                  ForeSeeMeSpacing.xxxl,
                ),
                itemCount: filtered.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: ForeSeeMeSpacing.sm),
                itemBuilder: (context, i) => _UserTile(entry: filtered[i]),
              );
            },
          ),
        ),
      ],
    );
  }

  bool _matches(UserDirectoryEntry entry) {
    if (_statusFilter != null && entry.status != _statusFilter) return false;
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return entry.email.toLowerCase().contains(q) ||
        (entry.name?.toLowerCase().contains(q) ?? false);
  }
}

class _SearchField extends StatelessWidget {
  final ValueChanged<String> onChanged;
  const _SearchField({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    return TextField(
      onChanged: onChanged,
      style: context.fsmText.bodyLarge?.copyWith(color: palette.textPrimary),
      decoration: InputDecoration(
        hintText: 'Search by name or email…',
        hintStyle: context.fsmText.bodySmall,
        prefixIcon: Icon(Icons.search_rounded, color: palette.textTertiary),
        filled: true,
        fillColor: ForeSeeMeSurface.fill(context),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ForeSeeMeRadius.sm),
          borderSide: BorderSide(color: ForeSeeMeSurface.stroke(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ForeSeeMeRadius.sm),
          borderSide: BorderSide(color: palette.secondary),
        ),
      ),
    );
  }
}

class _StatusFilterRow extends StatelessWidget {
  final UserStatus? value;
  final ValueChanged<UserStatus?> onChanged;
  const _StatusFilterRow({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _chip(
          context,
          key: const Key('status-filter-all'),
          label: 'All',
          selected: value == null,
          onTap: () => onChanged(null),
        ),
        const SizedBox(width: ForeSeeMeSpacing.sm),
        for (final status in UserStatus.values) ...[
          _chip(
            context,
            key: Key('status-filter-${status.name}'),
            label: status.label,
            selected: value == status,
            onTap: () => onChanged(status),
          ),
          const SizedBox(width: ForeSeeMeSpacing.sm),
        ],
      ],
    );
  }

  Widget _chip(
    BuildContext context, {
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final palette = context.fsmPalette;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        key: key,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? palette.secondary.withValues(alpha: 0.15)
                : ForeSeeMeSurface.fill(context),
            borderRadius: BorderRadius.circular(ForeSeeMeRadius.full),
            border: Border.all(
              color: selected
                  ? palette.secondary
                  : ForeSeeMeSurface.stroke(context),
            ),
          ),
          child: Text(
            label,
            style: context.fsmText.labelMedium?.copyWith(
              color: selected ? palette.secondary : palette.textSecondary,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  final UserDirectoryEntry entry;
  const _UserTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final statusColor = switch (entry.status) {
      UserStatus.active => context.fsmColors.success,
      UserStatus.blocked => palette.error,
      UserStatus.pending => palette.textTertiary,
    };

    return InkWell(
      borderRadius: BorderRadius.circular(ForeSeeMeRadius.md),
      onTap: () => context.push('/admin/users/detail', extra: entry),
      child: Container(
        padding: const EdgeInsets.all(ForeSeeMeSpacing.lg),
        decoration: ForeSeeMeSurface.card(context, radius: ForeSeeMeRadius.md),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: palette.secondary.withValues(alpha: 0.15),
              child: Text(
                (entry.name?.characters.firstOrNull ??
                        entry.email.characters.firstOrNull ??
                        '?')
                    .toUpperCase(),
                style: text.bodyLarge?.copyWith(color: palette.secondary),
              ),
            ),
            const SizedBox(width: ForeSeeMeSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name ?? entry.email,
                    style: text.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    entry.email,
                    style: text.bodySmall?.copyWith(
                      color: palette.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(ForeSeeMeRadius.full),
                border: Border.all(color: statusColor.withValues(alpha: 0.4)),
              ),
              child: Text(
                entry.status.label,
                style: text.labelSmall?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InviteUserButton extends ConsumerWidget {
  const _InviteUserButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextButton.icon(
      icon: const Icon(Icons.person_add_alt_1),
      label: const Text('Invite user'),
      onPressed: () => showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _InviteUserDialog(),
      ),
    );
  }
}

class _InviteUserDialog extends ConsumerStatefulWidget {
  const _InviteUserDialog();

  @override
  ConsumerState<_InviteUserDialog> createState() => _InviteUserDialogState();
}

class _InviteUserDialogState extends ConsumerState<_InviteUserDialog> {
  String _email = '';
  String? _feedback;
  bool _busy = false;
  bool _complete = false;

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _feedback = null;
    });
    try {
      await ref
          .read(adminApiClientProvider)
          .post(['invitations'], {'email': _email.trim()});
      if (!mounted) return;
      setState(() {
        _complete = true;
        _feedback =
            'Account created. Firebase accepted the request to send the setup email.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _feedback = error is AdminApiException
            ? error.toString()
            : 'Could not request the invitation.',
      );
    } finally {
      if (mounted) {
        ref.invalidate(userDirectoryListProvider);
        ref.invalidate(recentActivityLogProvider);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('Invite user'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_complete)
              TextField(
                enabled: !_busy,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email address'),
                onChanged: (email) => setState(() => _email = email),
              ),
            if (_busy) const LinearProgressIndicator(),
            if (_feedback != null) Text(_feedback!),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(_complete ? 'Done' : 'Cancel'),
          ),
          if (!_complete)
            FilledButton(
              onPressed: _busy || !_email.contains('@') ? null : _send,
              child: const Text('Send setup email'),
            ),
        ],
      ),
    );
  }
}
