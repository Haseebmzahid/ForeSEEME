import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/app_design_v2.dart';

/// One-time "you're set" confirmation shown right after first-time profile
/// setup succeeds (S6C-04), before the notification permission pre-prompt
/// (S6C-02). Pure presentation — the city and conditions it shows are the
/// real values the user just saved (passed in directly, not re-fetched or
/// guessed), and it never claims specific diseases are monitored: which
/// diseases actually have data for a city is derived from historical
/// `riskEstimates`, not knowable at profile-save time, so inventing names
/// here would violate the app's no-fabricated-claims rule.
class ProfileReadyScreen extends StatelessWidget {
  final String city;
  final List<String> conditions;

  const ProfileReadyScreen({
    super.key,
    required this.city,
    required this.conditions,
  });

  bool get _hasRealConditions =>
      conditions.isNotEmpty &&
      !(conditions.length == 1 && conditions.single == 'None');

  @override
  Widget build(BuildContext context) {
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
                  _ReadyIcon(),
                  const SizedBox(height: 28),
                  Text(
                    "You're all set!",
                    textAlign: TextAlign.center,
                    style: AppTextStylesV2.headline.copyWith(fontSize: 28),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "We're now watching environmental health risk for $city.",
                    textAlign: TextAlign.center,
                    style: AppTextStylesV2.body.copyWith(height: 1.5),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _hasRealConditions
                        ? "You've noted: ${conditions.join(', ')}. We'll keep that "
                              'in mind for your recommendations.'
                        : "You didn't note any chronic conditions — you can add "
                              'them anytime from your profile.',
                    textAlign: TextAlign.center,
                    style: AppTextStylesV2.caption,
                  ),
                  const Spacer(flex: 3),
                  _ContinueButton(
                    onPressed: () =>
                        context.pushReplacement('/notifications/permission'),
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
}

class _ReadyIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: AppColorsV2.riskLow.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColorsV2.riskLow.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: AppColorsV2.riskLow.withValues(alpha: 0.25),
            blurRadius: 32,
            spreadRadius: -4,
          ),
        ],
      ),
      child: const Icon(
        Icons.check_circle_outline_rounded,
        color: AppColorsV2.riskLow,
        size: 44,
      ),
    );
  }
}

class _ContinueButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _ContinueButton({required this.onPressed});

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
          child: const Center(
            child: Text(
              'Continue',
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
          colors: [Color(0x1A35C28A), AppColorsV2.shell],
          stops: [0.0, 0.7],
        ),
      ),
    );
  }
}
