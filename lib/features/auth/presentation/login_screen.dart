import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:fyp_foreseeme/core/theme/app_colors.dart';
import 'package:fyp_foreseeme/core/theme/app_theme.dart';
import 'package:fyp_foreseeme/core/widgets/app_button.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/core/widgets/app_text_field.dart';

import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_state.dart';
import 'package:fyp_foreseeme/features/auth/presentation/widgets/google_auth_button.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _isEmailLoading = false;
  bool _isGoogleLoading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  bool get _isLoading => _isEmailLoading || _isGoogleLoading;

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    setState(() => _isEmailLoading = true);

    await ref
        .read(authNotifierProvider.notifier)
        .signIn(email: _emailCtrl.text.trim(), password: _passwordCtrl.text);

    if (mounted) setState(() => _isEmailLoading = false);
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isGoogleLoading = true);

    await ref.read(authNotifierProvider.notifier).signInWithGoogle();

    if (mounted) setState(() => _isGoogleLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authNotifierProvider, (prev, next) {
      if (next is AuthStateError && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    next.message,
                    style: AppTextStyles.bodyText.copyWith(color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(AppSpacing.md),
          ),
        );
      }
    });

    final isDark =
        AppColors.activePalette == AppColors.darkPalette ||
        Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // ── Ambient background gradient ──────────────────────────────
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

          // ── Ambient teal glow orb – top-right ───────────────────────
          Positioned(
            top: -80,
            right: -60,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF006D77).withValues(alpha: isDark ? 0.28 : 0.14),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // ── Ambient teal glow orb – bottom-left ─────────────────────
          Positioned(
            bottom: 60,
            left: -80,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF28DDE8).withValues(alpha: isDark ? 0.18 : 0.10),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // ── Main content ─────────────────────────────────────────────
          SafeArea(
            child: AppReveal(
              child: CustomScrollView(
                physics: const ClampingScrollPhysics(),
                slivers: [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimensions.paddingHorizontal,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: AppSpacing.lg),

                          // ── Hero / Header ──────────────────────────
                          _HeroHeader(isDark: isDark),

                          const SizedBox(height: AppSpacing.md),

                          // ── Glassmorphic form card ─────────────────
                          _GlassFormCard(
                            isDark: isDark,
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  AppTextField(
                                    label: 'Email',
                                    hint: 'you@example.com',
                                    controller: _emailCtrl,
                                    keyboardType: TextInputType.emailAddress,
                                    prefixIcon: const Icon(
                                      Icons.mail_outline_rounded,
                                    ),
                                    validator: (v) {
                                      if (v == null || v.trim().isEmpty) {
                                        return 'Email is required';
                                      }
                                      if (!RegExp(
                                        r'^[^@]+@[^@]+\.[^@]+',
                                      ).hasMatch(v.trim())) {
                                        return 'Enter a valid email';
                                      }
                                      return null;
                                    },
                                  ),
                                  AppTextField(
                                    label: 'Password',
                                    hint: 'Enter your password',
                                    controller: _passwordCtrl,
                                    isPassword: true,
                                    prefixIcon: const Icon(
                                      Icons.lock_outline_rounded,
                                    ),
                                    validator: (v) {
                                      if (v == null || v.isEmpty) {
                                        return 'Password is required';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                  TextButton(
                                    onPressed: _isLoading
                                        ? null
                                        : () => context.push('/forgot-password'),
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      foregroundColor:
                                          const Color(0xFF28DDE8),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      minimumSize: const Size(0, 48),
                                    ),
                                    child: Text(
                                      'Forgot password?',
                                      style: AppTextStyles.caption.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF28DDE8),
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: AppSpacing.md),

                          // ── Primary CTA: Sign In ───────────────────
                          _GradientSignInButton(
                            isLoading: _isEmailLoading,
                            onPressed: _isLoading ? null : _signIn,
                          ),

                          const SizedBox(height: AppSpacing.md),

                          // ── OR Divider ─────────────────────────────
                          Row(
                            children: [
                              Expanded(
                                child: Divider(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.12)
                                      : AppColors.border,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.md,
                                ),
                                child: Text(
                                  'OR',
                                  style: GoogleFonts.manrope(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.4,
                                    // WCAG AA (4.5:1): matches the "Don't have
                                    // an account?" secondary-text treatment
                                    // below rather than the fainter tertiary
                                    // tone, which fell to ~3.2:1 here.
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.55)
                                        : AppColors.textSecondary,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Divider(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.12)
                                      : AppColors.border,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: AppSpacing.md),

                          // ── Google Sign-In ─────────────────────────
                          GoogleAuthButton(
                            isLoading: _isGoogleLoading,
                            onPressed: _isLoading ? null : _signInWithGoogle,
                          ),

                          const Spacer(),

                          // ── Bottom register row ────────────────────
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.md,
                              top: AppSpacing.md,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  "Don't have an account?",
                                  style: AppTextStyles.bodyText.copyWith(
                                    fontSize: 14,
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.55)
                                        : AppColors.textSecondary,
                                  ),
                                ),
                                AppButton(
                                  text: 'Register',
                                  isGhost: true,
                                  onPressed: _isLoading
                                      ? null
                                      : () => context.push('/register'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero / Header widget with icon glow and copy
// ─────────────────────────────────────────────────────────────────────────────

class _HeroHeader extends StatelessWidget {
  final bool isDark;
  const _HeroHeader({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── ForeSeeMe brand identity (logo · name · tagline) ──
        // Matches BrandLoading: same theme-aware SVG mark at the same 72px size.
        // Decorative — the "ForeSeeMe" text right below already conveys the
        // brand to screen readers.
        ExcludeSemantics(
          child: SvgPicture.asset(
            isDark
                ? 'assets/branding/logo/foreseeme-icon-white.svg'
                : 'assets/branding/logo/foreseeme-icon-black.svg',
            width: 72,
            height: 72,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'ForeSeeMe',
          style: AppTextStyles.heading2.copyWith(
            color: isDark ? Colors.white : AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'AI-Powered Health Intelligence',
          style: GoogleFonts.manrope(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 1.4,
            color: isDark ? const Color(0xFF8EA6BD) : AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Semantics(
          header: true,
          child: Text(
            'Welcome back,',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 34,
              fontWeight: FontWeight.w700,
              height: 1.10,
              letterSpacing: -0.5,
              color: isDark ? Colors.white : AppColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Sign in to sync your health journey.',
          style: GoogleFonts.manrope(
            fontSize: 15,
            fontWeight: FontWeight.w400,
            height: 1.55,
            color: isDark
                ? const Color(0xFF8EA6BD)
                : AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Glassmorphic form card
// ─────────────────────────────────────────────────────────────────────────────

class _GlassFormCard extends StatelessWidget {
  final bool isDark;
  final Widget child;

  const _GlassFormCard({required this.isDark, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: isDark
                ? const Color(0xFF0D1F38).withValues(alpha: 0.72)
                : Colors.white.withValues(alpha: 0.78),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.10)
                  : const Color(0xFF006D77).withValues(alpha: 0.14),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF006D77).withValues(
                  alpha: isDark ? 0.20 : 0.08,
                ),
                blurRadius: 40,
                spreadRadius: -8,
                offset: const Offset(0, 16),
              ),
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: isDark ? 0.30 : 0.06,
                ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Gradient "Sign In" primary button with teal → cyan glow
// ─────────────────────────────────────────────────────────────────────────────

class _GradientSignInButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback? onPressed;

  const _GradientSignInButton({
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
                colors: [Color(0xFF006D77), Color(0xFF28DDE8)],
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
                  color: const Color(0xFF28DDE8).withValues(alpha: 0.38),
                  blurRadius: 32,
                  spreadRadius: -6,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: const Color(0xFF006D77).withValues(alpha: 0.22),
                  blurRadius: 24,
                  spreadRadius: -8,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Center(
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  strokeCap: StrokeCap.round,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                'Sign In',
                style: GoogleFonts.manrope(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                  color: isDisabled ? AppColors.textTertiary : Colors.white,
                ),
              ),
      ),
    );

    return isDisabled ? button : PressableScale(onTap: onPressed, child: button);
  }
}
