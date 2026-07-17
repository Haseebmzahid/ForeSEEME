import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/a11y.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/core/theme/theme_provider.dart';
import 'package:fyp_foreseeme/features/admin/presentation/admin_providers.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/medication/presentation/adherence_notifier.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.fsmPalette;
    final user = ref.watch(authStateProvider).value;

    return Scaffold(
      backgroundColor: palette.background,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(
          'ForeSeeMe',
          style: context.fsmText.titleLarge?.copyWith(
            fontSize: 22,
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.notifications_none_rounded,
              color: palette.onSurfaceVariant,
            ),
            tooltip: 'Alerts',
            onPressed: () {},
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          // Ambient design-system background gradient
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: context.fsmColors.gradients.surface,
              ),
            ),
          ),
          // Glow orb behind avatar
          Positioned(
            top: 60,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      palette.primary.withValues(
                        alpha: palette.isDark ? 0.15 : 0.10,
                      ),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 20.0,
              ),
              child: Column(
                children: [
                  // Hero Profile Section
                  _ProfileHeroSection(
                    name: user?.displayName ?? 'Patient User',
                    email: user?.email ?? 'patient@foreseeme.com',
                  ),
                  const SizedBox(height: 32),

                  // Health Overview
                  const _HealthOverviewSection(),
                  const SizedBox(height: 32),

                  // Settings & Preferences
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'SETTINGS & PREFERENCES',
                      style: _sectionLabelStyle(context),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Theme Switcher
                  const _PremiumThemeSwitcher(),
                  const SizedBox(height: 16),

                  // Settings List
                  _GlassContainer(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _SettingsTile(
                          icon: Icons.health_and_safety_outlined,
                          title: 'Health Profile',
                          subtitle: 'Edit your medical history',
                          onTap: () => context.push(
                            '/health-profile',
                            extra: {'isEditMode': true},
                          ),
                        ),
                        const _Divider(),
                        _SettingsTile(
                          icon: Icons.notifications_outlined,
                          title: 'Notifications',
                          subtitle: 'Manage push alerts',
                          onTap: () => context.push('/notifications/settings'),
                        ),
                        const _Divider(),
                        _SettingsTile(
                          icon: Icons.alarm_outlined,
                          title: 'Reminders',
                          subtitle: 'Dosage & check-ups',
                          onTap: () {},
                        ),
                        const _Divider(),
                        _SettingsTile(
                          icon: Icons.lock_outline_rounded,
                          title: 'Privacy',
                          subtitle: 'Data & permissions',
                          onTap: () {},
                        ),
                        const _Divider(),
                        _SettingsTile(
                          icon: Icons.help_outline_rounded,
                          title: 'Help Center',
                          subtitle: 'FAQs & Support',
                          onTap: () {},
                        ),
                        const _Divider(),
                        _SettingsTile(
                          icon: Icons.info_outline_rounded,
                          title: 'About',
                          subtitle: 'Version 2.4.1',
                          onTap: () {},
                          showTrailing: false,
                        ),
                      ],
                    ),
                  ),
                  // Operator-only: manual risk override (Sprint 5, Prompt 13).
                  // Shown only when the signed-in user carries the admin claim;
                  // Firestore rules enforce it server-side regardless.
                  if (ref.watch(isAdminProvider).value ?? false) ...[
                    const SizedBox(height: 16),
                    _GlassContainer(
                      padding: EdgeInsets.zero,
                      child: _SettingsTile(
                        icon: Icons.admin_panel_settings_outlined,
                        title: 'Risk Override',
                        subtitle: 'Operator: correct a stale/wrong estimate',
                        onTap: () => context.push('/admin/risk-override'),
                        showTrailing: true,
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),

                  // Log Out Button
                  _LogoutButton(
                    onPressed: () {
                      ref.read(authNotifierProvider.notifier).signOut();
                    },
                  ),
                  const SizedBox(height: 16),

                  // Delete Account
                  TextButton(
                    onPressed: () {},
                    child: Text(
                      'DELETE ACCOUNT',
                      style: context.fsmText.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                        color: palette.error,
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Uppercase tracked section label used between Profile sections.
TextStyle? _sectionLabelStyle(BuildContext context) =>
    context.fsmText.labelSmall?.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.5,
      color: context.fsmPalette.textTertiary,
    );

// ── Hero Section ─────────────────────────────────────────────────────────────

class _ProfileHeroSection extends StatelessWidget {
  final String name;
  final String email;

  const _ProfileHeroSection({required this.name, required this.email});

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;

    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomRight,
          children: [
            Container(
              width: 110,
              height: 110,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [palette.primary, palette.secondary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: palette.primary.withValues(alpha: 0.3),
                    blurRadius: 24,
                    spreadRadius: -4,
                  ),
                ],
              ),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: palette.surface,
                ),
                child: Center(
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'P',
                    style: text.displayMedium?.copyWith(fontSize: 40),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 4,
              right: -4,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: palette.primary,
                  border: Border.all(color: palette.surface, width: 3),
                ),
                child: Icon(
                  Icons.edit_rounded,
                  color: palette.onPrimary,
                  size: 16,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          name,
          style: text.displayMedium?.copyWith(fontSize: 26),
        ),
        const SizedBox(height: 4),
        Text(
          email,
          style: text.bodyMedium?.copyWith(color: palette.textSecondary),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: palette.secondary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(ForeSeeMeRadius.full),
            border: Border.all(color: palette.secondary.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: palette.secondary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'PREMIUM HEALTH TRACKING',
                style: text.labelSmall?.copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: palette.secondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Health Overview ──────────────────────────────────────────────────────────

class _HealthOverviewSection extends ConsumerWidget {
  const _HealthOverviewSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.fsmPalette;
    final medicationsAsync = ref.watch(medicationsStreamProvider);
    final activeMedsCount = medicationsAsync.maybeWhen(
      data: (meds) => meds.where((m) => m.isActive).length,
      orElse: () => 0,
    );

    return _GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.health_and_safety_rounded,
                color: palette.primary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text('HEALTH OVERVIEW', style: _sectionLabelStyle(context)),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _OverviewCard(
                  title: 'Medications',
                  value: activeMedsCount.toString(),
                  badge: 'Active',
                  badgeColor: palette.secondary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _OverviewCard(title: 'Adherence', value: '94', suffix: '%'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _OverviewCard(
                  title: 'Reminders',
                  value: '5',
                  suffix: 'Today',
                  suffixIsSubtext: true,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _OverviewCard(
                  title: 'Streak',
                  value: '14',
                  valueColor: palette.primary,
                  suffix: 'Days',
                  suffixIsSubtext: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  final String title;
  final String value;
  final Color? valueColor;
  final String? suffix;
  final bool suffixIsSubtext;
  final String? badge;
  final Color? badgeColor;

  const _OverviewCard({
    required this.title,
    required this.value,
    this.valueColor,
    this.suffix,
    this.suffixIsSubtext = false,
    this.badge,
    this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surfaceContainerLow,
        borderRadius: BorderRadius.circular(ForeSeeMeRadius.md),
        border: Border.all(color: palette.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: text.bodyMedium?.copyWith(
              fontSize: 13,
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: text.displayMedium?.copyWith(
                  fontSize: 32,
                  color: valueColor ?? palette.textPrimary,
                  letterSpacing: -1.0,
                ),
              ),
              if (suffix != null && !suffixIsSubtext) ...[
                Text(
                  suffix!,
                  style: text.displayMedium?.copyWith(
                    fontSize: 20,
                    color: palette.textTertiary,
                  ),
                ),
              ],
              if (suffix != null && suffixIsSubtext) ...[
                const SizedBox(width: 4),
                Text(
                  suffix!,
                  style: text.labelMedium?.copyWith(
                    color: palette.textTertiary,
                  ),
                ),
              ],
              if (badge != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: (badgeColor ?? palette.primary).withValues(
                      alpha: 0.2,
                    ),
                    borderRadius: BorderRadius.circular(ForeSeeMeRadius.xs),
                  ),
                  child: Text(
                    badge!,
                    style: text.labelSmall?.copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: badgeColor ?? palette.primary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ── Theme Switcher ───────────────────────────────────────────────────────────

class _PremiumThemeSwitcher extends ConsumerWidget {
  const _PremiumThemeSwitcher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.fsmPalette;
    final themeMode = ref.watch(themeNotifierProvider);
    final isDark =
        themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);

    return _GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: palette.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.palette_outlined,
              color: palette.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'Theme Mode',
              style: context.fsmText.titleMedium?.copyWith(fontSize: 15),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: palette.surfaceContainerLow,
              borderRadius: BorderRadius.circular(ForeSeeMeRadius.full),
              border: Border.all(color: palette.outlineVariant),
            ),
            child: Row(
              children: [
                _ThemeToggleButton(
                  icon: Icons.dark_mode_rounded,
                  label: 'Dark',
                  isSelected: isDark,
                  onTap: () => ref
                      .read(themeNotifierProvider.notifier)
                      .setThemeMode(ThemeMode.dark),
                ),
                _ThemeToggleButton(
                  icon: Icons.light_mode_rounded,
                  label: 'Light',
                  isSelected: !isDark,
                  onTap: () => ref
                      .read(themeNotifierProvider.notifier)
                      .setThemeMode(ThemeMode.light),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeToggleButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemeToggleButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final contentColor = isSelected
        ? palette.textPrimary
        : palette.textTertiary;

    return Semantics(
      button: true,
      selected: isSelected,
      label: '$label theme',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? palette.surfaceContainerHighest
                : Colors.transparent,
            borderRadius: BorderRadius.circular(ForeSeeMeRadius.full),
            boxShadow: isSelected ? context.fsmColors.shadows.soft : [],
          ),
          child: Row(
            children: [
              Icon(icon, size: 14, color: contentColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: context.fsmText.labelMedium?.copyWith(
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: contentColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Settings Tile ────────────────────────────────────────────────────────────

class _SettingsTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool showTrailing;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.showTrailing = true,
  });

  @override
  State<_SettingsTile> createState() => _SettingsTileState();
}

class _SettingsTileState extends State<_SettingsTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;

    return InkWell(
      onTap: widget.onTap,
      onHover: (val) => setState(() => _isHovered = val),
      borderRadius: BorderRadius.circular(ForeSeeMeRadius.lg),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _isHovered
              ? palette.onSurface.withValues(alpha: 0.05)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: palette.secondary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(widget.icon, color: palette.secondary, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: text.titleMedium?.copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.subtitle,
                    style: text.bodySmall?.copyWith(
                      color: palette.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            if (widget.showTrailing)
              Icon(
                Icons.chevron_right_rounded,
                color: palette.textTertiary,
              ),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: context.fsmPalette.outlineVariant);
  }
}

// ── Logout Button ────────────────────────────────────────────────────────────

class _LogoutButton extends StatefulWidget {
  final VoidCallback onPressed;
  const _LogoutButton({required this.onPressed});

  @override
  State<_LogoutButton> createState() => _LogoutButtonState();
}

class _LogoutButtonState extends State<_LogoutButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    return Semantics(
      button: true,
      label: 'Log Out',
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _isPressed ? 0.98 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: palette.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(ForeSeeMeRadius.md),
              border: Border.all(
                color: palette.primary.withValues(alpha: 0.3),
              ),
              boxShadow: context.fsmColors.shadows.soft,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.logout_rounded, color: palette.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Log Out',
                  style: context.fsmText.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: palette.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Shared Glass Container ───────────────────────────────────────────────────

class _GlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _GlassContainer({
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    // Reduced-transparency fallback (audit M4): a translucent, blurred glass
    // panel over a gradient can drop below contrast thresholds. Under high
    // contrast the blur is dropped and ForeSeeMeSurface makes the fill opaque
    // with a stronger border, so text sits on a solid, predictable surface.
    final sigma = A11y.blurSigma(context, sigma: 16);
    return ClipRRect(
      borderRadius: BorderRadius.circular(ForeSeeMeRadius.lg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: Container(
          padding: padding,
          decoration: ForeSeeMeSurface.card(context),
          child: child,
        ),
      ),
    );
  }
}
