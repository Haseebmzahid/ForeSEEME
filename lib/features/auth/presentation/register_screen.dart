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
import 'widgets/second_factor_dialog.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _isEmailLoading = false;
  bool _isGoogleLoading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  bool get _isLoading => _isEmailLoading || _isGoogleLoading;

  Future<void> _submit() async {
    if (_isLoading || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _isEmailLoading = true);
    await ref.read(authNotifierProvider.notifier).signUp(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
          displayName: _nameCtrl.text.trim(),
        );
    if (mounted) setState(() => _isEmailLoading = false);
  }

  Future<void> _signInWithGoogle() async {
    if (_isLoading) return;
    FocusScope.of(context).unfocus();
    setState(() => _isGoogleLoading = true);
    await ref.read(authNotifierProvider.notifier).signInWithGoogle();
    if (mounted) setState(() => _isGoogleLoading = false);
  }

  Future<void> _completeSecondFactor(AuthStateSecondFactor challenge) async {
    final notifier = ref.read(authNotifierProvider.notifier);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SecondFactorDialog(
        choices: challenge.choices,
        complete: notifier.completeSecondFactor,
      ),
    );
    if (mounted) notifier.cancelSecondFactor();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;

    ref.listen<AuthState>(authNotifierProvider, (prev, next) {
      if (next is AuthStateSecondFactor && mounted) {
        _completeSecondFactor(next);
      }
      if (next is AuthStateError && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline_rounded, color: palette.onError, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    next.message,
                    style: context.fsmText.bodyLarge?.copyWith(color: palette.onError),
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
          // Ambient background gradient
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: context.fsmColors.gradients.surface,
              ),
            ),
          ),
          // Glow orb – top-left
          Positioned(
            top: -60,
            left: -80,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    palette.secondary.withValues(alpha: palette.isDark ? 0.26 : 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Glow orb – bottom-right
          Positioned(
            bottom: 80,
            right: -60,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    palette.primary.withValues(alpha: palette.isDark ? 0.16 : 0.09),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Main content
          SafeArea(
            child: AppReveal(
              child: CustomScrollView(
                physics: const ClampingScrollPhysics(),
                slivers: [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: ForeSeeMeSpacing.gutter),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: ForeSeeMeSpacing.huge),
                          // Hero header
                          const _RegisterHeroHeader(),
                          const SizedBox(height: ForeSeeMeSpacing.xxl),
                          // Glassmorphic form card
                          _GlassFormCard(
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  AppTextField(
                                    label: 'Full Name',
                                    hint: 'Haseeb',
                                    controller: _nameCtrl,
                                    prefixIcon: const Icon(Icons.person_outline_rounded),
                                    validator: (v) {
                                      if (v == null || v.trim().isEmpty) {
                                        return 'Name is required';
                                      }
                                      if (v.trim().length > 160) {
                                        return 'Enter up to 160 characters';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: ForeSeeMeSpacing.xs),
                                  AppTextField(
                                    label: 'Email',
                                    hint: 'you@example.com',
                                    controller: _emailCtrl,
                                    keyboardType: TextInputType.emailAddress,
                                    prefixIcon: const Icon(Icons.mail_outline_rounded),
                                    validator: (v) {
                                      if (v == null || v.trim().isEmpty) {
                                        return 'Email is required';
                                      }
                                      if (!RegExp(
                                        r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                                      ).hasMatch(v.trim())) {
                                        return 'Enter a valid email';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(
                                    height: ForeSeeMeSpacing.xs,
                                  ),
                                  const Text('Use at least 8 characters.'),
                                  AppTextField(
                                    label: 'Password',
                                    hint: 'Enter your password',
                                    controller: _passwordCtrl,
                                    isPassword: true,
                                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                                    validator: (v) {
                                      if (v == null || v.isEmpty) {
                                        return 'Password is required';
                                      }
                                      if (v.length < 8) {
                                        return 'Password must be at least 8 characters';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: ForeSeeMeSpacing.xs),
                                  AppTextField(
                                    label: 'Confirm Password',
                                    hint: 'Re-enter your password',
                                    controller: _confirmCtrl,
                                    isPassword: true,
                                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                                    validator: (v) {
                                      if (v == null || v.isEmpty) {
                                        return 'Please confirm your password';
                                      }
                                      if (v != _passwordCtrl.text) {
                                        return 'Passwords do not match';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: ForeSeeMeSpacing.md),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: ForeSeeMeSpacing.xxl),
                          const Text(
                            'We’ll email you a link to verify your address.',
                          ),
                          const SizedBox(height: ForeSeeMeSpacing.sm),
                          // CTA button
                          AppButton(
                            text: 'Create Account',
                            isLoading: _isEmailLoading,
                            onPressed: _isLoading ? null : _submit,
                          ),
                          const SizedBox(height: ForeSeeMeSpacing.xxl),
                          // OR Divider
                          Row(
                            children: [
                              Expanded(
                                child: Divider(color: palette.outlineVariant),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: ForeSeeMeSpacing.xxl),
                                child: Text(
                                  'OR',
                                  style: context.fsmText.labelSmall?.copyWith(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.4,
                                    // WCAG AA (4.5:1): matches the "Already
                                    // have an account?" secondary-text
                                    // treatment below rather than the fainter
                                    // tertiary tone, which fell to ~3.2:1 here.
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
                          GoogleAuthButton(
                            isLoading: _isGoogleLoading,
                            onPressed: _isLoading ? null : _signInWithGoogle,
                          ),
                          const Spacer(),
                          Padding(
                            padding: const EdgeInsets.only(
                                bottom: ForeSeeMeSpacing.xxxl, top: ForeSeeMeSpacing.huge),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Already have an account?',
                                  style: context.fsmText.bodyMedium?.copyWith(
                                    fontSize: 14,
                                    color: palette.textSecondary,
                                  ),
                                ),
                                AppButton(
                                  text: 'Login',
                                  isGhost: true,
                                  onPressed: _isLoading ? null : () => context.go('/login'),
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

// ── Hero header ──────────────────────────────────────────────────────────────

class _RegisterHeroHeader extends StatelessWidget {
  const _RegisterHeroHeader();

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
            'Create Account',
            style: text.displayLarge?.copyWith(fontSize: 34),
          ),
        ),
        const SizedBox(height: ForeSeeMeSpacing.sm),
        Text(
          'Sign up to start your health journey.',
          style: text.bodyLarge?.copyWith(color: palette.textSecondary),
        ),
      ],
    );
  }
}

// ── Glassmorphic form card ───────────────────────────────────────────────────

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
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          decoration: ForeSeeMeSurface.card(context, radius: ForeSeeMeRadius.xl),
          child: child,
        ),
      ),
    );
  }
}
