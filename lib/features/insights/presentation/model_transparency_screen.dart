import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/core/widgets/medical_disclaimer.dart';
import 'package:fyp_foreseeme/features/insights/presentation/model_transparency_content.dart';

/// Model Transparency page (Sprint 5, Prompt 7).
///
/// Static, sourced documentation of how ForeSeeMe produces risk: data
/// provenance, label methodology, the model, honest evaluation, and limitations.
/// Every statement is drawn from the committed model card / label methodology
/// (see [kModelTransparencySections]) — nothing is generated. Pure presentation:
/// no providers, no Firebase, no business logic. Reachable from Health Insights.
class ModelTransparencyScreen extends StatelessWidget {
  const ModelTransparencyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
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
        title: Text('Model Transparency', style: context.fsmText.titleLarge),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  ForeSeeMeSpacing.gutter,
                  ForeSeeMeSpacing.sm,
                  ForeSeeMeSpacing.gutter,
                  ForeSeeMeSpacing.xxl,
                ),
                children: [
                  const AppReveal(child: _NotClinicalBanner()),
                  const SizedBox(height: ForeSeeMeSpacing.lg),
                  for (var i = 0; i < kModelTransparencySections.length; i++) ...[
                    AppReveal(
                      delayMs: 40 + i * 30,
                      child: _SectionCard(section: kModelTransparencySections[i]),
                    ),
                    const SizedBox(height: ForeSeeMeSpacing.md),
                  ],
                  const AppReveal(child: _CitationsCard()),
                  const SizedBox(height: ForeSeeMeSpacing.md),
                  const AppReveal(child: _FooterNote()),
                ],
              ),
            ),
            // Consistent non-diagnostic framing, as on every risk-/AI-facing
            // surface.
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

// ── The headline "not clinical" statement ────────────────────────────────────

class _NotClinicalBanner extends StatelessWidget {
  const _NotClinicalBanner();

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final accent = palette.tertiary;
    return Semantics(
      container: true,
      label: kNotClinicalStatement,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(ForeSeeMeRadius.lg),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, size: 20, color: accent),
            const SizedBox(width: ForeSeeMeSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'How ForeSeeMe works',
                    style: text.titleMedium?.copyWith(fontSize: 16),
                  ),
                  const SizedBox(height: ForeSeeMeSpacing.sm),
                  Text(
                    kNotClinicalStatement,
                    style: text.bodyLarge?.copyWith(color: palette.textPrimary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── A documented section ─────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final TransparencySection section;
  const _SectionCard({required this.section});

  @override
  Widget build(BuildContext context) {
    final text = context.fsmText;
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(section.title, style: text.titleMedium?.copyWith(fontSize: 16)),
          const SizedBox(height: ForeSeeMeSpacing.sm),
          for (final paragraph in section.paragraphs) ...[
            Text(paragraph, style: text.bodyLarge),
            const SizedBox(height: ForeSeeMeSpacing.sm),
          ],
          for (final bullet in section.bullets) ...[
            _Bullet(text: bullet),
            const SizedBox(height: ForeSeeMeSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet({required this.text});

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6, right: 10),
          child: Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: palette.secondary, shape: BoxShape.circle),
          ),
        ),
        Expanded(child: Text(text, style: context.fsmText.bodyLarge)),
      ],
    );
  }
}

// ── Citations ────────────────────────────────────────────────────────────────

class _CitationsCard extends StatelessWidget {
  const _CitationsCard();

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.menu_book_outlined, size: 16, color: palette.textSecondary),
              const SizedBox(width: ForeSeeMeSpacing.sm),
              Text('Key sources', style: text.titleMedium?.copyWith(fontSize: 16)),
            ],
          ),
          const SizedBox(height: ForeSeeMeSpacing.md),
          for (final citation in kTransparencyCitations) ...[
            _Bullet(text: citation),
            const SizedBox(height: ForeSeeMeSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _FooterNote extends StatelessWidget {
  const _FooterNote();

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.verified_outlined, size: 13, color: palette.textTertiary),
        const SizedBox(width: ForeSeeMeSpacing.sm),
        Expanded(
          child: Text(
            kTransparencyFooter,
            style: context.fsmText.bodySmall?.copyWith(color: palette.textTertiary),
          ),
        ),
      ],
    );
  }
}

// ── Shared glass card (matches the Insights / Risk Details surfaces) ─────────

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: ForeSeeMeSurface.card(context, radius: ForeSeeMeRadius.lg),
      child: child,
    );
  }
}
