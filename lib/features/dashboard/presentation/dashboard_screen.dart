import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/core/widgets/app_skeleton.dart';
import 'package:fyp_foreseeme/core/widgets/medical_disclaimer.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/alerts_providers.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/insights/presentation/adherence_insights_card.dart';
import 'package:fyp_foreseeme/features/insights/presentation/recommendations_card.dart';
import 'package:fyp_foreseeme/features/medication/domain/enums/medication_enums.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/medication_model.dart';
import 'package:fyp_foreseeme/features/medication/presentation/adherence_notifier.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_card.dart';

// ── Shared frosted-surface decoration ────────────────────────────────────────

/// One "glass card" recipe for the whole dashboard, sourced entirely from the
/// active ForeSeeMe theme so it renders correctly in light and dark and keeps a
/// single, consistent card elevation/hierarchy. Translucent [surface] over the
/// ambient gradient, a hairline border, and the design-system medium shadow.
BoxDecoration _glassDecoration(
  BuildContext context, {
  double radius = ForeSeeMeRadius.lg,
}) {
  final p = context.fsmPalette;
  return BoxDecoration(
    borderRadius: BorderRadius.circular(radius),
    color: p.surface.withValues(alpha: p.isDark ? 0.55 : 0.80),
    border: Border.all(
      color: p.isDark ? p.onSurface.withValues(alpha: 0.06) : p.outlineVariant,
      width: ForeSeeMeBorderWidth.thin,
    ),
    boxShadow: context.fsmColors.shadows.medium,
  );
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Represents the next upcoming dose across all active medications.
class _NextDose {
  final MedicationModel medication;
  final String timeString; // "HH:mm"
  final DateTime scheduledDateTime;

  const _NextDose({
    required this.medication,
    required this.timeString,
    required this.scheduledDateTime,
  });
}

/// Parses "HH:mm" into a [TimeOfDay].
TimeOfDay _parseTime(String hhmm) {
  final parts = hhmm.split(':');
  return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
}

/// Converts a [TimeOfDay] into a full [DateTime] for today.
DateTime _todayAt(TimeOfDay t) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day, t.hour, t.minute);
}

/// Finds the next upcoming dose from the list of active medications.
/// Returns null if there are no scheduled doses at all.
_NextDose? _findNextDose(List<MedicationModel> meds) {
  final now = DateTime.now();
  _NextDose? best;

  for (final med in meds) {
    if (!med.isActive) continue;
    for (final timeStr in med.reminderTimes) {
      final t = _parseTime(timeStr);
      // Try today first
      var scheduled = _todayAt(t);
      // If it's already passed today, use tomorrow
      if (scheduled.isBefore(now)) {
        scheduled = scheduled.add(const Duration(days: 1));
      }
      if (best == null || scheduled.isBefore(best.scheduledDateTime)) {
        best = _NextDose(
          medication: med,
          timeString: timeStr,
          scheduledDateTime: scheduled,
        );
      }
    }
  }
  return best;
}

/// Returns a human-friendly relative time string (e.g. "In 20 mins", "In 2 hrs").
String _relativeTime(DateTime scheduled) {
  final diff = scheduled.difference(DateTime.now());
  if (diff.inMinutes <= 1) return 'Now';
  if (diff.inMinutes < 60) return 'In ${diff.inMinutes} mins';
  if (diff.inHours < 24) {
    return 'In ${diff.inHours} hr${diff.inHours > 1 ? 's' : ''}';
  }
  return 'Tomorrow';
}

/// Formats "HH:mm" into "08:00 AM" style.
String _formatDisplay(String hhmm) {
  final t = _parseTime(hhmm);
  final hour = t.hour == 0 ? 12 : (t.hour > 12 ? t.hour - 12 : t.hour);
  final minute = t.minute.toString().padLeft(2, '0');
  final suffix = t.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $suffix';
}

// ── Dashboard Screen ──────────────────────────────────────────────────────────

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).value;
    final displayName = user?.displayName ?? 'Patient';
    final palette = context.fsmPalette;
    final text = context.fsmText;

    return Scaffold(
      backgroundColor: palette.background,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Premium ambient background — the design-system surface gradient.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: context.fsmColors.gradients.surface,
              ),
            ),
          ),

          // Top ambient glow (brand primary, subtle).
          Positioned(
            top: -100,
            left: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    palette.primary.withValues(alpha: palette.isDark ? 0.15 : 0.10),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            bottom: false,
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: ForeSeeMeSpacing.xxl,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 16),
                        // 1. HERO HEALTH OVERVIEW
                        _HeroOverviewSection(displayName: displayName),

                        const SizedBox(height: 32),

                        // 2. LIVE RISK CARD (tap → full Risk Details analytics)
                        GestureDetector(
                          onTap: () => context.push('/risk-details'),
                          child: const RiskCard(),
                        ),

                        const SizedBox(height: 10),

                        // 2a. NON-DIAGNOSTIC FRAMING — the risk reading is an
                        // environmental estimate, never a clinical diagnosis.
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 2),
                          child: MedicalDisclaimer.inline(),
                        ),

                        const SizedBox(height: 16),

                        // 2b. CITED RECOMMENDATION (deterministic, sourced)
                        const RecommendationsCard(),

                        const SizedBox(height: 24),

                        // 3. SUPPORTIVE ADHERENCE INSIGHTS (real, read-only —
                        // streaks and taken-count computed from actual logs;
                        // never a fabricated score).
                        const AdherenceInsightsCard(),

                        const SizedBox(height: 16),

                        // 3c. HEALTH INSIGHTS SUMMARY ENTRY POINT
                        const _HealthInsightsEntry(),

                        const SizedBox(height: 32),

                        // 4. TODAY'S MEDICATION CARD (dynamic)
                        Text(
                          'Upcoming Schedule',
                          style: text.titleLarge?.copyWith(
                            fontSize: 20,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const _UpcomingMedicationCard(),

                        const SizedBox(height: 32),

                        // 5. QUICK ACTIONS SECTION
                        Text(
                          'Quick Actions',
                          style: text.titleLarge?.copyWith(
                            fontSize: 20,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const _QuickActionsRow(),

                        const SizedBox(
                          height: 120,
                        ), // Padding for bottom nav bar
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Hero Section ─────────────────────────────────────────────────────────────

class _HeroOverviewSection extends StatelessWidget {
  final String displayName;
  const _HeroOverviewSection({required this.displayName});

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning,';
    if (hour < 17) return 'Good Afternoon,';
    return 'Good Evening,';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final colors = context.fsmColors;
    final text = context.fsmText;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _getGreeting(),
                style: text.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: palette.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                displayName,
                style: text.displayMedium,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: colors.success.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(ForeSeeMeRadius.xs),
                  border: Border.all(
                    color: colors.success.withValues(alpha: 0.30),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: colors.success,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: colors.success,
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'System Optimal',
                      style: text.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.success,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const _InboxBellButton(),
        const SizedBox(width: 12),
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [palette.primary, palette.secondary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: palette.primary.withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(2),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: palette.surface,
            ),
            child: Icon(
              Icons.person_outline_rounded,
              color: palette.primary,
              size: 24,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Alert Inbox Bell ─────────────────────────────────────────────────────────

/// Dashboard entry point to the alert inbox (Sprint 4, Prompt 5), with a live
/// unread badge sourced from [unreadAlertCountProvider].
class _InboxBellButton extends ConsumerWidget {
  const _InboxBellButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadAlertCountProvider);
    final palette = context.fsmPalette;

    return Semantics(
      button: true,
      label: unread > 0 ? 'Alerts, $unread unread' : 'Alerts',
      child: Badge.count(
        count: unread,
        isLabelVisible: unread > 0,
        backgroundColor: palette.error,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: palette.surface.withValues(alpha: palette.isDark ? 0.45 : 0.80),
            border: Border.all(
              color: palette.isDark
                  ? palette.onSurface.withValues(alpha: 0.05)
                  : palette.outlineVariant,
            ),
          ),
          child: IconButton(
            icon: Icon(
              Icons.notifications_none_rounded,
              color: palette.onSurfaceVariant,
              size: 22,
            ),
            tooltip: 'Alerts',
            onPressed: () => context.push('/alerts'),
          ),
        ),
      ),
    );
  }
}

// ── Health Insights Entry ────────────────────────────────────────────────────

/// Dashboard entry point to the unified Health Insights summary (Sprint 4, P8).
class _HealthInsightsEntry extends StatelessWidget {
  const _HealthInsightsEntry();

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push('/health-insights'),
        borderRadius: BorderRadius.circular(ForeSeeMeRadius.md),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: _glassDecoration(context, radius: ForeSeeMeRadius.md),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: palette.secondary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(ForeSeeMeRadius.sm),
                ),
                child: Icon(
                  Icons.insights_rounded,
                  color: palette.secondary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Health Insights',
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Risk, tips & your routine in one view',
                      style: text.bodySmall?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: palette.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Upcoming Medication Card (DYNAMIC) ───────────────────────────────────────

class _UpcomingMedicationCard extends ConsumerStatefulWidget {
  const _UpcomingMedicationCard();

  @override
  ConsumerState<_UpcomingMedicationCard> createState() =>
      _UpcomingMedicationCardState();
}

class _UpcomingMedicationCardState
    extends ConsumerState<_UpcomingMedicationCard> {
  // Optimistic "taken" state for the dose currently shown (keyed by the
  // deterministic log ID so a different next-dose never inherits it).
  String? _optimisticallyTakenLogId;
  bool _isSubmitting = false;

  Future<void> _takeNow(_NextDose nextDose) async {
    if (_isSubmitting) return;
    final notifier = ref.read(adherenceNotifierProvider.notifier);
    final logId = notifier.generateLogId(
      nextDose.medication.id,
      nextDose.scheduledDateTime,
      nextDose.timeString,
    );

    setState(() {
      _isSubmitting = true;
      _optimisticallyTakenLogId = logId;
    });

    try {
      await notifier.updateStatus(
        medication: nextDose.medication,
        date: nextDose.scheduledDateTime,
        timeString: nextDose.timeString,
        status: AdherenceStatus.taken,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _optimisticallyTakenLogId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't mark as taken — restored ($e)")),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final medsAsync = ref.watch(medicationsStreamProvider);

    return medsAsync.when(
      loading: () => _GlassContainer(
        child: const AppSkeleton(
          child: Row(
            children: [
              SkeletonBox(width: 48, height: 48, radius: 24),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBar(width: 140, height: 16),
                    SizedBox(height: 8),
                    SkeletonBar(width: 90, height: 12),
                  ],
                ),
              ),
              SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SkeletonBar(width: 56, height: 14),
                  SizedBox(height: 8),
                  SkeletonBar(width: 40, height: 12),
                ],
              ),
            ],
          ),
        ),
      ),
      error: (err, st) => _buildEmpty(context, 'Unable to load medications'),
      data: (meds) {
        final nextDose = _findNextDose(meds);
        if (nextDose == null) {
          return _buildEmpty(context, 'No medications scheduled');
        }
        return _buildCard(context, nextDose);
      },
    );
  }

  Widget _buildEmpty(BuildContext context, String message) {
    final palette = context.fsmPalette;
    return _GlassContainer(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: palette.secondary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.medication_rounded,
              color: palette.textTertiary,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              message,
              style: context.fsmText.bodyLarge?.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: palette.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(BuildContext context, _NextDose nextDose) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final med = nextDose.medication;
    final timeDisplay = _formatDisplay(nextDose.timeString);
    final relative = _relativeTime(nextDose.scheduledDateTime);
    final logId = ref
        .read(adherenceNotifierProvider.notifier)
        .generateLogId(med.id, nextDose.scheduledDateTime, nextDose.timeString);
    final isTaken = _optimisticallyTakenLogId == logId;

    return _GlassContainer(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: palette.secondary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.medication_rounded,
                    color: palette.secondary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        med.name,
                        style: text.titleLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        med.dosage.isNotEmpty
                            ? med.dosage
                            : med.frequency.label,
                        style: text.bodyMedium?.copyWith(
                          fontSize: 13,
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      timeDisplay,
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      relative,
                      style: text.labelMedium?.copyWith(
                        color: palette.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(height: 1, color: palette.outlineVariant),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: _MedicationActionButton(
                    label: 'Skip',
                    icon: Icons.close_rounded,
                    color: palette.surfaceContainerHighest,
                    textColor: palette.textPrimary,
                    onTap: (isTaken || _isSubmitting)
                        ? null
                        : () => context.go('/check-in'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MedicationActionButton(
                    label: isTaken ? 'Taken' : 'Take Now',
                    icon: isTaken
                        ? Icons.check_circle_rounded
                        : Icons.check_rounded,
                    color: palette.primary,
                    textColor: palette.onPrimary,
                    onTap: isTaken ? null : () => _takeNow(nextDose),
                    isPrimary: true,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MedicationActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final Color textColor;
  final VoidCallback? onTap;
  final bool isPrimary;

  const _MedicationActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.textColor,
    required this.onTap,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isPrimary ? null : color,
            borderRadius: BorderRadius.circular(ForeSeeMeRadius.sm),
            gradient: isPrimary ? context.fsmColors.gradients.primary : null,
            boxShadow: isPrimary
                ? [
                    BoxShadow(
                      color: context.fsmPalette.primary.withValues(alpha: 0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: textColor, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: context.fsmText.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Quick Actions ────────────────────────────────────────────────────────────

class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickActionCard(
            icon: Icons.add_rounded,
            label: 'Add Med',
            // Correct path: nested under /medications
            onTap: () => context.push('/medications/add'),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _QuickActionCard(
            icon: Icons.place_outlined,
            label: 'Risk Map',
            // National risk map (Sprint 3, Prompt 4).
            onTap: () => context.push('/risk-map'),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _QuickActionCard(
            icon: Icons.menu_book_rounded,
            label: 'Resources',
            onTap: () => context.go('/resources'),
          ),
        ),
      ],
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: _glassDecoration(context, radius: ForeSeeMeRadius.md),
        child: Column(
          children: [
            Icon(icon, color: palette.primary, size: 24),
            const SizedBox(height: 8),
            Text(
              label,
              style: context.fsmText.labelMedium?.copyWith(
                color: palette.textPrimary,
              ),
            ),
          ],
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(ForeSeeMeRadius.lg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: padding,
          decoration: _glassDecoration(context),
          child: child,
        ),
      ),
    );
  }
}
