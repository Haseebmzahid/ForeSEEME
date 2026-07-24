import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/core/widgets/brand_loading.dart';
import 'package:fyp_foreseeme/core/widgets/error_state.dart';
import 'package:fyp_foreseeme/core/widgets/offline_state.dart';
import 'package:fyp_foreseeme/features/alerts/domain/models/notification_preferences.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/alerts_providers.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_visuals.dart';

/// Notification preferences: per-severity and per-condition toggles that
/// directly gate the backend's alert-dispatch engine.
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.fsmPalette;
    final async = ref.watch(notificationPreferencesControllerProvider);

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
        title: Text('Notifications', style: context.fsmText.titleLarge),
      ),
      body: SafeArea(
        child: AppMotion.stateSwitcher(
          context,
          async.when(
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

    // Brightness-aware risk appearances, so the severity icons read correctly
    // in light and dark.
    final high = RiskVisuals.resolve(context, RiskLevel.high);
    final medium = RiskVisuals.resolve(context, RiskLevel.medium);
    final low = RiskVisuals.resolve(context, RiskLevel.low);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        Text(
          'Choose which risk alerts you receive. These preferences control '
          'the alerts we send you.',
          style: context.fsmText.bodyMedium?.copyWith(
            color: context.fsmPalette.textSecondary,
          ),
        ),
        const SizedBox(height: 18),
        _DevicePermissionRow(
          onTap: () => context.push('/notifications/permission'),
        ),
        const SizedBox(height: 22),
        _sectionLabel(context, 'BY SEVERITY'),
        const SizedBox(height: 12),
        _Card(
          children: [
            _ToggleTile(
              icon: high.icon,
              iconColor: high.color,
              title: 'High risk alerts',
              value: prefs.highRiskAlerts,
              onChanged: (v) =>
                  run(context, () => controller.setHighRiskAlerts(v)),
            ),
            const _TileDivider(),
            _ToggleTile(
              icon: medium.icon,
              iconColor: medium.color,
              title: 'Medium risk alerts',
              value: prefs.mediumRiskAlerts,
              onChanged: (v) =>
                  run(context, () => controller.setMediumRiskAlerts(v)),
            ),
            const _TileDivider(),
            _ToggleTile(
              icon: low.icon,
              iconColor: low.color,
              title: 'Low risk updates',
              value: prefs.lowRiskUpdates,
              onChanged: (v) =>
                  run(context, () => controller.setLowRiskUpdates(v)),
            ),
          ],
        ),
        const SizedBox(height: 22),
        _sectionLabel(context, 'BY CONDITION'),
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

/// Uppercase tracked section label.
Widget _sectionLabel(BuildContext context, String label) => Text(
  label,
  style: context.fsmText.labelSmall?.copyWith(
    letterSpacing: 1.2,
    color: context.fsmPalette.textTertiary,
  ),
);

class _DevicePermissionRow extends StatelessWidget {
  final VoidCallback onTap;
  const _DevicePermissionRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final violet = palette.tertiary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ForeSeeMeRadius.md),
        child: Ink(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: violet.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(ForeSeeMeRadius.md),
            border: Border.all(color: violet.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.notifications_active_outlined,
                size: 20,
                color: violet,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Device notification permission',
                  style: context.fsmText.bodyMedium?.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: palette.textTertiary,
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
      decoration: ForeSeeMeSurface.card(context, radius: ForeSeeMeRadius.md),
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
      color: context.fsmPalette.outlineVariant,
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
              style: context.fsmText.titleMedium?.copyWith(fontSize: 15),
            ),
          ),
          // Inherits the design system's primary via the active ColorScheme.
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
