import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/a11y.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
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
    final palette = context.fsmPalette;

    ref.listen<AuthState>(authNotifierProvider, (prev, next) {
      if (next is AuthStateError && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  color: palette.onError,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    next.message,
                    style: context.fsmText.bodyLarge?.copyWith(
                      color: palette.onError,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: palette.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ForeSeeMeRadius.sm),
            ),
            margin: const EdgeInsets.all(ForeSeeMeSpacing.xxl),
          ),
        );
      }
    });

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // ── Ambient background gradient ──────────────────────────────
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: context.fsmColors.gradients.surface,
              ),
            ),
          ),

          // ── Ambient glow orb – top-right ────────────────────────────
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
                    palette.secondary.withValues(alpha: palette.isDark ? 0.28 : 0.14),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // ── Ambient glow orb – bottom-left ──────────────────────────
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
                    palette.primary.withValues(alpha: palette.isDark ? 0.18 : 0.10),
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
                        horizontal: ForeSeeMeSpacing.gutter,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: ForeSeeMeSpacing.huge),

                          // ── Hero / Header ──────────────────────────
                          const _HeroHeader(),

                          const SizedBox(height: ForeSeeMeSpacing.xxl),

                          // ── Glassmorphic form card ─────────────────
                          _GlassFormCard(
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
                                  const SizedBox(height: ForeSeeMeSpacing.md),
                                  TextButton(
                                    onPressed: _isLoading
                                        ? null
                                        : () => context.push('/forgot-password'),
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      foregroundColor: palette.secondary,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      minimumSize: const Size(0, 48),
                                    ),
                                    child: Text(
                                      'Forgot password?',
                                      style: context.fsmText.labelMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: palette.secondary,
                                            letterSpacing: 0.2,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: ForeSeeMeSpacing.xxl),

                          // ── Primary CTA: Sign In ───────────────────
                          AppButton(
                            text: 'Sign In',
                            isLoading: _isEmailLoading,
                            onPressed: _isLoading ? null : _signIn,
                          ),

                          const SizedBox(height: ForeSeeMeSpacing.xxl),

                          // ── OR Divider ─────────────────────────────
                          Row(
                            children: [
                              Expanded(
                                child: Divider(color: palette.outlineVariant),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: ForeSeeMeSpacing.xxl,
                                ),
                                child: Text(
                                  'OR',
                                  style: context.fsmText.labelSmall?.copyWith(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.4,
                                    // WCAG AA (4.5:1): matches the "Don't have
                                    // an account?" secondary-text treatment
                                    // below rather than the fainter tertiary
                                    // tone, which fell to ~3.2:1 here.
                                    color: palette.textSecondary,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Divider(color: palette.outlineVariant),
                              ),
                            ],
                          ),

                          const SizedBox(height: ForeSeeMeSpacing.xxl),

                          // ── Google Sign-In ─────────────────────────
                          GoogleAuthButton(
                            isLoading: _isGoogleLoading,
                            onPressed: _isLoading ? null : _signInWithGoogle,
                          ),

                          const Spacer(),

                          // ── Bottom register row ────────────────────
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: ForeSeeMeSpacing.xxl,
                              top: ForeSeeMeSpacing.xxl,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  "Don't have an account?",
                                  style: context.fsmText.bodyMedium?.copyWith(
                                    fontSize: 14,
                                    color: palette.textSecondary,
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
  const _HeroHeader();

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── ForeSeeMe brand identity (logo · name · tagline) ──
        // Matches BrandLoading: same theme-aware SVG mark at the same 72px size.
        // Decorative — the "ForeSeeMe" text right below already conveys the
        // brand to screen readers.
        ExcludeSemantics(
          child: SvgPicture.asset(
            palette.isDark
                ? 'assets/branding/logo/foreseeme-icon-white.svg'
                : 'assets/branding/logo/foreseeme-icon-black.svg',
            width: 72,
            height: 72,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(height: ForeSeeMeSpacing.xxl),
        Text('ForeSeeMe', style: text.titleLarge),
        const SizedBox(height: ForeSeeMeSpacing.xs),
        Text(
          'AI-Powered Health Intelligence',
          style: text.bodyMedium?.copyWith(color: palette.textSecondary),
        ),
        const SizedBox(height: ForeSeeMeSpacing.huge),
        Semantics(
          header: true,
          child: Text(
            'Welcome back,',
            style: text.displayLarge?.copyWith(fontSize: 34),
          ),
        ),
        const SizedBox(height: ForeSeeMeSpacing.sm),
        Text(
          'Sign in to sync your health journey.',
          style: text.bodyLarge?.copyWith(color: palette.textSecondary),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Glassmorphic form card
// ─────────────────────────────────────────────────────────────────────────────

class _GlassFormCard extends StatelessWidget {
  final Widget child;

  const _GlassFormCard({required this.child});

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
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          decoration: ForeSeeMeSurface.card(context, radius: ForeSeeMeRadius.xl),
          child: child,
        ),
      ),
    );
  }
}
