import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_stats_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/medication_hub_state.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/medication_model.dart';
import 'package:fyp_foreseeme/features/medication/presentation/adherence_analytics_provider.dart';
import 'package:fyp_foreseeme/features/medication/presentation/medication_hub_providers.dart';
import 'package:fyp_foreseeme/features/medication/presentation/medication_notifier.dart';
import 'package:fyp_foreseeme/features/medication/presentation/widgets/medication_detail_sheet.dart';
import 'package:fyp_foreseeme/features/medication/presentation/widgets/medication_hub_chrome.dart';
import 'package:fyp_foreseeme/features/medication/presentation/widgets/medication_hub_objects.dart';
import 'package:fyp_foreseeme/features/medication/presentation/widgets/medication_hub_style.dart';

/// The **Medications screen**, implemented natively from the approved
/// prototype (`docs/Design/ForeSeeMe Medications.html`).
///
/// Composition only: every value on screen comes from [medicationHubProvider],
/// which projects the existing medication and adherence-log streams through
/// [MedicationHubService]. The screen touches no repository and no Firebase SDK
/// (Golden Rule 1), performs no scheduling arithmetic of its own, and keeps the
/// module's existing behaviour — real-time streaming, add / edit / archive
/// through [MedicationNotifier], and the reminder scheduling and cancellation
/// that notifier already drives.
///
/// **Deliberate departures from the prototype**, all recorded here so the
/// difference is a decision rather than a drift:
///
///  * The prototype's mock status bar (`9:41`, `LTE`, a battery) is dropped. It
///    is prototype furniture standing in for the real OS status bar, and
///    drawing a fake `9:41` in a shipping app would be fabricated information.
///  * The prototype's own bottom navigation is dropped in favour of the app's
///    existing `AppShell` / `AppBottomNavBar`, which this screen must not
///    redesign. The scroll padding still reserves the prototype's clearance so
///    the last card clears the bar by the same margin.
///  * The prototype draws four distinct medication objects for its four mock
///    medications. The app stores two types (`pill`, `syrup`), so two objects
///    are drawn, keyed to the stored type — see `medication_hub_objects.dart`.
///  * The prototype has one non-taken past state, `MISSED`. The app
///    distinguishes a dose the user *skipped* from one that lapsed, so a
///    skipped dose keeps the prototype's amber treatment but is labelled
///    `SKIPPED`. Reporting a deliberate skip back as a miss would be wrong.
///  * The prototype's `checkIn` handler confirms the next dose in place. Here
///    the slab navigates to Daily Check-In, which is where the app's dose
///    confirmation (and its optimistic-update, auto-missed and notification
///    refresh machinery) actually lives. Duplicating that mutation on this
///    screen would create a second write path for the same fact.
///  * The prototype has no loading, error, or empty states. Those are drawn
///    here in its own material rather than left to a generic Material fallback.
///  * The screen this replaces carried an app-bar button through to the
///    adherence history, and the prototype has no app bar. Rather than lose the
///    entry point, the schedule header's own readout — which already summarises
///    today's adherence — becomes the control, gaining a chevron and a 44dp tap
///    target so it does not become a hidden gesture.
class MedicationScreen extends ConsumerStatefulWidget {
  const MedicationScreen({super.key});

  @override
  ConsumerState<MedicationScreen> createState() => _MedicationScreenState();
}

class _MedicationScreenState extends ConsumerState<MedicationScreen> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // ── Interactions (unchanged behaviour, new chrome) ─────────────────────────

  void _openDetail(MedicationModel medication) {
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
          _confirmArchive(medication);
        },
      ),
    );
  }

  Future<void> _confirmArchive(MedicationModel medication) async {
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
              foregroundColor: MedicationHubTheme.of(dialogContext).warn,
            ),
            child: const Text('Archive'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await ref
          .read(medicationNotifierProvider.notifier)
          .archiveMedication(medication.uid, medication.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Medication archived')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Archive failed: $e')),
      );
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = MedicationHubTheme.of(context);
    final hub = ref.watch(medicationHubProvider);

    return Scaffold(
      backgroundColor: theme.bg,
      body: Stack(
        children: [
          _Backdrop(scroll: _scroll),
          SafeArea(
            bottom: false,
            // The content and the bottom actions are siblings in a column, not
            // layers in a stack: the actions own their space at the foot of the
            // screen, so a medication card can never scroll underneath them.
            child: Column(
              children: [
                Expanded(
                  child: hub.when(
                    loading: () => const _HubLoading(),
                    error: (error, _) => _HubError(message: error.toString()),
                    data: (summary) => summary.activeCount == 0
                        ? const _HubEmpty()
                        : _HubContent(
                            summary: summary,
                            scroll: _scroll,
                            onMedicationTap: _openDetail,
                          ),
                  ),
                ),
                _BottomActions(
                  subtitle: _checkInSubtitle(hub.value),
                  onCheckIn: () => context.go('/check-in'),
                  onAdd: () => context.go('/medications/add'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The Check-In slab's subtitle, or `null` when there is no check-in to
  /// offer — while the hub is still loading, and once the day holds no dose
  /// left to confirm. The slab is only shown when it has something to do.
  ///
  /// This reads the same `nextDose` the hero and the schedule rail already
  /// read; it decides nothing of its own.
  static String? _checkInSubtitle(MedicationHubSummary? summary) {
    final next = summary?.nextDose;
    return next == null ? null : 'Confirm your ${next.time} dose';
  }
}

// ── Content ──────────────────────────────────────────────────────────────────

class _HubContent extends StatelessWidget {
  const _HubContent({
    required this.summary,
    required this.scroll,
    required this.onMedicationTap,
  });

  final MedicationHubSummary summary;
  final ScrollController scroll;
  final ValueChanged<MedicationModel> onMedicationTap;

  @override
  Widget build(BuildContext context) {
    final theme = MedicationHubTheme.of(context);
    final next = summary.nextDose;

    return ListView(
      controller: scroll,
      // The prototype's `padding: 46px 18px 272px`. The 46px top is its
      // status-bar allowance, which SafeArea now provides. Its 272px bottom was
      // clearance for a bottom bar that overlaid the list; the actions now sit
      // in their own region below it, so only the last card's breathing room
      // remains. The 18px side inset is applied per child rather than on the
      // list, because the hero and the rail cancel it (`margin: 0 -18px`) to
      // span the full width.
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      children: [
        _HeroSection(
          scroll: scroll,
          activeCount: summary.activeCount,
          takenCount: summary.takenCount,
          scheduledCount: summary.scheduledCount,
          nextName: next?.medication.name,
          nextTime: next?.time,
        ),

        // ── Today's schedule ───────────────────────────────────────────────
        Padding(
          // The prototype's `margin: 18px 2px 10px`, less the 14px the
          // readout's tap target adds above and below it.
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: MedHubSectionHeader(
            label: "TODAY'S SCHEDULE",
            trailing: _railSummary(summary),
            trailingColor: summary.missedCount > 0 ? theme.warn : theme.txt2,
            onTrailingTap: () => context.go('/adherence-history'),
            trailingHint: 'Opens your adherence history',
          ),
        ),
        if (summary.doses.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 4),
            child: _NoticeSlab(
              text: 'No doses are scheduled today. Add a reminder time to a '
                  'medication and it will appear here.',
            ),
          )
        else
          _ScheduleRail(summary: summary, onDoseTap: onMedicationTap),

        // ── Your medications ──────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
          child: MedHubSectionHeader(
            label: 'YOUR MEDICATIONS',
            trailing: '${summary.activeCount} ACTIVE',
            trailingColor: theme.accent,
          ),
        ),
        for (var i = 0; i < summary.medications.length; i++)
          Padding(
            padding: EdgeInsets.fromLTRB(18, i == 0 ? 0 : 12, 18, 0),
            child: MedHubMedicationCard(
              entry: summary.medications[i],
              floatIndex: i,
              onTap: () => onMedicationTap(summary.medications[i].medication),
            ),
          ),
      ],
    );
  }

  /// `2 TAKEN · 1 MISSED` — the prototype's rail readout, dropping a term that
  /// would read as a zero rather than reporting `0 MISSED`.
  static String _railSummary(MedicationHubSummary summary) {
    if (summary.doses.isEmpty) return 'NO DOSES';
    final parts = <String>['${summary.takenCount} TAKEN'];
    if (summary.missedCount > 0) parts.add('${summary.missedCount} MISSED');
    return parts.join(' · ');
  }
}

/// The horizontally-scrolling dose rail with its timeline rule beneath the
/// tiles.
///
/// The rail opens already showing the promoted dose — the prototype's
/// `revealNext(false)`, which scrolls with `behavior: 'auto'`, i.e. instantly.
/// It is applied as the scroll view's initial offset rather than a post-mount
/// scroll, so the rail is never briefly wrong and the reveal does not depend on
/// a second frame arriving.
class _ScheduleRail extends StatefulWidget {
  const _ScheduleRail({required this.summary, required this.onDoseTap});

  final MedicationHubSummary summary;
  final ValueChanged<MedicationModel> onDoseTap;

  @override
  State<_ScheduleRail> createState() => _ScheduleRailState();
}

class _ScheduleRailState extends State<_ScheduleRail> {
  ScrollController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Built once, with the offset the first frame should already be at. Any
    // out-of-range value is corrected by the scroll position on attach.
    _controller ??= ScrollController(initialScrollOffset: _revealOffset());
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// Where the promoted tile sits, measured in tile pitch: a resting tile plus
  /// the 10px gap.
  double _revealOffset() {
    final next = widget.summary.nextDose;
    if (next == null) return 0;
    final index = widget.summary.doses.indexOf(next);
    if (index <= 0) return 0;
    final pitch = medHubTileWidth(context, isNext: false) + 10;
    return index * pitch;
  }

  @override
  Widget build(BuildContext context) {
    final theme = MedicationHubTheme.of(context);
    final doses = widget.summary.doses;

    // How much of the day is behind the user, for the rule's lit segment.
    final settled = doses.where((d) => d.phase != HubDosePhase.later).length;
    final progress = doses.isEmpty ? 0.0 : settled / doses.length;

    // The rail takes its height from the tiles rather than a fixed number, so a
    // larger text size grows the tiles instead of clipping their captions.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // `top: 58px` — the rule runs behind the tiles.
        Positioned(
          left: 18,
          right: 18,
          top: medHubRailRuleTop(context),
          height: 1,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: theme.railRule(progress)),
            ),
          ),
        ),
        SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < doses.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                MedHubDoseTile(
                  dose: doses[i],
                  onTap: () => widget.onDoseTap(doses[i].medication),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Wraps [MedHubHero] in the prototype's scroll response:
/// `translateY(y·0.3)`, `scale(max(0.85, 1 − y·0.0005))`,
/// `opacity(max(0, 1 − y/230))`.
class _HeroSection extends StatelessWidget {
  const _HeroSection({
    required this.scroll,
    required this.activeCount,
    required this.takenCount,
    required this.scheduledCount,
    required this.nextName,
    required this.nextTime,
  });

  final ScrollController scroll;
  final int activeCount;
  final int takenCount;
  final int scheduledCount;
  final String? nextName;
  final String? nextTime;

  @override
  Widget build(BuildContext context) {
    final hero = MedHubHero(
      activeCount: activeCount,
      takenCount: takenCount,
      scheduledCount: scheduledCount,
      nextName: nextName,
      nextTime: nextTime,
    );

    if (AppMotion.reduceMotion(context)) return hero;

    return AnimatedBuilder(
      animation: scroll,
      child: hero,
      builder: (context, child) {
        final y = scroll.hasClients ? scroll.offset : 0.0;
        if (y <= 0) return child!;
        return Opacity(
          opacity: (1 - y / 230).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, y * 0.3),
            child: Transform.scale(
              scale: math.max(0.85, 1 - y * 0.0005),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

// ── Backdrop ─────────────────────────────────────────────────────────────────

/// The three ambient layers behind the content: the teal aurora (which
/// parallax-shifts with scroll at `0.12×`), a cool orb on the right, and the
/// receding perspective floor grid.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.scroll});

  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final theme = MedicationHubTheme.of(context);
    final size = MediaQuery.sizeOf(context);

    return Positioned.fill(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: Stack(
            children: [
              // `left/right: -20%; top: -16%; height: 600px`.
              AnimatedBuilder(
                animation: scroll,
                child: DecoratedBox(
                  decoration: BoxDecoration(gradient: theme.auroraFill),
                ),
                builder: (context, child) {
                  final y = scroll.hasClients ? scroll.offset : 0.0;
                  return Positioned(
                    left: -size.width * 0.2,
                    right: -size.width * 0.2,
                    top: -size.height * 0.16 + y * 0.12,
                    height: 600,
                    child: child!,
                  );
                },
              ),
              // `right: -25%; top: 34%; 420×380`.
              Positioned(
                right: -size.width * 0.25,
                top: size.height * 0.34,
                width: 420,
                height: 380,
                child: DecoratedBox(
                  decoration: BoxDecoration(gradient: theme.orbFill),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: -40,
                height: 300,
                child: CustomPaint(
                  painter: _FloorGridPainter(line: theme.line),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The prototype's floor: a 46px grid under `transform: perspective(240px)
/// rotateX(74deg)` with `transform-origin: bottom center`, faded out toward the
/// top by a mask.
///
/// Painted directly rather than transformed, because a projected grid is a few
/// lines of geometry and a `Transform` with that much foreshortening resamples
/// hairlines into mush. Transcribed from the Profile Hub's floor, which is the
/// same declaration.
class _FloorGridPainter extends CustomPainter {
  const _FloorGridPainter({required this.line});

  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final centerX = w / 2;

    double screenY(double depth) => h * (1 - 1 / (1 + depth * 3.2));

    for (var i = 0; i <= 14; i++) {
      final depth = i / 14;
      final y = screenY(depth);
      if (y >= h) continue;
      final fade = (1 - depth).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = line.withValues(alpha: line.a * fade * 0.45)
        ..strokeWidth = 1;
      canvas.drawLine(Offset(0, y), Offset(w, y), paint);
    }

    for (var i = -9; i <= 9; i++) {
      final xAtBase = centerX + i * 46.0;
      final paint = Paint()
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            line.withValues(alpha: line.a * 0.45),
            line.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h));
      canvas.drawLine(
        Offset(xAtBase, h),
        Offset(centerX + i * 46.0 * 0.06, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FloorGridPainter old) => old.line != line;
}

// ── Bottom action region ─────────────────────────────────────────────────────

/// The screen's actions, in their own space at the foot of the layout: the Add
/// Medication button, and the Check-In slab when there is a dose to confirm.
///
/// This is a **sibling** of the scrolling content, not an overlay on it — the
/// medication list ends where this region begins, so neither action can ever
/// cover a card. It keeps the prototype's material (the scrim, the FAB above
/// the slab at the right edge) and reserves clearance for `AppBottomNavBar`,
/// which `AppShell` draws below it.
class _BottomActions extends StatelessWidget {
  const _BottomActions({
    required this.subtitle,
    required this.onCheckIn,
    required this.onAdd,
  });

  /// Null hides the Check-In slab: while the hub is loading, and once nothing
  /// is left to confirm today. The region then carries the FAB alone.
  final String? subtitle;

  final VoidCallback onCheckIn;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = MedicationHubTheme.of(context);
    final hasCheckIn = subtitle != null;

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        14,
        16,
        // Clearance for `AppBottomNavBar` (68px bar + its 24px bottom inset +
        // its 8px top padding), matching the prototype's own 18px gap between
        // the slab and the bar.
        100 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(gradient: theme.bottomScrim),
      // One action row: the Check-In slab takes the width it can, the Add
      // button sits at the right edge alongside it. Stacking them would reserve
      // ~80px more of the screen than the list can spare on a 360×800 device.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (hasCheckIn) ...[
            Expanded(
              child: MedHubCheckInCta(subtitle: subtitle!, onTap: onCheckIn),
            ),
            const SizedBox(width: 12),
          ] else
            const Spacer(),
          MedHubFab(onTap: onAdd),
        ],
      ),
    );
  }
}

// ── Unhappy paths, in the prototype's own material ───────────────────────────

/// A quiet glass slab carrying one honest sentence.
class _NoticeSlab extends StatelessWidget {
  const _NoticeSlab({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = MedicationHubTheme.of(context);
    return MedHubSlab(
      radius: 16,
      blur: 14,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      shadow: theme.tileShadow,
      child: Text(
        text,
        style: medHubSans(
          context,
          size: 13,
          color: theme.txt2,
          height: 1.5,
        ),
      ),
    );
  }
}

class _HubLoading extends StatelessWidget {
  const _HubLoading();

  @override
  Widget build(BuildContext context) {
    final theme = MedicationHubTheme.of(context);
    return Center(
      child: Semantics(
        label: 'Loading medications',
        child: SizedBox(
          width: 34,
          height: 34,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            strokeCap: StrokeCap.round,
            color: theme.accent,
          ),
        ),
      ),
    );
  }
}

class _HubError extends StatelessWidget {
  const _HubError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = MedicationHubTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'UNABLE TO LOAD',
              style: medHubMono(
                context,
                size: 10,
                em: 0.28,
                color: theme.warn,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Your medications could not be loaded.',
              textAlign: TextAlign.center,
              style: medHubSans(
                context,
                size: 17,
                em: -0.02,
                color: theme.txt,
                weight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: medHubSans(
                context,
                size: 12.5,
                color: theme.txt2,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HubEmpty extends ConsumerWidget {
  const _HubEmpty();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = MedicationHubTheme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The hero's own capsule, at rest — the screen's identity object
            // rather than a generic icon.
            SizedBox(
              height: 96,
              child: Center(
                child: MedHubCapsule(
                  width: 118,
                  height: 52,
                  glow: theme.glow,
                  shadowColor: theme.shadowColor,
                  isDark: theme.isDark,
                ),
              ),
            ),
            const SizedBox(height: 26),
            Text(
              'MEDICATIONS',
              style: medHubMono(
                context,
                size: 10,
                em: 0.28,
                color: theme.txt2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No medications yet',
              textAlign: TextAlign.center,
              style: medHubSans(
                context,
                size: 22,
                em: -0.02,
                color: theme.txt,
                weight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Add your first medication and its reminder times, and your '
              'daily schedule will appear here.',
              textAlign: TextAlign.center,
              style: medHubSans(
                context,
                size: 13,
                color: theme.txt2,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
