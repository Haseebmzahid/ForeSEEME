import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/app_design_v2.dart';
import 'package:fyp_foreseeme/core/widgets/brand_loading.dart';
import 'package:fyp_foreseeme/core/widgets/error_state.dart';
import 'package:fyp_foreseeme/core/widgets/offline_state.dart';
import 'package:fyp_foreseeme/features/alerts/domain/models/notification_preferences.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/alerts_providers.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_visuals.dart';

/// Notification preferences (Sprint 3, Prompt 8): per-severity and per-condition
/// toggles. Settable + persisted now; consumed by Sprint 4's dispatch engine.
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationPreferencesControllerProvider);

    return Scaffold(
      backgroundColor: AppColorsV2.shell,
      appBar: AppBar(
        backgroundColor: AppColorsV2.shell,
        elevation: 0,
        foregroundColor: AppColorsV2.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: Text('Notifications', style: AppTextStylesV2.cardTitle),
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const BrandLoading(),
          error: (error, _) => isOfflineError(error)
              ? OfflineState(
                  onRetry: () =>
                      ref.invalidate(notificationPreferencesControllerProvider),
                )
              : ErrorState(
                  title: "Couldn't load settings",
                  explanation:
                      'Something went wrong loading your notification '
                      'settings. Please try again.',
                  onRetry: () =>
                      ref.invalidate(notificationPreferencesControllerProvider),
                  detail: '$error',
                ),
          data: (prefs) => _content(context, ref, prefs),
        ),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    WidgetRef ref,
    NotificationPreferences prefs,
  ) {
    final controller = ref.read(
      notificationPreferencesControllerProvider.notifier,
    );

    Future<void> run(
      BuildContext context,
      Future<void> Function() action,
    ) async {
      try {
        await action();
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not save. Check your connection.'),
            ),
          );
        }
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        Text(
          "Choose which risk alerts you receive. We'll start sending these in "
          'a future update.',
          style: AppTextStylesV2.body,
        ),
        const SizedBox(height: 18),
        _DevicePermissionRow(
          onTap: () => context.push('/notifications/permission'),
        ),
        const SizedBox(height: 22),
        Text('BY SEVERITY', style: AppTextStylesV2.microLabel),
        const SizedBox(height: 12),
        _Card(
          children: [
            _ToggleTile(
              icon: RiskVisuals.high.icon,
              iconColor: RiskVisuals.high.color,
              title: 'High risk alerts',
              value: prefs.highRiskAlerts,
              onChanged: (v) =>
                  run(context, () => controller.setHighRiskAlerts(v)),
            ),
            const _TileDivider(),
            _ToggleTile(
              icon: RiskVisuals.medium.icon,
              iconColor: RiskVisuals.medium.color,
              title: 'Medium risk alerts',
              value: prefs.mediumRiskAlerts,
              onChanged: (v) =>
                  run(context, () => controller.setMediumRiskAlerts(v)),
            ),
            const _TileDivider(),
            _ToggleTile(
              icon: RiskVisuals.low.icon,
              iconColor: RiskVisuals.low.color,
              title: 'Low risk updates',
              value: prefs.lowRiskUpdates,
              onChanged: (v) =>
                  run(context, () => controller.setLowRiskUpdates(v)),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Text('BY CONDITION', style: AppTextStylesV2.microLabel),
        const SizedBox(height: 12),
        _Card(
          children: [
            for (final entry in kNotificationConditionLabels.entries) ...[
              if (entry.key != kNotificationConditionLabels.keys.first)
                const _TileDivider(),
              _ToggleTile(
                title: entry.value,
                value: prefs.conditions[entry.key] ?? false,
                onChanged: (v) =>
                    run(context, () => controller.setCondition(entry.key, v)),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _DevicePermissionRow extends StatelessWidget {
  final VoidCallback onTap;
  const _DevicePermissionRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: AppColorsV2.violet.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColorsV2.violet.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.notifications_active_outlined,
                size: 20,
                color: AppColorsV2.violet,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Device notification permission',
                  style: AppTextStylesV2.body.copyWith(
                    color: AppColorsV2.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColorsV2.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColorsV2.glassFill,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColorsV2.stroke),
      ),
      child: Column(children: children),
    );
  }
}

class _TileDivider extends StatelessWidget {
  const _TileDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      color: Colors.white.withValues(alpha: 0.05),
      indent: 16,
      endIndent: 16,
    );
  }
}

class _ToggleTile extends StatelessWidget {
  final IconData? icon;
  final Color? iconColor;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleTile({
    required this.title,
    required this.value,
    required this.onChanged,
    this.icon,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: iconColor),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              title,
              style: AppTextStylesV2.body.copyWith(
                color: AppColorsV2.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: AppColorsV2.brandBlue,
            inactiveThumbColor: Colors.white.withValues(alpha: 0.6),
            inactiveTrackColor: Colors.white.withValues(alpha: 0.10),
          ),
        ],
      ),
    );
  }
}
