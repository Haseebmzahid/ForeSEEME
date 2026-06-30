import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/medication_model.dart';
import 'package:fyp_foreseeme/features/medication/presentation/adherence_notifier.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_card.dart';

const _kTeal = Color(0xFF006D77);
const _kCyan = Color(0xFF28DDE8);

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

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Premium Ambient Background
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF06111D),
                    Color(0xFF0A1628),
                    Color(0xFF040A12),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),

          // Top ambient glow
          Positioned(
            top: -100,
            left: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [_kCyan.withValues(alpha: 0.15), Colors.transparent],
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
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 16),
                        // 1. HERO HEALTH OVERVIEW
                        _HeroOverviewSection(displayName: displayName),

                        const SizedBox(height: 32),

                        // 2. LIVE RISK CARD (current city environmental risk)
                        const RiskCard(),

                        const SizedBox(height: 24),

                        // 3. ADHERENCE SUMMARY CARD
                        const _AdherenceSummaryCard(),

                        const SizedBox(height: 32),

                        // 4. TODAY'S MEDICATION CARD (dynamic)
                        Text(
                          'Upcoming Schedule',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const _UpcomingMedicationCard(),

                        const SizedBox(height: 32),

                        // 5. QUICK ACTIONS SECTION
                        Text(
                          'Quick Actions',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _getGreeting(),
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                displayName,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _kTeal.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _kTeal.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: _kCyan,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _kCyan,
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'System Optimal',
                      style: GoogleFonts.manrope(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _kCyan,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [_kCyan, _kTeal],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: _kCyan.withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(2),
          child: Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF0D1F38),
            ),
            child: const Icon(
              Icons.person_outline_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Adherence Summary Card ───────────────────────────────────────────────────

class _AdherenceSummaryCard extends StatelessWidget {
  const _AdherenceSummaryCard();

  @override
  Widget build(BuildContext context) {
    return _GlassContainer(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.analytics_outlined,
                      color: _kCyan,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'ADHERENCE',
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Great job keeping up!',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '14 day active streak 🔥',
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: _kCyan,
                  ),
                ),
              ],
            ),
          ),
          // Premium Circular Progress Indicator
          SizedBox(
            width: 80,
            height: 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 80,
                  height: 80,
                  child: CircularProgressIndicator(
                    value: 0.94,
                    strokeWidth: 8,
                    backgroundColor: Colors.white.withValues(alpha: 0.05),
                    valueColor: const AlwaysStoppedAnimation<Color>(_kCyan),
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Text(
                  '94%',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
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

// ── Upcoming Medication Card (DYNAMIC) ───────────────────────────────────────

class _UpcomingMedicationCard extends ConsumerWidget {
  const _UpcomingMedicationCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final medsAsync = ref.watch(medicationsStreamProvider);

    return medsAsync.when(
      loading: () => _GlassContainer(
        child: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(_kCyan),
            strokeWidth: 2,
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
    return _GlassContainer(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _kTeal.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.medication_rounded,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.manrope(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(BuildContext context, _NextDose nextDose) {
    final med = nextDose.medication;
    final timeDisplay = _formatDisplay(nextDose.timeString);
    final relative = _relativeTime(nextDose.scheduledDateTime);

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
                    color: _kTeal.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.medication_rounded, color: _kCyan),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        med.name,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        med.dosage.isNotEmpty
                            ? med.dosage
                            : med.frequency.label,
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.6),
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
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      relative,
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _kCyan,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.05)),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: _MedicationActionButton(
                    label: 'Skip',
                    icon: Icons.close_rounded,
                    color: Colors.white.withValues(alpha: 0.1),
                    textColor: Colors.white,
                    onTap: () => context.go('/check-in'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MedicationActionButton(
                    label: 'Take Now',
                    icon: Icons.check_rounded,
                    color: _kTeal,
                    textColor: Colors.white,
                    onTap: () => context.go('/check-in'),
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
  final VoidCallback onTap;
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isPrimary ? null : color,
          borderRadius: BorderRadius.circular(12),
          gradient: isPrimary
              ? const LinearGradient(
                  colors: [_kTeal, _kCyan],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : null,
          boxShadow: isPrimary
              ? [
                  BoxShadow(
                    color: _kCyan.withValues(alpha: 0.2),
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
              style: GoogleFonts.manrope(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
          ],
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1F38).withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Column(
          children: [
            Icon(icon, color: _kCyan, size: 24),
            const SizedBox(height: 8),
            Text(
              label,
              style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
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
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: const Color(0xFF0D1F38).withValues(alpha: 0.45),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.05),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
