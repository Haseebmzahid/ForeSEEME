import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/app_design_v2.dart';
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
    final isBusy = ref.watch(alertsControllerProvider).isLoading;

    return Scaffold(
      backgroundColor: AppColorsV2.shell,
      body: Stack(
        children: [
          const Positioned.fill(child: _Background()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  _BellIcon(),
                  const SizedBox(height: 28),
                  Semantics(
                    header: true,
                    child: Text(
                      'Stay ahead of risk',
                      textAlign: TextAlign.center,
                      style: AppTextStylesV2.headline.copyWith(fontSize: 28),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'ForeSeeMe watches your city’s weather and air quality, and '
                    'lets you know when environmental health risk rises — so you '
                    'don’t have to check. Allowing notifications turns these '
                    'alerts on; you can change them anytime in Settings.',
                    textAlign: TextAlign.center,
                    style: AppTextStylesV2.body.copyWith(height: 1.5),
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
                      style: AppTextStylesV2.body.copyWith(
                        color: AppColorsV2.textTertiary,
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
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: AppColorsV2.violet.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColorsV2.violet.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: AppColorsV2.violet.withValues(alpha: 0.25),
            blurRadius: 32,
            spreadRadius: -4,
          ),
        ],
      ),
      child: const Icon(
        Icons.notifications_active_outlined,
        color: AppColorsV2.violet,
        size: 44,
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
          const Icon(
            Icons.check_circle_outline_rounded,
            size: 18,
            color: AppColorsV2.riskLow,
          ),
          const SizedBox(width: 10),
          Text(label, style: AppTextStylesV2.body),
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          height: 56,
          decoration: BoxDecoration(
            gradient: AppGradientsV2.brand,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColorsV2.brandViolet.withValues(alpha: 0.4),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    'Allow notifications',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
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
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.5),
          radius: 1.1,
          colors: [Color(0x1A7C6BFF), AppColorsV2.shell],
          stops: [0.0, 0.7],
        ),
      ),
    );
  }
}
