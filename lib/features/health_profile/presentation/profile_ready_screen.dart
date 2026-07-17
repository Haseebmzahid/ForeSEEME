import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';

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
    final palette = context.fsmPalette;
    final text = context.fsmText;

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
                  const _ReadyIcon(),
                  const SizedBox(height: 28),
                  Semantics(
                    header: true,
                    child: Text(
                      "You're all set!",
                      textAlign: TextAlign.center,
                      style: text.displayMedium?.copyWith(fontSize: 28),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "We're now watching environmental health risk for $city.",
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(
                      color: palette.textSecondary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _hasRealConditions
                        ? "You've noted: ${conditions.join(', ')}. We'll keep that "
                              'in mind for your recommendations.'
                        : "You didn't note any chronic conditions — you can add "
                              'them anytime from your profile.',
                    textAlign: TextAlign.center,
                    style: text.bodySmall?.copyWith(
                      color: palette.textTertiary,
                    ),
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
  const _ReadyIcon();

  @override
  Widget build(BuildContext context) {
    // A success moment — the design system's success tone.
    final success = context.fsmColors.success;
    return ExcludeSemantics(
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          color: success.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(ForeSeeMeRadius.xl),
          border: Border.all(color: success.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: success.withValues(alpha: 0.25),
              blurRadius: 32,
              spreadRadius: -4,
            ),
          ],
        ),
        child: Icon(
          Icons.check_circle_outline_rounded,
          color: success,
          size: 44,
        ),
      ),
    );
  }
}

class _ContinueButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _ContinueButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    return Semantics(
      button: true,
      label: 'Continue',
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
              child: Text(
                'Continue',
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
            context.fsmColors.success.withValues(alpha: 0.10),
            palette.background,
          ],
          stops: const [0.0, 0.7],
        ),
      ),
    );
  }
}
