import 'package:flutter/material.dart';
import '../theme/foreseeme_theme.dart';
import '../theme/foreseeme_tokens.dart';

/// The app's standard labelled text field.
///
/// Focus accent, fill, border, shadow, and text tones all come from the
/// ForeSeeMe design system for the ambient brightness — no hardcoded colours.
/// The validation rules, focus handling, autofill hints, and 56dp minimum tap
/// height are unchanged.
class AppTextField extends StatefulWidget {
  final String label;
  final String hint;
  final TextEditingController? controller;
  final TextInputType keyboardType;
  final FormFieldValidator<String>? validator;
  final bool isPassword;
  final Widget? prefixIcon;

  // ── Additive (defaults preserve existing behaviour) ──────────────────────────
  /// Platform autofill hints (e.g. `[AutofillHints.email]`). Enables OS/browser
  /// autofill when the field sits inside an [AutofillGroup].
  final Iterable<String>? autofillHints;

  /// Keyboard action button (e.g. `TextInputAction.done`/`.next`).
  final TextInputAction? textInputAction;

  /// Called when the user submits from the keyboard action button.
  final ValueChanged<String>? onFieldSubmitted;

  /// External focus node (for focus traversal / programmatic focus).
  final FocusNode? focusNode;

  /// When false, the field is disabled (e.g. while a request is in flight).
  final bool enabled;

  const AppTextField({
    super.key,
    required this.label,
    required this.hint,
    this.controller,
    this.keyboardType = TextInputType.text,
    this.validator,
    this.isPassword = false,
    this.prefixIcon,
    this.autofillHints,
    this.textInputAction,
    this.onFieldSubmitted,
    this.focusNode,
    this.enabled = true,
  });

  @override
  AppTextFieldState createState() => AppTextFieldState();
}

class AppTextFieldState extends State<AppTextField> {
  FocusNode? _ownedFocusNode;
  FocusNode get _focusNode =>
      widget.focusNode ?? (_ownedFocusNode ??= FocusNode());
  bool _isFocused = false;
  bool _obscureText = true;

  String? _validate(String? value) {
    final customError = widget.validator?.call(value);
    if (customError != null) return customError;

    if (!widget.isPassword || widget.label.toLowerCase() != 'password') {
      return null;
    }

    final password = value ?? '';
    if (password.isEmpty) return 'Password is required';
    if (password.length < 8) return 'Use at least 8 characters';
    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      return 'Include an uppercase letter';
    }
    if (!RegExp(r'[a-z]').hasMatch(password)) {
      return 'Include a lowercase letter';
    }
    if (!RegExp(r'\d').hasMatch(password)) {
      return 'Include a number';
    }
    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=\[\]\\;/`~]').hasMatch(password)) {
      return 'Include a special character';
    }

    return null;
  }

  @override
  void initState() {
    super.initState();
    _obscureText = widget.isPassword;
    _focusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() {
        _isFocused = _focusNode.hasFocus;
      });
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _ownedFocusNode?.dispose(); // never dispose an externally-provided node
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final accent = palette.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ForeSeeMeSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label.toUpperCase(),
            style: text.labelMedium?.copyWith(
              color: _isFocused ? accent : palette.textSecondary,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: ForeSeeMeSpacing.md),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            constraints: const BoxConstraints(minHeight: 56),
            decoration: BoxDecoration(
              borderRadius: ForeSeeMeRadius.input,
              border: Border.all(
                color: _isFocused ? accent : palette.outline,
                width: _isFocused ? 1 : 0.6,
              ),
              color: palette.surfaceContainerLow,
              boxShadow: [
                BoxShadow(
                  color: palette.shadow.withValues(
                    alpha: _isFocused ? 0.12 : 0.08,
                  ),
                  blurRadius: _isFocused ? 28 : 18,
                  offset: const Offset(0, 10),
                ),
                if (_isFocused)
                  BoxShadow(
                    color: accent.withValues(alpha: 0.18),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
              ],
            ),
            child: TextFormField(
              controller: widget.controller,
              focusNode: _focusNode,
              keyboardType: widget.keyboardType,
              validator: _validate,
              obscureText: widget.isPassword ? _obscureText : false,
              enabled: widget.enabled,
              autofillHints: widget.autofillHints,
              textInputAction: widget.textInputAction,
              onFieldSubmitted: widget.onFieldSubmitted,
              autocorrect: !widget.isPassword,
              enableSuggestions: !widget.isPassword,
              style: text.bodyLarge?.copyWith(color: palette.textPrimary),
              cursorColor: accent,
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: text.bodyLarge?.copyWith(
                  color: palette.textTertiary.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w400,
                ),
                isDense: true,
                fillColor: Colors.transparent,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                errorMaxLines: 2,
                errorStyle: text.labelMedium?.copyWith(
                  color: palette.error,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 52,
                  minHeight: 56,
                ),
                prefixIcon: widget.prefixIcon != null
                    ? IconTheme(
                        data: IconThemeData(
                          color: _isFocused ? accent : palette.textSecondary,
                        ),
                        child: widget.prefixIcon!,
                      )
                    : null,
                suffixIconConstraints: const BoxConstraints(
                  minWidth: 52,
                  minHeight: 56,
                ),
                suffixIcon: widget.isPassword
                    ? IconButton(
                        tooltip:
                            _obscureText ? 'Show password' : 'Hide password',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                        icon: Icon(
                          _obscureText
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          color: _isFocused ? accent : palette.textSecondary,
                          size: 20,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscureText = !_obscureText;
                          });
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
