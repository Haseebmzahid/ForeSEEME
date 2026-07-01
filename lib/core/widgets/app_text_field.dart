import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label.toUpperCase(),
            style: AppTextStyles.caption.copyWith(
              color: _isFocused ? AppColors.accent : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            constraints: const BoxConstraints(minHeight: 56),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppDimensions.inputRadius),
              border: Border.all(
                color: _isFocused ? AppColors.borderFocus : AppColors.border,
                width: _isFocused ? 1 : 0.6,
              ),
              color: AppColors.surfaceHigh.withValues(alpha: 0.82),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: _isFocused ? 0.28 : 0.2,
                  ),
                  blurRadius: _isFocused ? 28 : 18,
                  offset: const Offset(0, 10),
                ),
                if (_isFocused)
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.18),
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
              style: AppTextStyles.bodyText.copyWith(
                color: AppColors.textPrimary,
              ),
              cursorColor: AppColors.accent,
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: AppTextStyles.bodyText.copyWith(
                  color: AppColors.textTertiary.withValues(alpha: 0.72),
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
                errorStyle: AppTextStyles.caption.copyWith(
                  color: AppColors.error,
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
                          color: _isFocused
                              ? AppColors.accent
                              : AppColors.textSecondary,
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
                          color: _isFocused
                              ? AppColors.accent
                              : AppColors.textSecondary,
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
