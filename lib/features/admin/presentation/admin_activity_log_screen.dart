import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/features/admin/domain/models/admin_activity_log_entry.dart';
import 'package:fyp_foreseeme/features/admin/presentation/activity_log_providers.dart';
import 'package:fyp_foreseeme/features/admin/presentation/admin_providers.dart';
import 'package:fyp_foreseeme/features/admin/presentation/widgets/not_authorized_view.dart';
import 'admin_read.dart';

class AdminActivityLogScreen extends ConsumerWidget {
  const AdminActivityLogScreen({super.key});

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
            isAdmin ? const _LogList() : const NotAuthorizedView(),
      ),
    );
  }
}

class _LogList extends ConsumerStatefulWidget {
  const _LogList();

  @override
  ConsumerState<_LogList> createState() => _LogListState();
}

class _LogListState extends ConsumerState<_LogList> {
  String? _action;
  DateTimeRange? _dates;

  Future<void> _chooseDates() async {
    final now = DateTime.now();
    final chosen = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: _dates,
    );
    if (chosen != null && mounted) setState(() => _dates = chosen);
  }

  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(recentActivityLogProvider);
    final palette = context.fsmPalette;
    final text = context.fsmText;

    return entriesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: AdminReadError(
          message: 'Could not load the activity log.',
          error: error,
          retry: () => ref.invalidate(recentActivityLogProvider),
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
                    'No administrative actions have been recorded yet.',
                    style: text.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  TextButton(
                    onPressed: () => ref.invalidate(recentActivityLogProvider),
                    child: const Text('Refresh log'),
                  ),
                ],
              ),
            ),
          );
        }
        final actions = entries.map((entry) => entry.action).toSet().toList()
          ..sort();
        final range = _dates;
        final selected = _action;
        final visible = entries.where((entry) {
          final when = entry.createdAt.toLocal();
          return (selected == null || entry.action == selected) &&
              (range == null ||
                  (!when.isBefore(range.start) &&
                      when.isBefore(
                        DateTime(
                          range.end.year,
                          range.end.month,
                          range.end.day + 1,
                        ),
                      )));
        }).toList();
        final limit = ref.watch(activityLogLimitProvider);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ForeSeeMeSpacing.gutter,
              ),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: ForeSeeMeSpacing.sm,
                children: [
                  DropdownButton<String>(
                    value: actions.contains(selected) ? selected : null,
                    hint: const Text('All actions'),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('All actions'),
                      ),
                      for (final action in actions)
                        DropdownMenuItem(
                          value: action,
                          child: Text(action.replaceAll('_', ' ')),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _action = value == '' ? null : value),
                  ),
                  TextButton(
                    onPressed: _chooseDates,
                    child: Text(range == null ? 'Date range' : 'Change dates'),
                  ),
                  if (range != null)
                    IconButton(
                      tooltip: 'Clear date filter',
                      onPressed: () => setState(() => _dates = null),
                      icon: const Icon(Icons.close),
                    ),
                  IconButton(
                    tooltip: 'Refresh log',
                    onPressed: () => ref.invalidate(recentActivityLogProvider),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(ForeSeeMeSpacing.gutter),
                itemCount: visible.length + 1,
                itemBuilder: (context, index) {
                  if (index < visible.length) {
                    return Padding(
                      padding: const EdgeInsets.only(
                        bottom: ForeSeeMeSpacing.sm,
                      ),
                      child: _LogEntryTile(entry: visible[index]),
                    );
                  }
                  return Column(
                    children: [
                      if (visible.isEmpty)
                        const Text(
                          'No matching records in the loaded history.',
                        ),
                      if (entries.length >= limit)
                        TextButton(
                          onPressed: () => ref
                              .read(activityLogLimitProvider.notifier)
                              .loadOlder(),
                          child: const Text('Load older actions'),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
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
                  entry.action.replaceAll('_', ' '),
                  style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(entry.summary),
                Text('Target · ${entry.target}'),
                Text('Outcome · ${entry.outcome ?? 'Legacy client record'}'),
                Text(
                  '${entry.authorEmail.isEmpty ? entry.authorUid : entry.authorEmail} · '
                  '${entry.createdAt.toLocal()}',
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
