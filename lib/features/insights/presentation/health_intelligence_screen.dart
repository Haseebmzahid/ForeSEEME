import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/core/widgets/app_skeleton.dart';
import 'package:fyp_foreseeme/core/widgets/medical_disclaimer.dart';
import 'package:fyp_foreseeme/core/widgets/timeline_row.dart';
import 'package:fyp_foreseeme/features/insights/domain/models/health_intelligence.dart';
import 'package:fyp_foreseeme/features/insights/presentation/insights_providers.dart';
import 'package:fyp_foreseeme/features/insights/presentation/recommendations_card.dart';
import 'package:fyp_foreseeme/features/insights/presentation/widgets/health_contributor_card.dart';
import 'package:fyp_foreseeme/features/resources/presentation/resources_providers.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/emergency_card.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/environment_tiles.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/explanation_panel.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_visuals.dart';

/// **Explainable Health Intelligence** (Sprint M-EHI) — the destination of
/// "Explore Your Health", replacing the earlier Health Insights screen.
///
/// It answers *why* — not just *what* — for today's health standing, composing
/// signals ForeSeeMe already computes into one coherent brief: a summary, the
/// "Why?" contributors, expandable contributor cards, cited recommendations, a
/// trend explanation, today's timeline, and the environmental context. It
/// introduces **no new data source** and **no generated medical text**: the
/// narrative is a deterministic template over stored data (via
/// [healthIntelligenceProvider]); every advisory is an existing cited, guarded
/// surface; and the non-diagnostic disclaimer is pinned below at all times.
class HealthIntelligenceScreen extends ConsumerWidget {
  const HealthIntelligenceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.fsmPalette;
    final async = ref.watch(healthIntelligenceProvider);

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        foregroundColor: palette.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => context.pop(),
        ),
        title: Text('Health Intelligence', style: context.fsmText.titleLarge),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: async.when(
                loading: () => const _LoadingState(),
                error: (_, _) => const _ErrorState(),
                data: (view) => _Content(view: view),
              ),
            ),
            // Pinned non-diagnostic framing — always visible, consistent with
            // Risk Details and the alert inbox.
            const Padding(
              padding: EdgeInsets.fromLTRB(
                ForeSeeMeSpacing.gutter,
                ForeSeeMeSpacing.sm,
                ForeSeeMeSpacing.gutter,
                ForeSeeMeSpacing.lg,
              ),
              child: MedicalDisclaimer.banner(),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Body ─────────────────────────────────────────────────────────────────────

class _Content extends StatelessWidget {
  const _Content({required this.view});

  final HealthIntelligenceView view;

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        ForeSeeMeSpacing.gutter,
        ForeSeeMeSpacing.sm,
        ForeSeeMeSpacing.gutter,
        ForeSeeMeSpacing.gutter,
      ),
      children: [
        AppReveal(
          child: Text(
            'A plain-language look at why your health status is what it is today '
            '— and what it’s built from.',
            style: context.fsmText.bodyLarge?.copyWith(
              color: palette.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: ForeSeeMeSpacing.gutter),

        // 1 — Health Summary ("How am I?")
        AppReveal(delayMs: 60, child: _SummaryCard(summary: view.summary)),
        const SizedBox(height: ForeSeeMeSpacing.xxl),

        // Emergency affordance — only on a High estimate (Content Safety Policy).
        if (view.isHighRisk) ...[
          const AppReveal(delayMs: 90, child: _EmergencyAffordance()),
          const SizedBox(height: ForeSeeMeSpacing.xxl),
        ],

        // 2 — Why? (signature) + the model-level detail panel.
        AppReveal(
          delayMs: 120,
          child: _WhyCard(title: view.whyTitle, reasons: view.whyReasons),
        ),
        const SizedBox(height: ForeSeeMeSpacing.lg),
        const AppReveal(delayMs: 150, child: ExplanationPanel()),
        const SizedBox(height: ForeSeeMeSpacing.xxl),

        // 3 — Health Contributors
        _SectionHeader(
          icon: Icons.tune_rounded,
          label: 'WHAT AFFECTS YOU',
        ),
        const SizedBox(height: ForeSeeMeSpacing.md),
        for (var i = 0; i < view.contributors.length; i++) ...[
          AppReveal(
            delayMs: 180 + i * 40,
            child: HealthContributorCard(contributor: view.contributors[i]),
          ),
          if (i != view.contributors.length - 1)
            const SizedBox(height: ForeSeeMeSpacing.md),
        ],
        const SizedBox(height: ForeSeeMeSpacing.xxl),

        // 4 — Recommendations (cited, guarded — reuses the existing surfaces).
        _SectionHeader(
          icon: Icons.recommend_outlined,
          label: 'RECOMMENDED TODAY',
        ),
        const SizedBox(height: ForeSeeMeSpacing.md),
        const AppReveal(delayMs: 220, child: RecommendationsCard()),
        const SizedBox(height: ForeSeeMeSpacing.xxl),

        // 5 — Trend Explanation ("What changed this week?")
        if (view.trendChanges.isNotEmpty) ...[
          AppReveal(
            delayMs: 260,
            child: _TrendChangesCard(changes: view.trendChanges),
          ),
          const SizedBox(height: ForeSeeMeSpacing.xxl),
        ],

        // 6 — Health Timeline ("What happened today?")
        if (view.timeline.isNotEmpty) ...[
          AppReveal(
            delayMs: 300,
            child: _TimelineCard(entries: view.timeline),
          ),
          const SizedBox(height: ForeSeeMeSpacing.xxl),
        ],

        // 7 — Environmental Context
        if (view.environment.hasData && view.estimate != null) ...[
          _SectionHeader(icon: Icons.eco_outlined, label: 'ENVIRONMENT'),
          const SizedBox(height: ForeSeeMeSpacing.md),
          AppReveal(
            delayMs: 340,
            child: _EnvironmentContextCard(
              context_: view.environment,
              estimate: view.estimate!,
            ),
          ),
          const SizedBox(height: ForeSeeMeSpacing.xxl),
        ],

        // 8 — Learn More (reuses existing educational destinations).
        _SectionHeader(icon: Icons.school_outlined, label: 'LEARN MORE'),
        const SizedBox(height: ForeSeeMeSpacing.md),
        const AppReveal(
          delayMs: 380,
          child: _NavLink(
            icon: Icons.map_outlined,
            title: 'Geospatial risk map',
            subtitle: 'Explore risk across every supported city',
            route: '/risk-map',
          ),
        ),
        const SizedBox(height: ForeSeeMeSpacing.md),
        const AppReveal(
          delayMs: 410,
          child: _NavLink(
            icon: Icons.calendar_month_rounded,
            title: "This week's report",
            subtitle: 'Your risk, routine and cited guidance',
            route: '/weekly-report',
          ),
        ),
        const SizedBox(height: ForeSeeMeSpacing.md),
        const AppReveal(
          delayMs: 440,
          child: _NavLink(
            icon: Icons.info_outline_rounded,
            title: 'How ForeSeeMe works',
            subtitle: 'Data, methodology, and honest limits',
            route: '/model-transparency',
          ),
        ),
        const SizedBox(height: ForeSeeMeSpacing.md),
        const AppReveal(
          delayMs: 470,
          child: _NavLink(
            icon: Icons.menu_book_rounded,
            title: 'Learn & resources',
            subtitle: 'Asthma triggers, air quality and WHO guidance',
            route: '/resources',
            isShellBranch: true,
          ),
        ),
      ],
    );
  }
}

// ── Section 1: Summary ───────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final HealthSummary summary;

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final appearance = summary.level == null
        ? null
        : RiskVisuals.resolve(context, summary.level!);
    final accent = appearance?.color ?? palette.textTertiary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: ForeSeeMeSurface.card(
        context,
        borderColor: accent.withValues(alpha: 0.30),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "TODAY'S HEALTH SUMMARY",
            style: text.labelSmall?.copyWith(
              letterSpacing: 1.2,
              color: palette.textTertiary,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(ForeSeeMeRadius.sm),
                ),
                child: Icon(
                  appearance?.icon ?? Icons.help_outline_rounded,
                  color: accent,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.levelLabel,
                      style: text.headlineSmall?.copyWith(color: accent),
                    ),
                    if (summary.confidencePercent != null)
                      Text(
                        'Confidence ${summary.confidencePercent}%',
                        style: text.bodySmall?.copyWith(
                          color: palette.textTertiary,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            summary.assessment,
            style: text.bodyLarge?.copyWith(
              color: palette.textPrimary,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Emergency affordance (high risk only) ────────────────────────────────────

class _EmergencyAffordance extends ConsumerWidget {
  const _EmergencyAffordance();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contact = ref.watch(emergencyContactProvider);
    return EmergencyCard(
      contact: contact,
      onCall: () => ref.read(launcherServiceProvider).dialPhone(contact.number),
    );
  }
}

// ── Section 2: Why? ──────────────────────────────────────────────────────────

class _WhyCard extends StatelessWidget {
  const _WhyCard({required this.title, required this.reasons});

  final String title;
  final List<WhyReason> reasons;

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: ForeSeeMeSurface.card(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.help_outline_rounded, size: 20, color: palette.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: text.titleLarge?.copyWith(fontSize: 18),
                ),
              ),
            ],
          ),
          if (reasons.isEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'As your risk estimate and routine build up, the factors behind '
              'them will appear here.',
              style: text.bodyMedium?.copyWith(color: palette.textSecondary),
            ),
          ] else ...[
            const SizedBox(height: 6),
            for (final reason in reasons) _ReasonRow(reason: reason),
          ],
        ],
      ),
    );
  }
}

class _ReasonRow extends StatelessWidget {
  const _ReasonRow({required this.reason});

  final WhyReason reason;

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final positive = reason.tone == ReasonTone.positive;
    final color = positive ? context.fsmColors.success : context.fsmColors.warning;
    final icon = positive
        ? Icons.check_circle_rounded
        : Icons.error_outline_rounded;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              reason.text,
              style: text.bodyLarge?.copyWith(
                color: palette.textPrimary,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section 5: Trend changes ─────────────────────────────────────────────────

class _TrendChangesCard extends StatelessWidget {
  const _TrendChangesCard({required this.changes});

  final List<TrendChange> changes;

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: ForeSeeMeSurface.card(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('This Week', style: text.titleLarge),
          const SizedBox(height: 4),
          Text(
            'What changed since last week',
            style: text.bodySmall?.copyWith(color: palette.textTertiary),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < changes.length; i++) ...[
            _ChangeRow(change: changes[i]),
            if (i != changes.length - 1) ...[
              const SizedBox(height: 12),
              Divider(height: 1, color: palette.outlineVariant),
              const SizedBox(height: 12),
            ],
          ],
        ],
      ),
    );
  }
}

class _ChangeRow extends StatelessWidget {
  const _ChangeRow({required this.change});

  final TrendChange change;

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final (color, icon) = switch (change.direction) {
      TrendChangeDirection.improved => (
        context.fsmColors.success,
        Icons.trending_up_rounded,
      ),
      TrendChangeDirection.worsened => (
        palette.error,
        Icons.trending_down_rounded,
      ),
      TrendChangeDirection.steady => (
        palette.textSecondary,
        Icons.trending_flat_rounded,
      ),
    };
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            change.label,
            style: text.bodyLarge?.copyWith(color: palette.textPrimary),
          ),
        ),
        Text(
          change.detail,
          style: text.titleMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

// ── Section 6: Timeline ──────────────────────────────────────────────────────

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.entries});

  final List<TimelineEntry> entries;

  @override
  Widget build(BuildContext context) {
    final text = context.fsmText;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: ForeSeeMeSurface.card(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Today's Timeline", style: text.titleLarge),
          const SizedBox(height: 16),
          for (var i = 0; i < entries.length; i++)
            _TimelineRow(
              entry: entries[i],
              isLast: i == entries.length - 1,
            ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.entry, required this.isLast});

  final TimelineEntry entry;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final (color, icon) = switch (entry.marker) {
      TimelineMarker.done => (context.fsmColors.success, Icons.check_rounded),
      TimelineMarker.pending => (context.fsmColors.warning, Icons.schedule_rounded),
      TimelineMarker.missed => (palette.error, Icons.close_rounded),
      TimelineMarker.info => (context.fsmColors.info, Icons.air_rounded),
      TimelineMarker.upcoming => (palette.secondary, Icons.arrow_forward_rounded),
    };

    return TimelineRow(
      eyebrow: entry.period,
      title: entry.text,
      icon: icon,
      color: color,
      isLast: isLast,
    );
  }
}

// ── Section 7: Environmental context ─────────────────────────────────────────

class _EnvironmentContextCard extends StatelessWidget {
  const _EnvironmentContextCard({
    required EnvironmentalContext context_,
    required this.estimate,
  }) : _ctx = context_;

  final EnvironmentalContext _ctx;
  final RiskEstimateModel estimate;

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Reuse the shared AQI + weather tiles — no new environmental widget.
        EnvironmentTiles(estimate: estimate),
        if (_ctx.primaryTriggerLabel != null &&
            _ctx.primaryTriggerNote != null) ...[
          const SizedBox(height: ForeSeeMeSpacing.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: ForeSeeMeSurface.card(context, radius: ForeSeeMeRadius.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: context.fsmColors.warning,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Today's biggest factor: ${_ctx.primaryTriggerLabel}",
                        style: text.titleMedium?.copyWith(fontSize: 15),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _ctx.primaryTriggerNote!,
                        style: text.bodySmall?.copyWith(
                          color: palette.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ── Shared bits ──────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    return Row(
      children: [
        Icon(icon, size: 16, color: palette.textTertiary),
        const SizedBox(width: 8),
        Text(
          label,
          style: context.fsmText.labelSmall?.copyWith(letterSpacing: 1.2),
        ),
      ],
    );
  }
}

/// A tappable navigation row (glass card) for the Learn More sub-pages. Mirrors
/// the app's shell-branch routing: a tab route (`/resources`) is reached with
/// `go()`, a stacked route with `push()`.
class _NavLink extends StatelessWidget {
  const _NavLink({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
    this.isShellBranch = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
  final bool isShellBranch;

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    return Semantics(
      button: true,
      label: '$title — $subtitle',
      child: InkWell(
        borderRadius: BorderRadius.circular(ForeSeeMeRadius.lg),
        onTap: () => isShellBranch ? context.go(route) : context.push(route),
        child: Container(
          padding: const EdgeInsets.all(ForeSeeMeSpacing.lg),
          decoration: BoxDecoration(
            color: palette.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(ForeSeeMeRadius.lg),
            border: Border.all(color: palette.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: palette.secondary),
              const SizedBox(width: ForeSeeMeSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: text.bodyLarge?.copyWith(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: text.bodySmall?.copyWith(color: palette.textTertiary),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: palette.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Async states ─────────────────────────────────────────────────────────────

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        ForeSeeMeSpacing.gutter,
        ForeSeeMeSpacing.lg,
        ForeSeeMeSpacing.gutter,
        ForeSeeMeSpacing.gutter,
      ),
      children: const [
        AppSkeleton(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBar(width: 220, height: 14),
              SizedBox(height: 20),
              SkeletonBox(height: 140, radius: 20),
              SizedBox(height: 20),
              SkeletonBox(height: 180, radius: 20),
              SizedBox(height: 20),
              SkeletonBox(height: 120, radius: 20),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState();

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ForeSeeMeSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 40,
              color: palette.textTertiary,
            ),
            const SizedBox(height: 14),
            Text(
              'Your health intelligence is unavailable right now',
              textAlign: TextAlign.center,
              style: text.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Check your connection and try again shortly.',
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: palette.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
