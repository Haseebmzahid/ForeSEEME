import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';

/// Shared presentation primitives for the Medication + Daily Check-In modules,
/// so both read as one family and neither duplicates the styling.
///
/// All colour comes from the ForeSeeMe design system for the ambient brightness.

/// The modules' primary CTA: a gradient pill with a press-scale, drawing its
/// fill from `gradients.primary` and its glow from the primary token.
class MedGradientButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  /// Shows a spinner in place of the label while a save is in flight.
  final bool isLoading;

  const MedGradientButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  @override
  State<MedGradientButton> createState() => _MedGradientButtonState();
}

class _MedGradientButtonState extends State<MedGradientButton> {
  bool _isPressed = false;

  void _set(bool value) {
    if (_isPressed == value || widget.isLoading) return;
    setState(() => _isPressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _isPressed ? 0.975 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 56,
            decoration: BoxDecoration(
              borderRadius: ForeSeeMeRadius.control,
              gradient: context.fsmColors.gradients.primary,
              border: Border.all(
                color: palette.onPrimary.withValues(alpha: 0.18),
                width: ForeSeeMeBorderWidth.hairline,
              ),
              boxShadow: [
                BoxShadow(
                  color: palette.primary.withValues(
                    alpha: _isPressed ? 0.20 : 0.36,
                  ),
                  blurRadius: _isPressed ? 18 : 30,
                  spreadRadius: -6,
                  offset: Offset(0, _isPressed ? 4 : 10),
                ),
              ],
            ),
            child: Center(
              child: widget.isLoading
                  ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        strokeCap: StrokeCap.round,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          palette.onPrimary,
                        ),
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(widget.icon, color: palette.onPrimary, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          widget.label,
                          style: context.fsmText.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                            color: palette.onPrimary,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared haloed glyph for the Medication / Check-In empty states, so both read
/// as one family. [accent] defaults to the brand primary.
class MedEmptyGlyph extends StatelessWidget {
  final IconData icon;
  final Color? accent;

  const MedEmptyGlyph({super.key, required this.icon, this.accent});

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final tint = accent ?? palette.primary;
    return ExcludeSemantics(
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              tint.withValues(alpha: 0.18),
              tint.withValues(alpha: 0.06),
              Colors.transparent,
            ],
            stops: const [0.0, 0.55, 1.0],
          ),
        ),
        child: Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(ForeSeeMeRadius.md),
              gradient: LinearGradient(
                colors: [tint, tint.withValues(alpha: 0.72)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: tint.withValues(alpha: 0.30),
                  blurRadius: 18,
                  spreadRadius: -4,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(icon, color: palette.onPrimary, size: 28),
          ),
        ),
      ),
    );
  }
}
