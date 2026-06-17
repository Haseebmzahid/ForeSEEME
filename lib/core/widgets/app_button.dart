import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class AppButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isGhost;
  final bool isOutlined;
  final Widget? icon;

  const AppButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.isGhost = false,
    this.isOutlined = false,
    this.icon,
  }) : assert(!(isGhost && isOutlined), "Cannot be both ghost and outlined");

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _isPressed = false;

  void _setPressed(bool value) {
    if (_isPressed == value || widget.onPressed == null || widget.isLoading) {
      return;
    }
    setState(() => _isPressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final isDisabled = widget.onPressed == null || widget.isLoading;

    if (widget.isGhost) {
      return _PressableButtonFrame(
        isPressed: _isPressed,
        onTapDown: () => _setPressed(true),
        onTapEnd: () => _setPressed(false),
        child: SizedBox(
          height: AppDimensions.buttonHeight,
          child: TextButton(
            onPressed: isDisabled ? null : widget.onPressed,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.accent,
              disabledForegroundColor: AppColors.textTertiary,
              textStyle: AppTextStyles.bodyText.copyWith(
                fontWeight: FontWeight.w700,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
              ),
            ),
            child: _buildContent(AppColors.accent),
          ),
        ),
      );
    }

    if (widget.isOutlined) {
      return _PressableButtonFrame(
        isPressed: _isPressed,
        onTapDown: () => _setPressed(true),
        onTapEnd: () => _setPressed(false),
        child: SizedBox(
          height: AppDimensions.buttonHeight,
          width: double.infinity,
          child: OutlinedButton(
            onPressed: isDisabled ? null : widget.onPressed,
            style: Theme.of(context).outlinedButtonTheme.style?.copyWith(
              overlayColor: WidgetStatePropertyAll(
                AppColors.accent.withValues(alpha: 0.06),
              ),
            ),
            child: _buildContent(AppColors.textPrimary),
          ),
        ),
      );
    }

    return _PressableButtonFrame(
      isPressed: _isPressed,
      onTapDown: () => _setPressed(true),
      onTapEnd: () => _setPressed(false),
      child: SizedBox(
        height: AppDimensions.buttonHeight,
        width: double.infinity,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
            gradient: isDisabled ? null : AppGradients.primaryAction,
            color: isDisabled ? AppColors.surfaceHigh : null,
            border: Border.all(
              color: Colors.white.withValues(alpha: isDisabled ? 0.04 : 0.14),
              width: 0.8,
            ),
            boxShadow: isDisabled
                ? []
                : [
                    BoxShadow(
                      color: AppColors.accentVariant.withValues(
                        alpha: _isPressed ? 0.14 : 0.24,
                      ),
                      blurRadius: _isPressed ? 18 : 34,
                      spreadRadius: -8,
                      offset: Offset(0, _isPressed ? 6 : 14),
                    ),
                    BoxShadow(
                      color: AppColors.accent.withValues(
                        alpha: _isPressed ? 0.08 : 0.16,
                      ),
                      blurRadius: _isPressed ? 16 : 28,
                      spreadRadius: -10,
                      offset: Offset(0, _isPressed ? 3 : 8),
                    ),
                  ],
          ),
          child: ElevatedButton(
            onPressed: isDisabled ? null : widget.onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              disabledBackgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              foregroundColor: Colors.white,
              disabledForegroundColor: AppColors.textTertiary,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
              ),
              textStyle: AppTextStyles.bodyText.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            child: _buildContent(Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(Color contentColor) {
    if (widget.isLoading) {
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: SizedBox(
          key: const ValueKey('loading'),
          height: 22,
          width: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            strokeCap: StrokeCap.round,
            valueColor: AlwaysStoppedAnimation<Color>(contentColor),
          ),
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: widget.icon != null
          ? Row(
              key: const ValueKey('icon-content'),
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                IconTheme(
                  data: IconThemeData(color: contentColor, size: 20),
                  child: widget.icon!,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  widget.text,
                  style: AppTextStyles.bodyText.copyWith(
                    fontWeight: FontWeight.w800,
                    color: contentColor,
                  ),
                ),
              ],
            )
          : Text(
              widget.text,
              key: const ValueKey('text-content'),
              style: AppTextStyles.bodyText.copyWith(
                fontWeight: FontWeight.w800,
                color: contentColor,
              ),
            ),
    );
  }
}

class _PressableButtonFrame extends StatelessWidget {
  final bool isPressed;
  final VoidCallback onTapDown;
  final VoidCallback onTapEnd;
  final Widget child;

  const _PressableButtonFrame({
    required this.isPressed,
    required this.onTapDown,
    required this.onTapEnd,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => onTapDown(),
      onTapUp: (_) => onTapEnd(),
      onTapCancel: onTapEnd,
      child: AnimatedScale(
        scale: isPressed ? 0.985 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: child,
      ),
    );
  }
}
