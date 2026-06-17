import 'package:flutter/material.dart';
import 'package:fyp_foreseeme/core/widgets/app_scaffold.dart';
import 'package:fyp_foreseeme/core/theme/app_colors.dart';
import 'package:fyp_foreseeme/core/theme/app_theme.dart';

class ResourcesScreen extends StatelessWidget {
  const ResourcesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      body: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.paddingHorizontal,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.xl),
            Text('Resources', style: AppTextStyles.heading1),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Educational materials and support for your journey.',
              style: AppTextStyles.bodyText.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.menu_book_rounded,
                      size: 64,
                      color: AppColors.primary.withValues(alpha: 0.2),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text('Coming Soon', style: AppTextStyles.heading2),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'We are curating the best resources for you.',
                      style: AppTextStyles.bodyText.copyWith(
                        color: AppColors.textTertiary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
