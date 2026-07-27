import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/features/admin/domain/models/job_heartbeat.dart';
import 'package:fyp_foreseeme/features/admin/presentation/admin_providers.dart';
import 'package:fyp_foreseeme/features/admin/presentation/system_status_providers.dart';
import 'package:fyp_foreseeme/features/admin/presentation/widgets/not_authorized_view.dart';
import 'package:fyp_foreseeme/features/risk/domain/services/risk_staleness.dart';

/// System Monitoring Dashboard (Sprint M8.1, SDS FR8.1): a read-only operator
/// view of model status, scheduled-job health, and alert volume.
///
/// Hosted as a branch of [AdminShell] — it renders only its body content; the
/// shell provides the shared app bar/back button/bottom nav. Gates its own
/// content on `isAdminProvider`, matching the admin-override screen's
/// convention; the authoritative enforcement is server-side (`firestore.rules`
/// denies `jobHeartbeats`/`alertDispatchLog` reads to non-admins regardless).
///
/// "Active users" has no data source anywhere in the system yet (no counter,
/// no aggregation job) — rather than fabricate a number, that card says so
/// honestly, matching the project's established never-invent-a-number
/// discipline (see docs/MODULE_8_AUDIT.md §5).
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdminAsync = ref.watch(isAdminProvider);
    return SafeArea(
      child: isAdminAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const NotAuthorizedView(),
        data: (isAdmin) =>
            isAdmin ? const _DashboardBody() : const NotAuthorizedView(),
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        ForeSeeMeSpacing.gutter,
        ForeSeeMeSpacing.md,
        ForeSeeMeSpacing.gutter,
        ForeSeeMeSpacing.xxxl,
      ),
      children: [
        _sectionLabel(context, 'MODEL STATUS'),
        const SizedBox(height: ForeSeeMeSpacing.sm),
        const _ModelStatusCard(),
        const SizedBox(height: ForeSeeMeSpacing.xl),
        _sectionLabel(context, 'SCHEDULED JOBS'),
        const SizedBox(height: ForeSeeMeSpacing.sm),
        const _JobHealthSection(),
        const SizedBox(height: ForeSeeMeSpacing.xl),
        _sectionLabel(context, 'ALERTS'),
        const SizedBox(height: ForeSeeMeSpacing.sm),
        const _AlertVolumeCard(),
        const SizedBox(height: ForeSeeMeSpacing.xl),
        _sectionLabel(context, 'USERS'),
        const SizedBox(height: ForeSeeMeSpacing.sm),
        const _ActiveUsersCard(),
      ],
    );
  }
}

Widget _sectionLabel(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.only(left: ForeSeeMeSpacing.xs),
  child: Text(
    text,
    style: context.fsmText.labelSmall?.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.5,
      color: context.fsmPalette.textTertiary,
    ),
  ),
);

/// Shared card shell for every metric on this dashboard.
class _MetricCard extends StatelessWidget {
  final Widget child;
  const _MetricCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(ForeSeeMeSpacing.lg),
      decoration: ForeSeeMeSurface.card(context),
      child: child,
    );
  }
}

/// Small, colour+icon+text status pill — never colour alone, matching the risk
/// module's accessibility convention (`RiskVisuals`).
class _StatusPill extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  const _StatusPill({required this.color, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(ForeSeeMeRadius.full),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: context.fsmText.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Maps a job's run status to the same semantic colours the risk module uses
/// (success/warning/error), so "healthy"/"degraded"/"failed" reads consistently
/// with the rest of the app.
_StatusPill _statusPillFor(BuildContext context, JobRunStatus status) {
  final colors = context.fsmColors;
  return switch (status) {
    JobRunStatus.ok => _StatusPill(
      color: colors.success,
      icon: Icons.check_circle_outline_rounded,
      label: status.label,
    ),
    JobRunStatus.degraded => _StatusPill(
      color: colors.warning,
      icon: Icons.priority_high_rounded,
      label: status.label,
    ),
    JobRunStatus.failed => _StatusPill(
      color: context.fsmPalette.error,
      icon: Icons.error_outline_rounded,
      label: status.label,
    ),
    JobRunStatus.unknown => _StatusPill(
      color: context.fsmPalette.textTertiary,
      icon: Icons.help_outline_rounded,
      label: status.label,
    ),
  };
}

/// Generic loading/error scaffolding shared by every metric card, so each card
/// only has to describe its data state.
class _AsyncMetric<T> extends ConsumerWidget {
  final FutureProvider<T> provider;
  final Widget Function(BuildContext, T) builder;
  final String errorMessage;

  const _AsyncMetric({
    required this.provider,
    required this.builder,
    required this.errorMessage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(provider);
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: ForeSeeMeSpacing.sm),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (_, _) => Text(
        errorMessage,
        style: context.fsmText.bodySmall?.copyWith(color: context.fsmPalette.error),
      ),
      data: (value) => builder(context, value),
    );
  }
}

class _ModelStatusCard extends StatelessWidget {
  const _ModelStatusCard();

  @override
  Widget build(BuildContext context) {
    return _MetricCard(
      child: _AsyncMetric(
        provider: latestModelStatusProvider,
        errorMessage: 'Could not load model status.',
        builder: (context, status) {
          final palette = context.fsmPalette;
          final text = context.fsmText;
          if (status == null) {
            return Text(
              'No risk estimates have been written yet.',
              style: text.bodyMedium?.copyWith(color: palette.textSecondary),
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.model_training_rounded, color: palette.primary, size: 22),
              const SizedBox(width: ForeSeeMeSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status.version,
                      style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'Latest estimate ${riskAgeLabel(status.generatedAt)}',
                      style: text.bodySmall?.copyWith(color: palette.textTertiary),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _JobHealthSection extends StatelessWidget {
  const _JobHealthSection();

  @override
  Widget build(BuildContext context) {
    return _MetricCard(
      child: _AsyncMetric(
        provider: jobHeartbeatsProvider,
        errorMessage: 'Could not load job status.',
        builder: (context, heartbeats) => Column(
          children: [
            for (var i = 0; i < heartbeats.length; i++) ...[
              _JobHealthRow(heartbeat: heartbeats[i]),
              if (i != heartbeats.length - 1) ...[
                const SizedBox(height: ForeSeeMeSpacing.md),
                Container(height: 1, color: ForeSeeMeSurface.stroke(context)),
                const SizedBox(height: ForeSeeMeSpacing.md),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _JobHealthRow extends StatelessWidget {
  final JobHeartbeat heartbeat;
  const _JobHealthRow({required this.heartbeat});

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final hasRun = heartbeat.status != JobRunStatus.unknown;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                heartbeat.job,
                style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                hasRun
                    ? 'Last run ${riskAgeLabel(heartbeat.finishedAt)}'
                    : 'Never run yet',
                style: text.bodySmall?.copyWith(color: palette.textTertiary),
              ),
            ],
          ),
        ),
        _statusPillFor(context, heartbeat.status),
      ],
    );
  }
}

class _AlertVolumeCard extends StatelessWidget {
  const _AlertVolumeCard();

  @override
  Widget build(BuildContext context) {
    return _MetricCard(
      child: _AsyncMetric(
        provider: alertVolumeProvider,
        errorMessage: 'Could not load alert volume.',
        builder: (context, count) {
          final palette = context.fsmPalette;
          final text = context.fsmText;
          return Row(
            children: [
              Icon(Icons.campaign_outlined, color: palette.secondary, size: 22),
              const SizedBox(width: ForeSeeMeSpacing.md),
              Expanded(
                child: Text(
                  'Total alerts dispatched',
                  style: text.bodyMedium?.copyWith(color: palette.textSecondary),
                ),
              ),
              Text(
                '$count',
                style: text.displayMedium?.copyWith(fontSize: 26),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ActiveUsersCard extends StatelessWidget {
  const _ActiveUsersCard();

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    return _MetricCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.groups_outlined, color: palette.textTertiary, size: 22),
          const SizedBox(width: ForeSeeMeSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Not tracked yet',
                  style: text.titleMedium?.copyWith(color: palette.textSecondary),
                ),
                const SizedBox(height: 2),
                Text(
                  'Active-user counting has no data source yet — see '
                  'docs/MODULE_8_AUDIT.md for the follow-up decision.',
                  style: text.bodySmall?.copyWith(color: palette.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
