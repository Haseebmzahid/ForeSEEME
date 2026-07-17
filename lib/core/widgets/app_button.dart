import 'package:flutter/material.dart';
import '../theme/foreseeme_theme.dart';
import '../theme/foreseeme_tokens.dart';

/// The app's primary button.
///
/// Three variants — a gradient **filled** CTA (default), an **outlined**
/// secondary, and a text **ghost** — all drawing colour, gradient, and shadow
/// from the ForeSeeMe design system for the ambient brightness. Nothing is
/// hardcoded: the CTA fill is `colors.gradients.primary`, its glow derives from
/// the `primary`/`secondary` tokens, and disabled states use surface + disabled
/// text tokens. The press-scale, loading swap, and 56dp touch target are
/// unchanged.
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
  static const double _height = 56.0;

  bool _isPressed = false;

  void _setPressed(bool value) {
    if (_isPressed == value || widget.onPressed == null || widget.isLoading) {
      return;
    }
    setState(() => _isPressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final isDisabled = widget.onPressed == null || widget.isLoading;

    if (widget.isGhost) {
      return _PressableButtonFrame(
        isPressed: _isPressed,
        onTapDown: () => _setPressed(true),
        onTapEnd: () => _setPressed(false),
        child: SizedBox(
          height: _height,
          child: TextButton(
            onPressed: isDisabled ? null : widget.onPressed,
            style: TextButton.styleFrom(
              foregroundColor: palette.primary,
              disabledForegroundColor: palette.textDisabled,
              textStyle: context.fsmText.bodyLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              shape: const RoundedRectangleBorder(
                borderRadius: ForeSeeMeRadius.control,
              ),
            ),
            child: _buildContent(context, palette.primary),
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
          height: _height,
          width: double.infinity,
          child: OutlinedButton(
            onPressed: isDisabled ? null : widget.onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: palette.textPrimary,
              disabledForegroundColor: palette.textDisabled,
              side: BorderSide(
                color: palette.outline,
                width: ForeSeeMeBorderWidth.thin,
              ),
              minimumSize: const Size.fromHeight(_height),
              shape: const RoundedRectangleBorder(
                borderRadius: ForeSeeMeRadius.control,
              ),
              overlayColor: palette.primary.withValues(alpha: 0.06),
              textStyle: context.fsmText.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            child: _buildContent(context, palette.textPrimary),
          ),
        ),
      );
    }

    return _PressableButtonFrame(
      isPressed: _isPressed,
      onTapDown: () => _setPressed(true),
      onTapEnd: () => _setPressed(false),
      child: SizedBox(
        height: _height,
        width: double.infinity,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: ForeSeeMeRadius.control,
            gradient: isDisabled ? null : context.fsmColors.gradients.primary,
            color: isDisabled ? palette.surfaceContainerHighest : null,
            border: Border.all(
              color: palette.onPrimary.withValues(alpha: isDisabled ? 0.0 : 0.14),
              width: 0.8,
            ),
            boxShadow: isDisabled
                ? []
                : [
                    BoxShadow(
                      color: palette.primary.withValues(
                        alpha: _isPressed ? 0.16 : 0.26,
                      ),
                      blurRadius: _isPressed ? 18 : 34,
                      spreadRadius: -8,
                      offset: Offset(0, _isPressed ? 6 : 14),
                    ),
                    BoxShadow(
                      color: palette.secondary.withValues(
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
              foregroundColor: palette.onPrimary,
              disabledForegroundColor: palette.textDisabled,
              padding: const EdgeInsets.symmetric(
                horizontal: ForeSeeMeSpacing.xxl,
              ),
              shape: const RoundedRectangleBorder(
                borderRadius: ForeSeeMeRadius.control,
              ),
              textStyle: context.fsmText.bodyLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            child: _buildContent(context, palette.onPrimary),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, Color contentColor) {
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

    final label = context.fsmText.bodyLarge?.copyWith(
      fontWeight: FontWeight.w800,
      color: contentColor,
    );

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
                const SizedBox(width: ForeSeeMeSpacing.md),
                Text(widget.text, style: label),
              ],
            )
          : Text(
              widget.text,
              key: const ValueKey('text-content'),
              style: label,
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
