import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/app_design_v2.dart';
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
    return Scaffold(
      backgroundColor: AppColorsV2.shell,
      appBar: AppBar(
        backgroundColor: AppColorsV2.shell,
        elevation: 0,
        foregroundColor: AppColorsV2.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => context.pop(),
        ),
        title: Text('Model Transparency', style: AppTextStylesV2.cardTitle),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  const AppReveal(child: _NotClinicalBanner()),
                  const SizedBox(height: 18),
                  for (var i = 0; i < kModelTransparencySections.length; i++) ...[
                    AppReveal(
                      delayMs: 40 + i * 30,
                      child: _SectionCard(section: kModelTransparencySections[i]),
                    ),
                    const SizedBox(height: 16),
                  ],
                  const AppReveal(child: _CitationsCard()),
                  const SizedBox(height: 16),
                  const AppReveal(child: _FooterNote()),
                ],
              ),
            ),
            // Consistent non-diagnostic framing, as on every risk-/AI-facing
            // surface.
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
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
    return Semantics(
      container: true,
      label: kNotClinicalStatement,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColorsV2.violet.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColorsV2.violet.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.info_outline_rounded,
              size: 20,
              color: AppColorsV2.violet,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'How ForeSeeMe works',
                    style: AppTextStylesV2.cardTitle.copyWith(fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    kNotClinicalStatement,
                    style: AppTextStylesV2.body.copyWith(
                      color: AppColorsV2.textPrimary,
                    ),
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
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.title,
            style: AppTextStylesV2.cardTitle.copyWith(fontSize: 16),
          ),
          const SizedBox(height: 10),
          for (final paragraph in section.paragraphs) ...[
            Text(paragraph, style: AppTextStylesV2.body),
            const SizedBox(height: 10),
          ],
          for (final bullet in section.bullets) ...[
            _Bullet(text: bullet),
            const SizedBox(height: 8),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6, right: 10),
          child: Container(
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
              color: AppColorsV2.teal,
              shape: BoxShape.circle,
            ),
          ),
        ),
        Expanded(child: Text(text, style: AppTextStylesV2.body)),
      ],
    );
  }
}

// ── Citations ────────────────────────────────────────────────────────────────

class _CitationsCard extends StatelessWidget {
  const _CitationsCard();

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.menu_book_outlined,
                size: 16,
                color: AppColorsV2.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                'Key sources',
                style: AppTextStylesV2.cardTitle.copyWith(fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final citation in kTransparencyCitations) ...[
            _Bullet(text: citation),
            const SizedBox(height: 8),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.verified_outlined,
          size: 13,
          color: AppColorsV2.textFaint,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            kTransparencyFooter,
            style: AppTextStylesV2.caption.copyWith(
              color: AppColorsV2.textFaint,
            ),
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
      decoration: BoxDecoration(
        color: AppColorsV2.glassFill,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColorsV2.stroke),
      ),
      child: child,
    );
  }
}
