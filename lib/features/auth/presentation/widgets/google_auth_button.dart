import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:fyp_foreseeme/core/theme/app_colors.dart';
import 'package:fyp_foreseeme/core/theme/app_theme.dart';
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
    final isDark =
        AppColors.activePalette == AppColors.darkPalette ||
        Theme.of(context).brightness == Brightness.dark;

    final button = ClipRRect(
      borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.curve,
          height: AppDimensions.buttonHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.white.withValues(alpha: 0.82),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.14)
                  : const Color(0xFF006D77).withValues(alpha: 0.20),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.06),
                blurRadius: 16,
                spreadRadius: -6,
                offset: const Offset(0, 6),
              ),
            ],
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
                        isDark ? Colors.white : AppColors.textPrimary,
                      ),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SvgPicture.network(
                        'https://upload.wikimedia.org/wikipedia/commons/c/c1/Google_%22G%22_logo.svg',
                        height: 20,
                        width: 20,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        'Continue with Google',
                        style: GoogleFonts.manrope(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.1,
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.90)
                              : AppColors.textPrimary,
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
