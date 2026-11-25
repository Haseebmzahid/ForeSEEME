import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/a11y.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/core/widgets/app_button.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/core/widgets/app_text_field.dart';
import 'package:fyp_foreseeme/features/auth/presentation/password_reset_controller.dart';

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
    final palette = context.fsmPalette;
    final accent = isError ? palette.error : palette.secondary;
    final sigma = A11y.blurSigma(context, sigma: 18);
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        margin: const EdgeInsets.all(ForeSeeMeSpacing.xxl),
        padding: EdgeInsets.zero,
        content: ClipRRect(
          borderRadius: BorderRadius.circular(ForeSeeMeRadius.md),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: palette.inverseSurface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(ForeSeeMeRadius.md),
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
                      style: context.fsmText.bodyMedium?.copyWith(
                        fontSize: 13.5,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                        color: palette.onInverseSurface,
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
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: true, // keyboard-aware (content scrolls)
      body: Stack(
        children: [
          const _AmbientBackground(),

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
                                  ForeSeeMeSpacing.gutter,
                                  72,
                                  ForeSeeMeSpacing.gutter,
                                  ForeSeeMeSpacing.huge,
                                ),
                                child: AppMotion.stateSwitcher(
                                  context,
                                  _view == _View.success
                                      ? _buildSuccess()
                                      : _buildForm(),
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

  Widget _buildForm() {
    return Column(
      key: const ValueKey('form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Hero(
          icon: Icons.lock_reset_rounded,
          title: 'Forgot password?',
          subtitle:
              "Enter your email and we'll send you instructions to reset your "
              'password.',
        ),
        const SizedBox(height: ForeSeeMeSpacing.xxl),

        AnimatedBuilder(
          animation: _shakeCtrl,
          builder: (context, child) {
            final v = _shakeCtrl.value;
            final dx = math.sin(v * math.pi * 5) * 10 * (1 - v);
            return Transform.translate(offset: Offset(dx, 0), child: child);
          },
          child: _GlassCard(
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
                          r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                        ).hasMatch(v.trim())) {
                          return 'Enter a valid email address';
                        }
                        return null;
                      },
                    ),
                    AnimatedSize(
                      duration: AppMotion.medium,
                      curve: AppMotion.curve,
                      alignment: Alignment.topCenter,
                      child: _errorMessage == null
                          ? const SizedBox(width: double.infinity)
                          : Padding(
                              padding: const EdgeInsets.only(
                                top: ForeSeeMeSpacing.sm,
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

        const SizedBox(height: ForeSeeMeSpacing.xxl),

        AppButton(
          text: 'Send reset link',
          isLoading: _submitting,
          onPressed: _submitting ? null : _submit,
        ),

        const SizedBox(height: ForeSeeMeSpacing.xxl),

        _SignInRow(
          prompt: 'Remember your password?',
          onTap: _backToSignIn,
        ),
      ],
    );
  }

  // ── Success view ─────────────────────────────────────────────────────────--

  Widget _buildSuccess() {
    final palette = context.fsmPalette;
    return Column(
      key: const ValueKey('success'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _AnimatedSuccessMark(),
        const SizedBox(height: ForeSeeMeSpacing.xxl),

        Semantics(
          header: true,
          child: Text(
            'Check your inbox',
            textAlign: TextAlign.center,
            style: context.fsmText.headlineLarge?.copyWith(fontSize: 26),
          ),
        ),
        const SizedBox(height: ForeSeeMeSpacing.md),

        Semantics(
          liveRegion: true,
          child: Text(
            kPasswordResetNeutralMessage,
            textAlign: TextAlign.center,
            style: context.fsmText.bodyLarge?.copyWith(
              fontSize: 15,
              height: 1.5,
              color: palette.textSecondary,
            ),
          ),
        ),

        if (_emailCtrl.text.trim().isNotEmpty) ...[
          const SizedBox(height: ForeSeeMeSpacing.xxl),
          _EmailChip(email: _emailCtrl.text.trim()),
        ],

        const SizedBox(height: ForeSeeMeSpacing.huge),

        AppButton(
          text: 'Back to Sign In',
          onPressed: _backToSignIn,
        ),
        const SizedBox(height: ForeSeeMeSpacing.xs),

        _ResendButton(isLoading: _resending, onPressed: _resend),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Reusable liquid-glass building blocks (consistent with the Login screen)
// ═════════════════════════════════════════════════════════════════════════════

class _AmbientBackground extends StatelessWidget {
  const _AmbientBackground();

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    return ExcludeSemantics(
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: context.fsmColors.gradients.surface,
              ),
            ),
          ),
          Positioned(
            top: -80,
            right: -60,
            child: _GlowOrb(
              size: 280,
              color: palette.secondary.withValues(alpha: palette.isDark ? 0.28 : 0.14),
            ),
          ),
          Positioned(
            bottom: 60,
            left: -80,
            child: _GlowOrb(
              size: 240,
              color: palette.primary.withValues(alpha: palette.isDark ? 0.18 : 0.10),
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
  final IconData icon;
  final String title;
  final String subtitle;

  const _Hero({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
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
                  palette.secondary.withValues(alpha: 0.22),
                  palette.primary.withValues(alpha: 0.10),
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
                  borderRadius: BorderRadius.circular(ForeSeeMeRadius.xs),
                  gradient: context.fsmColors.gradients.primary,
                  boxShadow: [
                    BoxShadow(
                      color: palette.primary.withValues(alpha: 0.40),
                      blurRadius: 18,
                      spreadRadius: -4,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(icon, color: palette.onPrimary, size: 20),
              ),
            ),
          ),
        ),
        const SizedBox(height: ForeSeeMeSpacing.xxl),
        Semantics(
          header: true,
          child: Text(
            title,
            style: text.displayLarge?.copyWith(fontSize: 32),
          ),
        ),
        const SizedBox(height: ForeSeeMeSpacing.sm),
        Text(
          subtitle,
          style: text.bodyLarge?.copyWith(color: palette.textSecondary),
        ),
      ],
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;

  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    // Reduced-transparency fallback (audit M4): under high contrast the blur
    // drops and ForeSeeMeSurface makes the fill opaque with a stronger border.
    final sigma = A11y.blurSigma(context, sigma: 24);
    return ClipRRect(
      borderRadius: BorderRadius.circular(ForeSeeMeRadius.xl),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          decoration: ForeSeeMeSurface.card(context, radius: ForeSeeMeRadius.xl),
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
    final palette = context.fsmPalette;
    final text = context.fsmText;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: palette.error.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(ForeSeeMeRadius.sm),
          border: Border.all(color: palette.error.withValues(alpha: 0.32)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded, size: 18, color: palette.error),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "We couldn't send the link",
                    style: text.labelMedium?.copyWith(
                      color: palette.error,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    style: text.labelMedium?.copyWith(
                      color: palette.error,
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
    final palette = context.fsmPalette;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: palette.secondary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(ForeSeeMeRadius.full),
          border: Border.all(color: palette.secondary.withValues(alpha: 0.24)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.alternate_email_rounded, size: 15, color: palette.secondary),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                email,
                overflow: TextOverflow.ellipsis,
                style: context.fsmText.labelMedium?.copyWith(
                  color: palette.textPrimary,
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
  final VoidCallback onTap;

  const _SignInRow({required this.prompt, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            prompt,
            style: context.fsmText.bodyMedium?.copyWith(
              fontSize: 14,
              color: palette.textSecondary,
            ),
          ),
          TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              foregroundColor: palette.secondary,
              minimumSize: const Size(0, 48),
              textStyle: context.fsmText.bodyLarge?.copyWith(
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
    final palette = context.fsmPalette;
    final sigma = A11y.blurSigma(context, sigma: 12);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: Material(
            color: ForeSeeMeSurface.fill(context),
            shape: CircleBorder(
              side: BorderSide(color: ForeSeeMeSurface.stroke(context)),
            ),
            child: IconButton(
              tooltip: 'Back to sign in',
              onPressed: onTap,
              iconSize: 22,
              color: palette.textPrimary,
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
    final palette = context.fsmPalette;
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
                  palette.success.withValues(alpha: 0.26),
                  palette.secondary.withValues(alpha: 0.10),
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
                  gradient: context.fsmColors.gradients.primary,
                  boxShadow: [
                    BoxShadow(
                      color: palette.primary.withValues(alpha: 0.40),
                      blurRadius: 22,
                      spreadRadius: -4,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.mark_email_read_rounded,
                  color: palette.onPrimary,
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
    final palette = context.fsmPalette;
    return Center(
      child: Semantics(
        button: true,
        enabled: !isLoading,
        label: 'Resend password reset email',
        child: TextButton(
          onPressed: isLoading ? null : () => onPressed(),
          style: TextButton.styleFrom(
            foregroundColor: palette.secondary,
            disabledForegroundColor: palette.textDisabled,
            minimumSize: const Size(0, 48),
            textStyle: context.fsmText.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: isLoading
                    ? Padding(
                        key: const ValueKey('spin'),
                        padding: const EdgeInsets.only(right: 8),
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              palette.secondary,
                            ),
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
