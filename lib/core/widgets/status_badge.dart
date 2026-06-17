import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../../features/medication/domain/enums/medication_enums.dart';

class StatusBadge extends StatelessWidget {
  final AdherenceStatus status;

  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    Color badgeColor;
    switch (status) {
      case AdherenceStatus.taken:
        badgeColor = AppColors.success;
        break;
      case AdherenceStatus.missed:
        badgeColor = AppColors.error;
        break;
      case AdherenceStatus.pending:
        badgeColor = AppColors.warning;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 7.0),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20.0),
        border: Border.all(color: badgeColor.withValues(alpha: 0.34), width: 1),
      ),
      child: Text(
        status.name.toUpperCase(),
        style: AppTextStyles.caption.copyWith(
          color: badgeColor,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
