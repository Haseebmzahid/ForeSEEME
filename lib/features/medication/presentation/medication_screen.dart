import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/core/widgets/empty_state_widget.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/medication_model.dart';
import 'package:fyp_foreseeme/features/medication/presentation/adherence_notifier.dart';
import 'package:fyp_foreseeme/features/medication/presentation/widgets/med_primitives.dart';

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
    final palette = context.fsmPalette;
    final text = context.fsmText;

    final reminderText = medication.reminderTimes.isEmpty
        ? 'No reminders set'
        : medication.reminderTimes.map(_formatTime).join(', ');

    final isActive = medication.isActive;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ForeSeeMeSpacing.gutter,
        vertical: 6.0,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ForeSeeMeRadius.lg),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: ForeSeeMeSurface.card(context),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon badge
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(ForeSeeMeRadius.sm),
                    gradient: isActive
                        ? LinearGradient(
                            colors: [palette.primary, palette.secondary],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: isActive ? null : palette.surfaceContainerHighest,
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: palette.primary.withValues(alpha: 0.30),
                              blurRadius: 14,
                              spreadRadius: -4,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : [],
                  ),
                  child: Icon(
                    Icons.medication_rounded,
                    color: isActive ? palette.onPrimary : palette.textTertiary,
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
                              style: text.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
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
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: palette.secondary.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(
                                ForeSeeMeRadius.full,
                              ),
                              border: Border.all(
                                color: palette.secondary.withValues(alpha: 0.24),
                                width: ForeSeeMeBorderWidth.hairline,
                              ),
                            ),
                            child: Text(
                              medication.dosage,
                              style: text.labelSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: palette.secondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        medication.frequency.label,
                        style: text.bodyMedium?.copyWith(
                          fontSize: 13,
                          color: palette.textSecondary,
                        ),
                      ),
                      if (reminderText.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time_rounded,
                              size: 13,
                              color: palette.secondary.withValues(alpha: 0.75),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                reminderText,
                                style: text.bodySmall?.copyWith(
                                  color: palette.secondary,
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
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: palette.error.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Inactive',
                            style: text.labelSmall?.copyWith(
                              color: palette.error,
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
    final palette = context.fsmPalette;
    final medicationsAsync = ref.watch(medicationsStreamProvider);

    return Scaffold(
      backgroundColor: palette.background,
      extendBodyBehindAppBar: true,
      appBar: const _GlassAppBar(),
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
                    palette.primary.withValues(
                      alpha: palette.isDark ? 0.20 : 0.10,
                    ),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // List content
          medicationsAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(strokeCap: StrokeCap.round),
            ),
            error: (err, _) => EmptyStateWidget(
              title: 'Unable to load medications',
              subTitle: err.toString(),
              icon: Icons.error_outline,
            ),
            data: (medications) {
              if (medications.isEmpty) {
                return const _EmptyMedicationState();
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
                        ForeSeeMeSpacing.gutter,
                        16.0,
                        ForeSeeMeSpacing.gutter,
                        0.0,
                      ),
                      child: MedGradientButton(
                        icon: Icons.check_circle_outline_rounded,
                        label: 'Check-In Now',
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
  const _GlassAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: AppBar(
          backgroundColor: ForeSeeMeSurface.chromeFill(context),
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          title: Text(
            'Medications',
            style: context.fsmText.titleLarge?.copyWith(
              fontSize: 20,
              letterSpacing: -0.2,
            ),
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.bar_chart_rounded, color: palette.secondary),
              tooltip: 'Adherence history',
              onPressed: () => context.go('/adherence-history'),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _GlassIconButton(
                icon: Icons.add_rounded,
                tooltip: 'Add medication',
                onPressed: () => context.go('/medications/add'),
              ),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(
              height: 1,
              color: ForeSeeMeSurface.stroke(context),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _GlassIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: onPressed,
          // Keeps the visual badge at 36dp while preserving a 48dp tap target.
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  gradient: context.fsmColors.gradients.primary,
                  boxShadow: [
                    BoxShadow(
                      color: palette.primary.withValues(alpha: 0.30),
                      blurRadius: 12,
                      spreadRadius: -3,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(icon, color: palette.onPrimary, size: 20),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyMedicationState extends StatelessWidget {
  const _EmptyMedicationState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const MedEmptyGlyph(icon: Icons.medication_rounded),
            const SizedBox(height: 24),
            Text(
              'No medications yet',
              style: context.fsmText.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Your medications will appear here.\nAdd one to get started.',
              textAlign: TextAlign.center,
              style: context.fsmText.bodyMedium?.copyWith(
                height: 1.6,
                color: context.fsmPalette.textSecondary,
              ),
            ),
            const SizedBox(height: 28),
            MedGradientButton(
              icon: Icons.check_circle_outline_rounded,
              label: 'Check-In Now',
              onPressed: () => context.go('/check-in'),
            ),
          ],
        ),
      ),
    );
  }
}
