import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:fyp_foreseeme/core/theme/app_colors.dart';
import 'package:fyp_foreseeme/core/theme/app_theme.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/core/widgets/app_text_field.dart';
import 'package:fyp_foreseeme/features/auth/presentation/password_reset_controller.dart';

// Brand accent pair used across the auth surfaces (matches the Login screen's
// liquid-glass treatment — teal → cyan glow). Works on light and dark shells.
const Color _kTeal = Color(0xFF006D77);
const Color _kCyan = Color(0xFF28DDE8);

/// Forgot Password — a premium, liquid-glass screen consistent with the Login
/// screen. Presentation only: it delegates to [PasswordResetController] (no
/// Firebase here) and renders its loading / success / error states with proper
/// autofill, focus, validation timing, animations and accessibility.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

enum _View { form, success }

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _emailFocus = FocusNode();

  // UI is driven by local state so a resend never flips away from the success
  // view; the controller is still the single source for the actual request.
  _View _view = _View.form;
  bool _submitting = false;
  bool _resending = false;
  String? _errorMessage;
  AutovalidateMode _autovalidate = AutovalidateMode.disabled;

  late final AnimationController _shakeCtrl;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _emailFocus.dispose();
    _shakeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    // Validation timing: stay pristine until the first attempt, then validate
    // live as the user corrects the field.
    if (!_formKey.currentState!.validate()) {
      setState(() => _autovalidate = AutovalidateMode.onUserInteraction);
      return;
    }
    _emailFocus.unfocus();

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    await ref
        .read(passwordResetControllerProvider.notifier)
        .sendResetEmail(_emailCtrl.text);
    if (!mounted) return;

    final state = ref.read(passwordResetControllerProvider);
    setState(() => _submitting = false);

    if (state is PasswordResetSent) {
      setState(() => _view = _View.success);
    } else if (state is PasswordResetFailure) {
      setState(() => _errorMessage = state.message);
      if (!AppMotion.reduceMotion(context)) _shakeCtrl.forward(from: 0);
    }
  }

  Future<void> _resend() async {
    if (_resending) return;
    setState(() => _resending = true);

    await ref
        .read(passwordResetControllerProvider.notifier)
        .sendResetEmail(_emailCtrl.text);
    if (!mounted) return;

    final state = ref.read(passwordResetControllerProvider);
    setState(() => _resending = false);

    if (state is PasswordResetSent) {
      _showSnack("We've sent the reset link again — check your inbox.");
    } else if (state is PasswordResetFailure) {
      _showSnack(state.message, isError: true);
    }
  }

  void _backToSignIn() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/login');
    }
  }

  /// A premium floating "glass" snackbar (used for resend feedback).
  void _showSnack(String message, {bool isError = false}) {
    final accent = isError ? AppColors.error : _kCyan;
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        margin: const EdgeInsets.all(AppSpacing.md),
        padding: EdgeInsets.zero,
        content: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1F38).withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: accent.withValues(alpha: 0.45)),
              ),
              child: Row(
                children: [
                  Icon(
                    isError
                        ? Icons.error_outline_rounded
                        : Icons.mark_email_read_rounded,
                    color: accent,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      message,
                      style: GoogleFonts.manrope(
                        fontSize: 13.5,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
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

  @override
  Widget build(BuildContext context) {
    final isDark =
        AppColors.activePalette == AppColors.darkPalette ||
        Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: true, // keyboard-aware (content scrolls)
      body: Stack(
        children: [
          _AmbientBackground(isDark: isDark),

          SafeArea(
            child: AppReveal(
              child: Stack(
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 460),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  AppDimensions.paddingHorizontal,
                                  72,
                                  AppDimensions.paddingHorizontal,
                                  AppSpacing.lg,
                                ),
                                child: AppMotion.stateSwitcher(
                                  context,
                                  _view == _View.success
                                      ? _buildSuccess(isDark)
                                      : _buildForm(isDark),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  Positioned(
                    top: 4,
                    left: 4,
                    child: _GlassBackButton(onTap: _backToSignIn),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Form view ──────────────────────────────────────────────────────────────

  Widget _buildForm(bool isDark) {
    return Column(
      key: const ValueKey('form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Hero(
          isDark: isDark,
          icon: Icons.lock_reset_rounded,
          title: 'Forgot password?',
          subtitle:
              "Enter your email and we'll send you instructions to reset your "
              'password.',
        ),
        const SizedBox(height: AppSpacing.md),

        AnimatedBuilder(
          animation: _shakeCtrl,
          builder: (context, child) {
            final v = _shakeCtrl.value;
            final dx = math.sin(v * math.pi * 5) * 10 * (1 - v);
            return Transform.translate(offset: Offset(dx, 0), child: child);
          },
          child: _GlassCard(
            isDark: isDark,
            child: AutofillGroup(
              child: Form(
                key: _formKey,
                autovalidateMode: _autovalidate,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppTextField(
                      label: 'Email',
                      hint: 'you@example.com',
                      controller: _emailCtrl,
                      focusNode: _emailFocus,
                      enabled: !_submitting,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      prefixIcon: const Icon(Icons.mail_outline_rounded),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Email is required';
                        }
                        if (!RegExp(
                          r'^[^@]+@[^@]+\.[^@]+',
                        ).hasMatch(v.trim())) {
                          return 'Enter a valid email address';
                        }
                        return null;
                      },
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: _errorMessage == null
                          ? const SizedBox(width: double.infinity)
                          : Padding(
                              padding: const EdgeInsets.only(
                                top: AppSpacing.sm,
                              ),
                              child: _InlineError(message: _errorMessage!),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: AppSpacing.md),

        _GradientButton(
          label: 'Send reset link',
          isLoading: _submitting,
          onPressed: _submitting ? null : _submit,
        ),

        const SizedBox(height: AppSpacing.md),

        _SignInRow(
          prompt: 'Remember your password?',
          isDark: isDark,
          onTap: _backToSignIn,
        ),
      ],
    );
  }

  // ── Success view ─────────────────────────────────────────────────────────--

  Widget _buildSuccess(bool isDark) {
    return Column(
      key: const ValueKey('success'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _AnimatedSuccessMark(),
        const SizedBox(height: AppSpacing.md),

        Semantics(
          header: true,
          child: Text(
            'Check your inbox',
            textAlign: TextAlign.center,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),

        Semantics(
          liveRegion: true,
          child: Text(
            kPasswordResetNeutralMessage,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyText.copyWith(
              fontSize: 15,
              height: 1.5,
              color: AppColors.textSecondary,
            ),
          ),
        ),

        if (_emailCtrl.text.trim().isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _EmailChip(email: _emailCtrl.text.trim()),
        ],

        const SizedBox(height: AppSpacing.lg),

        _GradientButton(
          label: 'Back to Sign In',
          isLoading: false,
          onPressed: _backToSignIn,
        ),
        const SizedBox(height: AppSpacing.xs),

        _ResendButton(isLoading: _resending, onPressed: _resend),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Reusable liquid-glass building blocks (consistent with the Login screen)
// ═════════════════════════════════════════════════════════════════════════════

class _AmbientBackground extends StatelessWidget {
  final bool isDark;
  const _AmbientBackground({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? const [
                          Color(0xFF0A1628),
                          Color(0xFF0D1F38),
                          Color(0xFF081220),
                        ]
                      : const [
                          Color(0xFFF0F7FF),
                          Color(0xFFE6F5F5),
                          Color(0xFFF5F0FF),
                        ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            top: -80,
            right: -60,
            child: _GlowOrb(
              size: 280,
              color: _kTeal.withValues(alpha: isDark ? 0.28 : 0.14),
            ),
          ),
          Positioned(
            bottom: 60,
            left: -80,
            child: _GlowOrb(
              size: 240,
              color: _kCyan.withValues(alpha: isDark ? 0.18 : 0.10),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  final double size;
  final Color color;
  const _GlowOrb({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, Colors.transparent]),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  final bool isDark;
  final IconData icon;
  final String title;
  final String subtitle;

  const _Hero({
    required this.isDark,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  _kCyan.withValues(alpha: 0.22),
                  _kTeal.withValues(alpha: 0.10),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
            child: Center(
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    colors: [_kTeal, _kCyan],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _kCyan.withValues(alpha: 0.40),
                      blurRadius: 18,
                      spreadRadius: -4,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Semantics(
          header: true,
          child: Text(
            title,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              height: 1.10,
              letterSpacing: -0.5,
              color: isDark ? Colors.white : AppColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: GoogleFonts.manrope(
            fontSize: 15,
            fontWeight: FontWeight.w400,
            height: 1.55,
            color: isDark ? const Color(0xFF8EA6BD) : AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _GlassCard extends StatelessWidget {
  final bool isDark;
  final Widget child;

  const _GlassCard({required this.isDark, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: isDark
                ? const Color(0xFF0D1F38).withValues(alpha: 0.72)
                : Colors.white.withValues(alpha: 0.78),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.10)
                  : _kTeal.withValues(alpha: 0.14),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: _kTeal.withValues(alpha: isDark ? 0.20 : 0.08),
                blurRadius: 40,
                spreadRadius: -8,
                offset: const Offset(0, 16),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.06),
                blurRadius: 24,
                spreadRadius: -10,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Inline, accessible error surface with a friendly title + the specific reason.
class _InlineError extends StatelessWidget {
  final String message;
  const _InlineError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.32)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded, size: 18, color: AppColors.error),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "We couldn't send the link",
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.error,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.error,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmailChip extends StatelessWidget {
  final String email;
  const _EmailChip({required this.email});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: _kTeal.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _kTeal.withValues(alpha: 0.24)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.alternate_email_rounded, size: 15, color: _kCyan),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                email,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignInRow extends StatelessWidget {
  final String prompt;
  final bool isDark;
  final VoidCallback onTap;

  const _SignInRow({
    required this.prompt,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            prompt,
            style: AppTextStyles.bodyText.copyWith(
              fontSize: 14,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.55)
                  : AppColors.textSecondary,
            ),
          ),
          TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              foregroundColor: _kCyan,
              minimumSize: const Size(0, 48),
              textStyle: AppTextStyles.bodyText.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            child: const Text('Sign In'),
          ),
        ],
      ),
    );
  }
}

/// Circular glass back button — accessible, ≥48px, consistent glass treatment.
class _GlassBackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _GlassBackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Material(
            color: Colors.white.withValues(alpha: 0.06),
            shape: CircleBorder(
              side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: IconButton(
              tooltip: 'Back to sign in',
              onPressed: onTap,
              iconSize: 22,
              color: AppColors.textPrimary,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          ),
        ),
      ),
    );
  }
}

/// Success mark — fades + drifts in for a confirmation (shared AppReveal
/// entrance, consistent with the rest of the onboarding/auth flow).
class _AnimatedSuccessMark extends StatelessWidget {
  const _AnimatedSuccessMark();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Center(
        child: AppReveal(
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.success.withValues(alpha: 0.26),
                  _kTeal.withValues(alpha: 0.10),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
            child: Center(
              child: Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [_kTeal, _kCyan],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _kCyan.withValues(alpha: 0.40),
                      blurRadius: 22,
                      spreadRadius: -4,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.mark_email_read_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Text button for "Resend", with an inline loading spinner + disabled state.
class _ResendButton extends StatelessWidget {
  final bool isLoading;
  final Future<void> Function() onPressed;

  const _ResendButton({required this.isLoading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        button: true,
        enabled: !isLoading,
        label: 'Resend password reset email',
        child: TextButton(
          onPressed: isLoading ? null : () => onPressed(),
          style: TextButton.styleFrom(
            foregroundColor: _kCyan,
            disabledForegroundColor: AppColors.textTertiary,
            minimumSize: const Size(0, 48),
            textStyle: AppTextStyles.caption.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: isLoading
                    ? const Padding(
                        key: ValueKey('spin'),
                        padding: EdgeInsets.only(right: 8),
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(_kCyan),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(key: ValueKey('empty')),
              ),
              Text(isLoading ? 'Sending…' : "Didn't get it? Resend email"),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Gradient CTA — mirrors the Login screen's primary button (press + loading)
// ═════════════════════════════════════════════════════════════════════════════

class _GradientButton extends StatelessWidget {
  final String label;
  final bool isLoading;
  // VoidCallback accepts sync handlers and `Future<void> Function()`s alike.
  final VoidCallback? onPressed;

  const _GradientButton({
    required this.label,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = onPressed == null || isLoading;

    final button = AnimatedContainer(
      duration: AppMotion.fast,
      curve: AppMotion.curve,
      height: AppDimensions.buttonHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
        gradient: isDisabled
            ? null
            : const LinearGradient(
                colors: [_kTeal, _kCyan],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
        color: isDisabled ? AppColors.surfaceHigh : null,
        border: Border.all(
          color: isDisabled
              ? Colors.transparent
              : Colors.white.withValues(alpha: 0.18),
          width: 0.8,
        ),
        boxShadow: isDisabled
            ? []
            : [
                BoxShadow(
                  color: _kCyan.withValues(alpha: 0.38),
                  blurRadius: 32,
                  spreadRadius: -6,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: _kTeal.withValues(alpha: 0.22),
                  blurRadius: 24,
                  spreadRadius: -8,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, anim) =>
              FadeTransition(opacity: anim, child: child),
          child: isLoading
              ? const SizedBox(
                  key: ValueKey('loading'),
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    strokeCap: StrokeCap.round,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Text(
                  label,
                  key: const ValueKey('label'),
                  style: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                    color: isDisabled ? AppColors.textTertiary : Colors.white,
                  ),
                ),
        ),
      ),
    );

    return Semantics(
      button: true,
      enabled: !isDisabled,
      label: isLoading ? 'Sending, please wait' : label,
      child: isDisabled ? button : PressableScale(onTap: onPressed, child: button),
    );
  }
}
