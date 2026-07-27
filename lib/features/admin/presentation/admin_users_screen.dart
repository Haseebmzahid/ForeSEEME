import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/core/widgets/empty_state.dart';
import 'package:fyp_foreseeme/features/admin/presentation/admin_providers.dart';
import 'package:fyp_foreseeme/features/admin/presentation/admin_users_providers.dart';
import 'package:fyp_foreseeme/features/admin/presentation/widgets/not_authorized_view.dart';
import 'package:fyp_foreseeme/features/auth/domain/models/user_directory_entry.dart';

/// Admin User Management (Sprint M8.4, SDS FR8.5): a read-only, searchable,
/// filterable directory of registered users.
///
/// Deliberately does not offer suspend/block/delete/add-user in-app — those
/// need the Firebase Auth Admin SDK (list-all, disable, delete), which is not
/// reachable from Firestore rules the way every other admin surface's data
/// is. They ship as operator scripts instead (see the banner below and
/// docs/user_management.md) rather than as buttons that would either be fake
/// (a Firestore-only "blocked" label nobody's account actually respects) or
/// require a first-of-its-kind authenticated backend API this project
/// doesn't have.
///
/// Hosted as a branch of [AdminShell] — it renders only its body content; the
/// shell provides the shared app bar/back button/bottom nav. Gates its own
/// content on `isAdminProvider`, matching every other admin screen; the
/// authoritative enforcement is server-side (`firestore.rules` denies
/// `userDirectory` reads to non-admins regardless).
class AdminUsersScreen extends ConsumerWidget {
  const AdminUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdminAsync = ref.watch(isAdminProvider);
    return SafeArea(
      child: isAdminAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const NotAuthorizedView(),
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
    final text = context.fsmText;
    final palette = context.fsmPalette;

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
              _SearchField(onChanged: (v) => setState(() => _query = v)),
              const SizedBox(height: ForeSeeMeSpacing.sm),
              _StatusFilterRow(
                value: _statusFilter,
                onChanged: (s) => setState(() => _statusFilter = s),
              ),
              const SizedBox(height: ForeSeeMeSpacing.sm),
              const _OperatorOnlyBanner(),
            ],
          ),
        ),
        Expanded(
          child: usersAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(
              child: Text(
                'Could not load the user directory.',
                style: text.bodyMedium?.copyWith(color: palette.error),
              ),
            ),
            data: (users) {
              if (users.isEmpty) {
                return const EmptyState(
                  icon: Icons.people_outline_rounded,
                  title: 'No registered users yet',
                  description:
                      'Users appear here once they create an account.',
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
              color: selected ? palette.secondary : ForeSeeMeSurface.stroke(context),
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

class _OperatorOnlyBanner extends StatelessWidget {
  const _OperatorOnlyBanner();

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final accent = palette.tertiary;
    return Container(
      padding: const EdgeInsets.all(ForeSeeMeSpacing.md),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(ForeSeeMeRadius.md),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: accent),
          const SizedBox(width: ForeSeeMeSpacing.sm),
          Expanded(
            child: Text(
              'Suspending, reactivating, and deleting accounts are operator '
              'actions run outside the app — see backend/scripts/.',
              style: context.fsmText.bodySmall?.copyWith(
                color: palette.textSecondary,
              ),
            ),
          ),
        ],
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
    final isActive = entry.status == UserStatus.active;
    final statusColor = isActive ? context.fsmColors.success : palette.textTertiary;

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
                (entry.name?.isNotEmpty == true ? entry.name![0] : entry.email[0])
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
                    style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    entry.email,
                    style: text.bodySmall?.copyWith(color: palette.textTertiary),
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
