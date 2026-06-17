import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:fyp_foreseeme/core/theme/app_colors.dart';
import 'package:fyp_foreseeme/core/theme/app_theme.dart';
import 'package:fyp_foreseeme/core/widgets/empty_state_widget.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/medication_model.dart';
import 'package:fyp_foreseeme/features/medication/presentation/adherence_notifier.dart';

// ── Liquid Glass teal constants ───────────────────────────────────────────────
const _kTeal = Color(0xFF006D77);
const _kCyan = Color(0xFF28DDE8);

class MedicationScreen extends ConsumerWidget {
  const MedicationScreen({super.key});

  String _formatTime(String timeString) {
    final parts = timeString.split(':');
    if (parts.length != 2) return timeString;
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = parts[1];
    final suffix = hour >= 12 ? 'PM' : 'AM';
    final readHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$readHour:$minute $suffix';
  }

  Widget _buildMedicationTile(BuildContext context, MedicationModel medication) {
    final isDark =
        AppColors.activePalette == AppColors.darkPalette ||
        Theme.of(context).brightness == Brightness.dark;

    final reminderText = medication.reminderTimes.isEmpty
        ? 'No reminders set'
        : medication.reminderTimes.map(_formatTime).join(', ');

    final isActive = medication.isActive;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.paddingHorizontal,
        vertical: 6.0,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: isDark
                  ? const Color(0xFF0D1F38).withValues(alpha: 0.68)
                  : Colors.white.withValues(alpha: 0.80),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.09)
                    : _kTeal.withValues(alpha: 0.13),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: _kTeal.withValues(alpha: isDark ? 0.14 : 0.06),
                  blurRadius: 24,
                  spreadRadius: -6,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.05),
                  blurRadius: 16,
                  spreadRadius: -8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon badge
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: isActive
                        ? const LinearGradient(
                            colors: [_kTeal, _kCyan],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: isActive
                        ? null
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.07)
                            : AppColors.surfaceHigh),
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: _kCyan.withValues(alpha: 0.30),
                              blurRadius: 14,
                              spreadRadius: -4,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : [],
                  ),
                  child: Icon(
                    Icons.medication_rounded,
                    color: isActive
                        ? Colors.white
                        : (isDark ? AppColors.textTertiary : AppColors.textTertiary),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                // Text content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              medication.name,
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white : AppColors.textPrimary,
                                height: 1.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Dosage pill
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _kTeal.withValues(alpha: isDark ? 0.18 : 0.10),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: _kCyan.withValues(alpha: isDark ? 0.28 : 0.18),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              medication.dosage,
                              style: GoogleFonts.manrope(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isDark ? _kCyan : _kTeal,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        medication.frequency.label,
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isDark
                              ? const Color(0xFF8EA6BD)
                              : AppColors.textSecondary,
                        ),
                      ),
                      if (reminderText.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time_rounded,
                              size: 13,
                              color: isDark
                                  ? _kCyan.withValues(alpha: 0.70)
                                  : _kTeal.withValues(alpha: 0.70),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                reminderText,
                                style: GoogleFonts.manrope(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: isDark
                                      ? _kCyan.withValues(alpha: 0.80)
                                      : _kTeal.withValues(alpha: 0.80),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (!isActive) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Inactive',
                            style: GoogleFonts.manrope(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.error,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final medicationsAsync = ref.watch(medicationsStreamProvider);
    final isDark =
        AppColors.activePalette == AppColors.darkPalette ||
        Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: _GlassAppBar(isDark: isDark, context: context),
      body: Stack(
        children: [
          // Ambient gradient background
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? const [Color(0xFF0A1628), Color(0xFF0D1F38), Color(0xFF081220)]
                      : const [Color(0xFFF0F7FF), Color(0xFFE6F5F5), Color(0xFFF5F0FF)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),
          // Ambient glow orb – top-right
          Positioned(
            top: -40,
            right: -50,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _kTeal.withValues(alpha: isDark ? 0.22 : 0.10),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // List content
          medicationsAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(_kCyan),
                strokeCap: StrokeCap.round,
              ),
            ),
            error: (err, _) => EmptyStateWidget(
              title: 'Unable to load medications',
              subTitle: err.toString(),
              icon: Icons.error_outline,
            ),
            data: (medications) {
              if (medications.isEmpty) {
                return _EmptyMedicationState(isDark: isDark, context: context);
              }
              return ListView.builder(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + kToolbarHeight + 16,
                  bottom: 96.0,
                ),
                itemCount: medications.length + 1,
                itemBuilder: (context, index) {
                  if (index == medications.length) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppDimensions.paddingHorizontal,
                        16.0,
                        AppDimensions.paddingHorizontal,
                        0.0,
                      ),
                      child: _GradientCheckInButton(
                        onPressed: () => context.go('/check-in'),
                      ),
                    );
                  }
                  return _buildMedicationTile(context, medications[index]);
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Glass AppBar ──────────────────────────────────────────────────────────────

class _GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final bool isDark;
  final BuildContext context;

  const _GlassAppBar({required this.isDark, required this.context});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext buildContext) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: AppBar(
          backgroundColor: isDark
              ? const Color(0xFF0A1628).withValues(alpha: 0.75)
              : Colors.white.withValues(alpha: 0.72),
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text(
            'Medications',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : AppColors.textPrimary,
              letterSpacing: -0.2,
            ),
          ),
          actions: [
            IconButton(
              icon: Icon(
                Icons.bar_chart_rounded,
                color: isDark ? _kCyan.withValues(alpha: 0.90) : _kTeal,
              ),
              onPressed: () => context.go('/adherence-history'),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _GlassIconButton(
                isDark: isDark,
                icon: Icons.add_rounded,
                onPressed: () => context.go('/medications/add'),
              ),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(
              height: 1,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.07)
                  : _kTeal.withValues(alpha: 0.10),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  final bool isDark;
  final IconData icon;
  final VoidCallback onPressed;

  const _GlassIconButton({
    required this.isDark,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          gradient: const LinearGradient(
            colors: [_kTeal, _kCyan],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: _kCyan.withValues(alpha: 0.30),
              blurRadius: 12,
              spreadRadius: -3,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyMedicationState extends StatelessWidget {
  final bool isDark;
  final BuildContext context;

  const _EmptyMedicationState({required this.isDark, required this.context});

  @override
  Widget build(BuildContext buildContext) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _kCyan.withValues(alpha: 0.18),
                    _kTeal.withValues(alpha: 0.06),
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
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      colors: [_kTeal, _kCyan],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _kCyan.withValues(alpha: 0.30),
                        blurRadius: 18,
                        spreadRadius: -4,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.medication_rounded,
                      color: Colors.white, size: 28),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No medications yet',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your medications will appear here.\nAdd one to get started.',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: 14,
                height: 1.6,
                color: isDark ? const Color(0xFF8EA6BD) : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 28),
            _GradientCheckInButton(onPressed: () => context.go('/check-in')),
          ],
        ),
      ),
    );
  }
}

// ── Gradient Check-In button ──────────────────────────────────────────────────

class _GradientCheckInButton extends StatefulWidget {
  final VoidCallback onPressed;
  const _GradientCheckInButton({required this.onPressed});

  @override
  State<_GradientCheckInButton> createState() => _GradientCheckInButtonState();
}

class _GradientCheckInButtonState extends State<_GradientCheckInButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _isPressed ? 0.975 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: AppDimensions.buttonHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
            gradient: const LinearGradient(
              colors: [_kTeal, _kCyan],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: _kCyan.withValues(alpha: _isPressed ? 0.20 : 0.36),
                blurRadius: _isPressed ? 18 : 30,
                spreadRadius: -6,
                offset: Offset(0, _isPressed ? 4 : 10),
              ),
            ],
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_outline_rounded,
                    color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Check-In Now',
                  style: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                    color: Colors.white,
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
