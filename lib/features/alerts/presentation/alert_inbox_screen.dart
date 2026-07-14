import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/app_design_v2.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/core/widgets/brand_loading.dart';
import 'package:fyp_foreseeme/core/widgets/empty_state.dart';
import 'package:fyp_foreseeme/core/widgets/error_state.dart';
import 'package:fyp_foreseeme/core/widgets/medical_disclaimer.dart';
import 'package:fyp_foreseeme/core/widgets/offline_state.dart';
import 'package:fyp_foreseeme/features/alerts/domain/models/alert_filter.dart';
import 'package:fyp_foreseeme/features/alerts/domain/models/notification_preferences.dart';
import 'package:fyp_foreseeme/features/alerts/domain/models/user_alert.dart';
import 'package:fyp_foreseeme/features/alerts/domain/services/alert_analytics.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/alerts_providers.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/services/alert_deep_link_router.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/services/alert_grouping.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_visuals.dart';

/// Alert inbox / history (Sprint 4, Prompt 5).
///
/// Reads the user-scoped `userAlerts` stream and shows delivered alerts newest
/// first, with unread emphasis. Tapping an alert marks it read (persisted) and
/// opens its deep link when it points at a known in-app route. Pure
/// presentation: it only watches Riverpod providers (GOLDEN_RULES rule 1) — no
/// Firebase, no dispatch logic (that lives in the backend engine).
class AlertInboxScreen extends ConsumerStatefulWidget {
  const AlertInboxScreen({super.key});

  @override
  ConsumerState<AlertInboxScreen> createState() => _AlertInboxScreenState();
}

class _AlertInboxScreenState extends ConsumerState<AlertInboxScreen> {
  // Filter selection is pure UI state — a plain field on the widget's State,
  // mirroring DailyCheckInScreen's _selectedDate rather than introducing this
  // codebase's first StateProvider (Sprint 6A, S6A-06).
  AlertFilter _selectedFilter = AlertFilter.all;

  // Latches true the first time the list renders real tiles, so the entrance
  // stagger plays once per screen open — never again on a filter change or a
  // new alert streaming in (Sprint 6A, S6A-07). A fresh screen push creates a
  // fresh State, so re-opening the inbox does get a fresh reveal.
  bool _hasRevealedOnce = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(userAlertsStreamProvider);
    final unreadCount = ref.watch(unreadAlertCountProvider);

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
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all_rounded),
            tooltip: 'Mark all read',
            // Disabled (not hidden) at zero unread: a stable, always-present
            // control is easier to reason about — and to find with a screen
            // reader — than one that appears/disappears (Sprint 6A, S6A-03).
            onPressed: unreadCount == 0
                ? null
                : () async {
                    await ref.read(markAllAlertsReadProvider)();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('All alerts marked as read'),
                        backgroundColor: AppColorsV2.teal,
                      ),
                    );
                  },
          ),
        ],
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
                  onRetry: () => ref.invalidate(userAlertsStreamProvider),
                )
              : ErrorState(
                  title: "Couldn't load alerts",
                  explanation:
                      'Something went wrong loading your alerts. Please try '
                      'again.',
                  onRetry: () => ref.invalidate(userAlertsStreamProvider),
                  detail: '$error',
                ),
          data: (alerts) {
            if (alerts.isEmpty) {
              // True empty: nothing to filter, so no chip row either.
              return const EmptyState(
                icon: Icons.notifications_none_rounded,
                title: 'No alerts yet',
                description:
                    'When risk rises in your city, your alerts will appear '
                    'here so you can review them anytime.',
              );
            }
            // Captured before the flip, so only *this* build — the first one
            // to render real tiles — gets the entrance stagger.
            final animateEntrance = !_hasRevealedOnce;
            _hasRevealedOnce = true;
            final filtered = alerts
                .where(_selectedFilter.matches)
                .toList(growable: false);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: _FilterChipRow(
                    selected: _selectedFilter,
                    onSelected: (filter) =>
                        setState(() => _selectedFilter = filter),
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? const EmptyState(
                          icon: Icons.filter_alt_off_rounded,
                          title: 'No alerts match this filter',
                          description:
                              'Try a different filter, or choose "All" to '
                              'see everything.',
                        )
                      : _AlertList(
                          alerts: filtered,
                          animateEntrance: animateEntrance,
                        ),
                ),
              ],
            );
          },
                ),
              ),
            ),
            // Alerts carry health guidance, so the non-diagnostic framing is
            // pinned below the list — present in every state, including empty.
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

/// Single-select filter row: All / Unread / Low / Medium / High
/// (Sprint 6A, S6A-06, Decision 1). Client-side over the already-loaded
/// window — no new query, no new provider.
class _FilterChipRow extends StatelessWidget {
  final AlertFilter selected;
  final ValueChanged<AlertFilter> onSelected;

  const _FilterChipRow({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: AlertFilter.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = AlertFilter.values[index];
          return _FilterChip(
            label: filter.label,
            selected: filter == selected,
            onTap: () => onSelected(filter),
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$label filter',
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: selected
                    ? AppColorsV2.teal.withValues(alpha: 0.15)
                    : AppColorsV2.glassFill,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected
                      ? AppColorsV2.teal.withValues(alpha: 0.5)
                      : AppColorsV2.stroke,
                ),
              ),
              child: Text(
                label,
                style: AppTextStylesV2.caption.copyWith(
                  color: selected
                      ? AppColorsV2.teal
                      : AppColorsV2.textSecondary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AlertList extends ConsumerWidget {
  final List<UserAlertModel> alerts;

  /// Whether this build should play the staggered entrance (Sprint 6A,
  /// S6A-07) — true only for the screen's first real render; the caller
  /// latches this so it never repeats on a filter change or a new alert
  /// streaming in.
  final bool animateEntrance;

  const _AlertList({required this.alerts, required this.animateEntrance});

  /// Wraps [child] in [AppReveal] when [animateEntrance] is set; otherwise
  /// returns it unwrapped, so a non-first render never re-mounts the reveal
  /// machinery at all.
  Widget _reveal(int index, Widget child) {
    if (!animateEntrance) return child;
    return AppReveal(delayMs: (index * 30).clamp(0, 300), child: child);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Grouped once per build from the already-loaded, already-newest-first
    // stream value — no new provider (Sprint 6A, S6A-05). Headers scroll with
    // the content rather than pinning: at this data scale (≤50 alerts, per
    // the existing query cap) true sticky-pinned headers are complexity this
    // milestone doesn't need.
    final groups = groupAlertsByDate(alerts, now: DateTime.now());
    final items = <Widget>[];
    var index = 0;
    for (final group in groups) {
      items.add(_reveal(index++, _DateHeader(text: group.header)));
      for (final alert in group.alerts) {
        items.add(
          _reveal(
            index++,
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _AlertTile(
                alert: alert,
                onTap: () async {
                  // Mark read first (persists), then follow the deep link if
                  // it is a known in-app route (reuses the Prompt 4 router's
                  // whitelist).
                  await ref.read(markAlertReadProvider)(alert.id);
                  final route = alert.deepLink;
                  if (AlertDeepLinkRouter.knownRoutes.contains(route)) {
                    // Engagement hook (Prompt 9): record the inbox open.
                    ref
                        .read(alertAnalyticsProvider)
                        .logAlertOpened(
                          route: route,
                          source: AlertOpenSource.inbox,
                        );
                    if (context.mounted) context.push(route);
                  }
                },
              ),
            ),
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

/// A date-group header ("TODAY", "YESTERDAY", or an absolute date).
class _DateHeader extends StatelessWidget {
  final String text;
  const _DateHeader({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
      child: Text(text.toUpperCase(), style: AppTextStylesV2.microLabel),
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

    // Condition + disease, e.g. "Respiratory · Smog" (Sprint 6A, S6A-04). Both
    // fields are already parsed onto the model but were never surfaced; hide
    // the row entirely if neither resolves, rather than showing a stray "·".
    final conditionLabel = kNotificationConditionLabels[alert.category];
    final captionParts = <String>[
      if (conditionLabel != null && conditionLabel.isNotEmpty) conditionLabel,
      if (alert.disease.isNotEmpty) alert.disease,
    ];
    final caption = captionParts.join(' · ');

    // One structured announcement per tile instead of TalkBack reading each
    // child Text separately — mirrors the "Loading" pattern in AppSkeleton.
    final buffer = StringBuffer();
    if (unread) buffer.write('Unread. ');
    buffer.write('${appearance.label} risk');
    if (alert.disease.isNotEmpty) buffer.write(', ${alert.disease}');
    if (alert.city.isNotEmpty) buffer.write(' in ${alert.city}');
    buffer.write('. ${alert.title}');
    final semanticsLabel = buffer.toString();

    return Semantics(
      button: true,
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: Material(
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
                            if (caption.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(caption, style: AppTextStylesV2.caption),
                            ],
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

