import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/core/widgets/empty_state_widget.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_stats_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/medication_model.dart';
import 'package:fyp_foreseeme/features/medication/presentation/adherence_analytics_provider.dart';
import 'package:fyp_foreseeme/features/medication/presentation/adherence_notifier.dart';
import 'package:fyp_foreseeme/features/medication/presentation/medication_notifier.dart';
import 'package:fyp_foreseeme/features/medication/presentation/widgets/med_primitives.dart';
import 'package:fyp_foreseeme/features/medication/presentation/widgets/medication_detail_sheet.dart';

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

  Widget _buildMedicationTile(
    BuildContext context,
    WidgetRef ref,
    MedicationModel medication,
  ) {
    final palette = context.fsmPalette;
    final text = context.fsmText;

    final reminderText = medication.reminderTimes.isEmpty
        ? 'No reminders set'
        : medication.reminderTimes.map(_formatTime).join(', ');

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ForeSeeMeSpacing.gutter,
        vertical: 6.0,
      ),
      child: PressableScale(
        onTap: () => _showMedicationDetailSheet(context, ref, medication),
        child: Semantics(
          button: true,
          label: '${medication.name}, ${medication.dosage}',
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
                        gradient: LinearGradient(
                          colors: [palette.primary, palette.secondary],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: palette.primary.withValues(alpha: 0.30),
                            blurRadius: 14,
                            spreadRadius: -4,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.medication_rounded,
                        color: palette.onPrimary,
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
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: palette.textTertiary,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showMedicationDetailSheet(
    BuildContext context,
    WidgetRef ref,
    MedicationModel medication,
  ) {
    final stats = ref.read(adherenceAnalyticsProvider(medication.uid)).value;
    AdherenceStatsModel? stat;
    for (final s in stats ?? const <AdherenceStatsModel>[]) {
      if (s.medicationId == medication.id) {
        stat = s;
        break;
      }
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => MedicationDetailSheet(
        medication: medication,
        stat: stat,
        onEdit: () {
          Navigator.of(sheetContext).pop();
          context.push('/medications/edit', extra: medication);
        },
        onArchive: () {
          Navigator.of(sheetContext).pop();
          _confirmArchive(context, ref, medication);
        },
      ),
    );
  }

  Future<void> _confirmArchive(
    BuildContext context,
    WidgetRef ref,
    MedicationModel medication,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Archive Medication?'),
        content: const Text(
          'This medication will no longer appear in your active medications.\n\n'
          'Your adherence history will remain available.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: dialogContext.fsmPalette.error,
            ),
            child: const Text('Archive'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await ref
          .read(medicationNotifierProvider.notifier)
          .archiveMedication(medication.uid, medication.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Medication archived')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Archive failed: $e')),
      );
    }
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
              // Archived medications are excluded — they preserve adherence
              // history but no longer appear in the active list.
              final activeMedications = medications
                  .where((m) => m.isActive)
                  .toList();

              if (activeMedications.isEmpty) {
                return const _EmptyMedicationState();
              }
              return ListView.builder(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + kToolbarHeight + 16,
                  bottom: 96.0,
                ),
                itemCount: activeMedications.length + 1,
                itemBuilder: (context, index) {
                  if (index == activeMedications.length) {
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
                  return _buildMedicationTile(
                    context,
                    ref,
                    activeMedications[index],
                  );
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
