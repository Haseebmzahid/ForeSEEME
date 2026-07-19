import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/core/widgets/brand_loading.dart';
import 'package:fyp_foreseeme/core/widgets/empty_state.dart';
import 'package:fyp_foreseeme/core/widgets/error_state.dart';
import 'package:fyp_foreseeme/core/widgets/medical_disclaimer.dart';
import 'package:fyp_foreseeme/core/widgets/offline_state.dart';
import 'package:fyp_foreseeme/core/widgets/timeline_row.dart';
import 'package:fyp_foreseeme/features/alerts/domain/models/user_alert.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/alerts_providers.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/services/alert_grouping.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_visuals.dart';

/// **Geospatial Activity Timeline** (Geospatial Intelligence sprint) — a
/// spatial, chronological read of the same alert history the Alert Inbox
/// already manages, purpose-built for map exploration rather than
/// notification triage.
///
/// It duplicates NO business logic: the data source is the exact same
/// [userAlertsStreamProvider] stream and the exact same [groupAlertsByDate]
/// bucketing the inbox uses — only the presentation (a connector-line
/// timeline instead of a filterable list) and the interaction (tapping an
/// entry hands its city back to the map) differ. The Alert Inbox remains the
/// operational read/unread notification center; this screen is part of the
/// map's exploration experience.
///
/// Reached by pushing `/risk-activity` for a `String?` result: tapping an
/// entry with a known city pops that city back to the caller (the map, which
/// then glides its camera there and opens the Area Insight sheet) instead of
/// pushing a second map instance.
class GeospatialTimelineScreen extends ConsumerWidget {
  const GeospatialTimelineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.fsmPalette;
    final async = ref.watch(userAlertsStreamProvider);

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
        title: Text('Recent Activity', style: context.fsmText.titleLarge),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: AppMotion.stateSwitcher(
                context,
                async.when(
                  loading: () => const BrandLoading(),
                  error: (error, _) => isOfflineError(error)
                      ? OfflineState(
                          onRetry: () =>
                              ref.invalidate(userAlertsStreamProvider),
                        )
                      : ErrorState(
                          title: "Couldn't load recent activity",
                          explanation:
                              'Something went wrong loading your activity. '
                              'Please try again.',
                          onRetry: () =>
                              ref.invalidate(userAlertsStreamProvider),
                          detail: '$error',
                        ),
                  data: (alerts) {
                    if (alerts.isEmpty) {
                      return const EmptyState(
                        icon: Icons.map_outlined,
                        title: 'No activity yet',
                        description:
                            'As risk changes in your area, activity will '
                            'appear here — tap any entry to see it on the map.',
                      );
                    }
                    return _Timeline(alerts: alerts);
                  },
                ),
              ),
            ),
            // Alerts carry health guidance, so the non-diagnostic framing is
            // pinned below the list — present in every state.
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: MedicalDisclaimer.inline(),
            ),
          ],
        ),
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.alerts});

  final List<UserAlertModel> alerts;

  @override
  Widget build(BuildContext context) {
    final groups = groupAlertsByDate(alerts, now: DateTime.now());
    final items = <Widget>[];
    for (final group in groups) {
      items.add(_DateHeader(text: group.header));
      for (var i = 0; i < group.alerts.length; i++) {
        items.add(
          _AlertTimelineRow(
            alert: group.alerts[i],
            isLast: i == group.alerts.length - 1,
          ),
        );
      }
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      itemCount: items.length,
      itemBuilder: (context, index) => items[index],
    );
  }
}

class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 12, 2, 10),
      child: Text(
        text.toUpperCase(),
        style: context.fsmText.labelSmall?.copyWith(
          letterSpacing: 1.2,
          color: context.fsmPalette.textTertiary,
        ),
      ),
    );
  }
}

class _AlertTimelineRow extends StatelessWidget {
  const _AlertTimelineRow({required this.alert, required this.isLast});

  final UserAlertModel alert;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final appearance = RiskVisuals.resolve(
      context,
      RiskLevelX.fromJson(alert.riskLevel),
    );
    final subtitleParts = <String>[
      if (alert.city.isNotEmpty) alert.city,
      '${appearance.label} risk',
      if (!alert.read) 'Unread',
    ];

    return TimelineRow(
      title: alert.title,
      subtitle: subtitleParts.join(' · '),
      icon: appearance.icon,
      color: appearance.color,
      isLast: isLast,
      onTap: alert.city.isEmpty ? null : () => context.pop(alert.city),
    );
  }
}
