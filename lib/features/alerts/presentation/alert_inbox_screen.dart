import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/app_design_v2.dart';
import 'package:fyp_foreseeme/core/widgets/brand_loading.dart';
import 'package:fyp_foreseeme/core/widgets/offline_state.dart';
import 'package:fyp_foreseeme/features/alerts/domain/models/user_alert.dart';
import 'package:fyp_foreseeme/features/alerts/domain/services/alert_analytics.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/alerts_providers.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/services/alert_deep_link_router.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_visuals.dart';

/// Alert inbox / history (Sprint 4, Prompt 5).
///
/// Reads the user-scoped `userAlerts` stream and shows delivered alerts newest
/// first, with unread emphasis. Tapping an alert marks it read (persisted) and
/// opens its deep link when it points at a known in-app route. Pure
/// presentation: it only watches Riverpod providers (GOLDEN_RULES rule 1) — no
/// Firebase, no dispatch logic (that lives in the backend engine).
class AlertInboxScreen extends ConsumerWidget {
  const AlertInboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(userAlertsStreamProvider);

    return Scaffold(
      backgroundColor: AppColorsV2.shell,
      appBar: AppBar(
        backgroundColor: AppColorsV2.shell,
        elevation: 0,
        foregroundColor: AppColorsV2.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => context.pop(),
        ),
        title: Text('Alerts', style: AppTextStylesV2.cardTitle),
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const BrandLoading(),
          error: (error, _) => isOfflineError(error)
              ? OfflineState(
                  onRetry: () => ref.invalidate(userAlertsStreamProvider),
                )
              : Center(
                  child: TextButton.icon(
                    onPressed: () => ref.invalidate(userAlertsStreamProvider),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                  ),
                ),
          data: (alerts) =>
              alerts.isEmpty ? const _EmptyInbox() : _AlertList(alerts: alerts),
        ),
      ),
    );
  }
}

class _AlertList extends ConsumerWidget {
  final List<UserAlertModel> alerts;
  const _AlertList({required this.alerts});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      itemCount: alerts.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final alert = alerts[index];
        return _AlertTile(
          alert: alert,
          onTap: () async {
            // Mark read first (persists), then follow the deep link if it is a
            // known in-app route (reuses the Prompt 4 router's whitelist).
            await ref.read(markAlertReadProvider)(alert.id);
            final route = alert.deepLink;
            if (AlertDeepLinkRouter.knownRoutes.contains(route)) {
              // Engagement hook (Prompt 9): record the inbox open.
              ref
                  .read(alertAnalyticsProvider)
                  .logAlertOpened(route: route, source: AlertOpenSource.inbox);
              if (context.mounted) context.push(route);
            }
          },
        );
      },
    );
  }
}

class _AlertTile extends StatelessWidget {
  final UserAlertModel alert;
  final VoidCallback onTap;

  const _AlertTile({required this.alert, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final appearance = RiskVisuals.forLevel(
      RiskLevelX.fromJson(alert.riskLevel),
    );
    final unread = !alert.read;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: unread ? appearance.fill : AppColorsV2.glassFill,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: unread ? appearance.border : AppColorsV2.stroke,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(appearance.icon, size: 22, color: appearance.color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          alert.title,
                          style: AppTextStylesV2.body.copyWith(
                            color: AppColorsV2.textPrimary,
                            fontWeight: unread
                                ? FontWeight.w700
                                : FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(alert.body, style: AppTextStylesV2.body),
                      ],
                    ),
                  ),
                  if (unread) ...[
                    const SizedBox(width: 8),
                    Container(
                      width: 9,
                      height: 9,
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        color: appearance.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
              if (alert.recommendation != null) ...[
                const SizedBox(height: 12),
                _RecommendationRow(recommendation: alert.recommendation!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The cited advisory line. The source is always shown — recommendations are
/// looked up, never generated (Rule 11).
class _RecommendationRow extends StatelessWidget {
  final AlertRecommendation recommendation;
  const _RecommendationRow({required this.recommendation});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColorsV2.shellRaised.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColorsV2.strokeSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            recommendation.text,
            style: AppTextStylesV2.body.copyWith(
              color: AppColorsV2.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(
                Icons.verified_outlined,
                size: 13,
                color: AppColorsV2.textTertiary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Source: ${recommendation.source}',
                  style: AppTextStylesV2.caption,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyInbox extends StatelessWidget {
  const _EmptyInbox();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.notifications_none_rounded,
              size: 56,
              color: AppColorsV2.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              'No alerts yet',
              style: AppTextStylesV2.cardTitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              "When risk rises in your city, your alerts will appear here so you "
              'can review them anytime.',
              style: AppTextStylesV2.body,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
