import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/features/admin/domain/models/job_heartbeat.dart';
import 'package:fyp_foreseeme/features/admin/presentation/admin_providers.dart';
import 'package:fyp_foreseeme/features/admin/presentation/admin_read.dart';
import 'package:fyp_foreseeme/features/admin/presentation/system_status_providers.dart';
import 'package:fyp_foreseeme/features/admin/presentation/widgets/not_authorized_view.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

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
            isAdmin ? const _DashboardBody() : const NotAuthorizedView(),
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () async {
        final requests = [
          ref.refresh(jobHeartbeatsProvider.future),
          ref.refresh(alertVolumeProvider.future),
          ref.refresh(latestModelStatusProvider.future),
          ref.refresh(deployedModelProvider.future),
          ref.refresh(accountMetricsProvider.future),
        ];
        await Future.wait(
          requests.map((request) async {
            try {
              await request;
            } catch (_) {
              /* Individual cards display errors. */
            }
          }),
        );
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          ForeSeeMeSpacing.gutter,
          ForeSeeMeSpacing.md,
          ForeSeeMeSpacing.gutter,
          ForeSeeMeSpacing.xxxl,
        ),
        children: [
          const _OverallStatus(),
          const SizedBox(height: ForeSeeMeSpacing.xl),
          _sectionLabel(context, 'MODEL STATUS'),
          const SizedBox(height: ForeSeeMeSpacing.sm),
          const _ModelStatusCard(),
          const SizedBox(height: ForeSeeMeSpacing.sm),
          _MetricCard(
            child: _AsyncMetric(
              provider: deployedModelProvider,
              errorMessage: 'Could not load the deployed model.',
              builder: (_, status) => Text(
                status == null
                    ? 'Deployed model · Not available yet'
                    : 'Deployed model · ${status.version}\nVerified ${status.generatedAt.toLocal()}',
              ),
            ),
          ),
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
          _MetricCard(
            child: _AsyncMetric(
              provider: accountMetricsProvider,
              errorMessage: 'Could not load user metrics.',
              builder: (_, metrics) => Text(
                metrics == null
                    ? 'Total registered users · Not available yet\nActive users · Not available yet'
                    : 'Total registered users · ${metrics.totalUsers}\n'
                          'Active users in ${metrics.windowDays} days · ${metrics.activeUsers}\n'
                          'Measured ${metrics.generatedAt.toLocal()}',
              ),
            ),
          ),
        ],
      ),
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
  const _StatusPill({
    required this.color,
    required this.icon,
    required this.label,
  });

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
      skipLoadingOnRefresh: false,
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
      error: (error, _) => AdminReadError(
        message: errorMessage,
        error: error,
        retry: () => ref.invalidate(provider),
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
              Icon(
                Icons.model_training_rounded,
                color: palette.primary,
                size: 22,
              ),
              const SizedBox(width: ForeSeeMeSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Latest estimate · ${status.version}',
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Generated ${status.generatedAt.toLocal()}',
                      style: text.bodySmall?.copyWith(
                        color: palette.textTertiary,
                      ),
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

class _JobHealthSection extends ConsumerWidget {
  const _JobHealthSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _MetricCard(
      child: _AsyncMetric(
        provider: jobHeartbeatsProvider,
        errorMessage: 'Could not load job status.',
        builder: (context, heartbeats) => Column(
          children: [
            for (var i = 0; i < heartbeats.length; i++) ...[
              if (heartbeats[i].readError case final error?)
                AdminReadError(
                  message: 'Could not load ${heartbeats[i].job}.',
                  error: error,
                  retry: () => ref.invalidate(jobHeartbeatsProvider),
                )
              else
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
    final now = DateTime.now();
    final hasRun = heartbeat.hasRun;
    final lastSuccess = heartbeat.lastSuccessfulAt;
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
                    ? 'Latest run · ${heartbeat.status.label}'
                    : 'Never executed',
                style: text.bodySmall?.copyWith(color: palette.textTertiary),
              ),
              if (hasRun) ...[
                Text('Started ${heartbeat.startedAt.toLocal()}'),
                Text('Completed ${heartbeat.finishedAt.toLocal()}'),
                Text('Duration · ${heartbeat.durationMs} ms'),
                if (heartbeat.isStale(now)) const Text('Heartbeat is stale'),
                if (heartbeat.counts.isNotEmpty)
                  Text(
                    heartbeat.counts.entries
                        .map((item) => '${item.key} · ${item.value}')
                        .join(', '),
                  ),
                if (heartbeat.error != null) Text(heartbeat.error!),
              ],
              Text(
                lastSuccess == null
                    ? 'Last success · Not available yet'
                    : 'Last success · ${lastSuccess.toLocal()}',
              ),
              if (heartbeat.job == 'compute_risk')
                Text(
                  'Model in latest successful batch · '
                  '${heartbeat.lastSuccessfulModelVersion ?? 'Not available yet'}',
                ),
            ],
          ),
        ),
        _statusPillFor(context, heartbeat.healthAt(now)),
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
                  style: text.bodyMedium?.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ),
              if (count == null)
                const Flexible(child: Text('Not available yet'))
              else
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

class _OverallStatus extends ConsumerWidget {
  const _OverallStatus();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(jobHeartbeatsProvider).asData?.value ?? const [];
    final deployed = ref.watch(deployedModelProvider).asData?.value;
    final now = DateTime.now();
    final health = jobs.map((job) => job.healthAt(now)).toList();
    final inferred = jobs.where((job) => job.job == 'compute_risk').firstOrNull;
    final severity = health.contains(JobRunStatus.failed)
        ? JobRunStatus.failed
        : health.contains(JobRunStatus.degraded)
        ? JobRunStatus.degraded
        : health.isEmpty ||
              health.contains(JobRunStatus.unknown) ||
              deployed == null ||
              inferred?.lastSuccessfulModelVersion == null
        ? JobRunStatus.unknown
        : deployed.version != inferred!.lastSuccessfulModelVersion
        ? JobRunStatus.degraded
        : JobRunStatus.ok;
    return _MetricCard(
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        children: [
          const Text('Overall operational status'),
          _statusPillFor(context, severity),
        ],
      ),
    );
  }
}
