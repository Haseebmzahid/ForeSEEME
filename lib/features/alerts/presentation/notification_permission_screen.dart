import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/core/widgets/medical_disclaimer.dart';
import 'package:fyp_foreseeme/features/alerts/domain/models/notification_permission_status.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/alerts_providers.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';

/// One-time notification-permission prompt (Sprint 3, Prompt 7). On Allow it
/// requests permission and captures the FCM token; declining returns gracefully.
class NotificationPermissionScreen extends ConsumerWidget {
  const NotificationPermissionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final isBusy = ref.watch(alertsControllerProvider).isLoading;

    return Scaffold(
      backgroundColor: palette.background,
      body: Stack(
        children: [
          const Positioned.fill(child: _Background()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  const _BellIcon(),
                  const SizedBox(height: 28),
                  Semantics(
                    header: true,
                    child: Text(
                      'Stay ahead of risk',
                      textAlign: TextAlign.center,
                      style: text.displayMedium?.copyWith(fontSize: 28),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'ForeSeeMe watches your city’s weather and air quality, and '
                    'lets you know when environmental health risk rises — so you '
                    'don’t have to check. Allowing notifications turns these '
                    'alerts on; you can change them anytime in Settings.',
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(
                      color: palette.textSecondary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 26),
                  const _Benefit('Timely high-risk warnings'),
                  const _Benefit('Fully customizable in settings'),
                  const _Benefit('No spam, ever'),
                  const SizedBox(height: 22),
                  // Sets expectations honestly at the consent point: these are
                  // environmental risk estimates, not a medical diagnosis.
                  const MedicalDisclaimer.inline(),
                  const Spacer(flex: 3),
                  _AllowButton(
                    busy: isBusy,
                    onPressed: isBusy ? null : () => _allow(context, ref),
                  ),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: isBusy ? null : () => context.pop(),
                    child: Text(
                      'Maybe later',
                      style: text.bodyMedium?.copyWith(
                        color: palette.textTertiary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _allow(BuildContext context, WidgetRef ref) async {
    final user = ref.read(authStateProvider).value;
    if (user == null) {
      context.pop();
      return;
    }

    String message;
    try {
      final status = await ref
          .read(alertsControllerProvider.notifier)
          .enableNotifications(user.uid);
      message = status.isGranted
          ? 'Notifications enabled.'
          : 'No problem — you can enable alerts anytime in Settings.';
    } catch (_) {
      message =
          'Could not enable notifications. You can try again in Settings.';
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    context.pop();
  }
}

class _BellIcon extends StatelessWidget {
  const _BellIcon();

  @override
  Widget build(BuildContext context) {
    final violet = context.fsmPalette.tertiary;
    return ExcludeSemantics(
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          color: violet.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(ForeSeeMeRadius.xl),
          border: Border.all(color: violet.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: violet.withValues(alpha: 0.25),
              blurRadius: 32,
              spreadRadius: -4,
            ),
          ],
        ),
        child: Icon(
          Icons.notifications_active_outlined,
          color: violet,
          size: 44,
        ),
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  final String label;
  const _Benefit(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            size: 18,
            color: context.fsmColors.success,
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: context.fsmText.bodyMedium?.copyWith(
              color: context.fsmPalette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _AllowButton extends StatelessWidget {
  final bool busy;
  final VoidCallback? onPressed;

  const _AllowButton({required this.busy, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    return Semantics(
      button: true,
      label: 'Allow notifications',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(ForeSeeMeRadius.md),
          child: Ink(
            height: 56,
            decoration: BoxDecoration(
              gradient: context.fsmColors.gradients.brand,
              borderRadius: BorderRadius.circular(ForeSeeMeRadius.md),
              boxShadow: [
                BoxShadow(
                  color: palette.tertiary.withValues(alpha: 0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Center(
              child: busy
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        strokeCap: StrokeCap.round,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          palette.onPrimary,
                        ),
                      ),
                    )
                  : Text(
                      'Allow notifications',
                      style: context.fsmText.bodyLarge?.copyWith(
                        color: palette.onPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Background extends StatelessWidget {
  const _Background();

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.5),
          radius: 1.1,
          colors: [
            palette.tertiary.withValues(alpha: 0.10),
            palette.background,
          ],
          stops: const [0.0, 0.7],
        ),
      ),
    );
  }
}
