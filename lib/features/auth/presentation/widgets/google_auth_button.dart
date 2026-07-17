import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';

class GoogleAuthButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback? onPressed;

  const GoogleAuthButton({
    super.key,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = onPressed == null || isLoading;
    final palette = context.fsmPalette;

    final button = ClipRRect(
      borderRadius: ForeSeeMeRadius.control,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.curve,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: ForeSeeMeRadius.control,
            color: ForeSeeMeSurface.fill(context),
            border: Border.all(color: ForeSeeMeSurface.stroke(context)),
            boxShadow: context.fsmColors.shadows.soft,
          ),
          child: Center(
            child: isLoading
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      strokeCap: StrokeCap.round,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        palette.textPrimary,
                      ),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Decorative — the "Continue with Google" text already
                      // conveys the meaning to screen readers.
                      ExcludeSemantics(
                        child: SvgPicture.network(
                          'https://upload.wikimedia.org/wikipedia/commons/c/c1/Google_%22G%22_logo.svg',
                          height: 20,
                          width: 20,
                        ),
                      ),
                      const SizedBox(width: ForeSeeMeSpacing.sm),
                      Text(
                        'Continue with Google',
                        style: context.fsmText.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.1,
                          color: palette.textPrimary,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );

    return isDisabled ? button : PressableScale(onTap: onPressed, child: button);
  }
}
