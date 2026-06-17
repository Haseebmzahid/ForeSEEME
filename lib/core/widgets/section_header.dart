import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

const _kTeal = Color(0xFF006D77);
const _kCyan = Color(0xFF28DDE8);

class SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const SectionHeader({super.key, required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.activePalette == AppColors.darkPalette ||
        Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimensions.paddingHorizontal,
        AppSpacing.md,
        AppDimensions.paddingHorizontal,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : _kTeal.withValues(alpha: 0.08),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : _kTeal.withValues(alpha: 0.15),
              ),
              boxShadow: isDark
                  ? [
                      BoxShadow(
                        color: _kCyan.withValues(alpha: 0.15),
                        blurRadius: 10,
                        spreadRadius: -2,
                      )
                    ]
                  : [],
            ),
            child: Icon(
              icon,
              color: isDark ? _kCyan : _kTeal,
              size: 16,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            title,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : AppColors.textPrimary,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}
