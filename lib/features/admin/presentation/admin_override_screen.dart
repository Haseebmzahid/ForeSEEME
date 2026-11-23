import 'package:flutter/material.dart';
import 'admin_read.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/core/widgets/app_button.dart';
import 'package:fyp_foreseeme/features/admin/presentation/admin_providers.dart';
import 'package:fyp_foreseeme/features/admin/presentation/widgets/not_authorized_view.dart';
import 'package:fyp_foreseeme/features/health_profile/domain/constants/cities_constants.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_override.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_override_provider.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_visuals.dart';

/// Minimal, guarded internal surface for the manual risk-override safety valve
/// (Sprint 5, Prompt 13). Visible only to an admin-claim user (the entry point on
/// the profile screen is itself gated); this screen additionally fails closed if
/// the claim is absent, and Firestore rules enforce it server-side regardless.
///
/// Deliberately small: pick a city, set the level/disease + a required reason,
/// submit or clear. No batch tools or user management (do not over-build).
///
/// Hosted as a branch of [AdminShell] (Sprint M8.1) — it renders only its body
/// content; the shell provides the shared app bar/back button/bottom nav.
class AdminOverrideScreen extends ConsumerStatefulWidget {
  const AdminOverrideScreen({super.key});

  @override
  ConsumerState<AdminOverrideScreen> createState() =>
      _AdminOverrideScreenState();
}

/// The diseases the risk pipeline reports (kept in sync with the backend labels).
const List<String> _kDiseases = [
  'Dengue',
  'Smog',
  'Influenza',
  'Respiratory Illness',
  'Heat-Related Illness',
];

class _AdminOverrideScreenState extends ConsumerState<AdminOverrideScreen> {
  late String _city = kSupportedCities.first;
  RiskLevel _level = RiskLevel.high;
  late String _disease = _kDiseases.first;
  final _reasonController = TextEditingController();

  /// True only once submit/clear has actually been invoked. Needed because
  /// [AsyncNotifier.build] itself transitions `AsyncLoading` → `AsyncData` the
  /// moment the controller is first created — identical in shape to a real
  /// write completing — so gating the "saved" toast below on
  /// `previous is AsyncLoading` alone would show a false "Override saved."
  /// the instant this screen opens, before any write has happened. (Found
  /// while building Sprint M8.3's article form, which copied this listener
  /// pattern and turned the same latent bug into a broken auto-pop.)
  bool _submitted = false;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAdminAsync = ref.watch(isAdminProvider);

    // Surface submit/clear results without leaving the screen.
    ref.listen(adminOverrideControllerProvider, (previous, next) {
      next.whenOrNull(
        error: (e, _) {
          _submitted = false;
          _snack('Could not save override: $e', isError: true);
        },
        data: (_) {
          if (_submitted && previous is AsyncLoading) {
            _submitted = false;
            _snack('Override saved.');
          }
        },
      );
    });

    return SafeArea(
      child: isAdminAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: AdminReadError(
            message: 'Could not verify the administrator session.',
            error: error,
            retry: () => ref.invalidate(isAdminProvider),
          ),
        ),
        data: (isAdmin) => isAdmin ? _form() : const NotAuthorizedView(),
      ),
    );
  }

  Widget _form() {
    final controllerState = ref.watch(adminOverrideControllerProvider);
    final isBusy = controllerState.isLoading;
    final activeAsync = ref.watch(activeOverrideForCityProvider(_city));

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        ForeSeeMeSpacing.gutter,
        ForeSeeMeSpacing.md,
        ForeSeeMeSpacing.gutter,
        ForeSeeMeSpacing.xxxl,
      ),
      children: [
        const _InfoBanner(),
        const SizedBox(height: ForeSeeMeSpacing.lg),
        activeAsync.maybeWhen(
          data: (o) => o == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(bottom: ForeSeeMeSpacing.lg),
                  child: _ActiveOverrideCard(
                    riskOverride: o,
                    onClear: isBusy
                        ? null
                        : () {
                            _submitted = true;
                            ref
                                .read(adminOverrideControllerProvider.notifier)
                                .clear(_city);
                          },
                  ),
                ),
          error: (error, _) => AdminReadError(
            message: 'Could not load the current override.',
            error: error,
            retry: () => ref.invalidate(activeOverrideForCityProvider(_city)),
          ),
          orElse: () => const SizedBox.shrink(),
        ),
        _label('City'),
        _CityDropdown(
          value: _city,
          onChanged: (c) => setState(() => _city = c),
        ),
        const SizedBox(height: ForeSeeMeSpacing.lg),
        _label('Risk level'),
        _LevelSelector(
          value: _level,
          onChanged: (l) => setState(() => _level = l),
        ),
        const SizedBox(height: ForeSeeMeSpacing.lg),
        _label('Disease'),
        _DiseaseDropdown(
          value: _disease,
          onChanged: (d) => setState(() => _disease = d),
        ),
        const SizedBox(height: ForeSeeMeSpacing.lg),
        _label('Reason (required, shown to users)'),
        _ReasonField(controller: _reasonController),
        const SizedBox(height: ForeSeeMeSpacing.xxl),
        AppButton(
          text: 'Apply override',
          isLoading: isBusy,
          onPressed: isBusy ? null : _submit,
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      _snack('A reason is required — it is shown to users.', isError: true);
      return;
    }
    final city = _city;
    final disease = _disease;
    final level = _level;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apply manual override?'),
        content: Text(
          '${level.toJson()} risk for $disease in $city. The override expires in 24 hours.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _submitted = true;
    ref
        .read(adminOverrideControllerProvider.notifier)
        .submit(city: city, riskLevel: level, disease: disease, reason: reason);
  }

  void _snack(String message, {bool isError = false}) {
    if (!mounted) return;
    final palette = context.fsmPalette;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: context.fsmText.bodyLarge?.copyWith(
            color: isError ? palette.onError : palette.onSecondary,
          ),
        ),
        backgroundColor: isError ? palette.error : palette.secondary,
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: ForeSeeMeSpacing.sm),
    child: Text(
      text,
      style: context.fsmText.labelSmall?.copyWith(letterSpacing: 1.2),
    ),
  );
}

// ── Pieces ───────────────────────────────────────────────────────────────────

class _InfoBanner extends StatelessWidget {
  const _InfoBanner();

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final accent = palette.tertiary;
    return Container(
      padding: const EdgeInsets.all(ForeSeeMeSpacing.lg),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(ForeSeeMeRadius.md),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: accent),
          const SizedBox(width: ForeSeeMeSpacing.sm),
          Expanded(
            child: Text(
              'An override transparently replaces the automated estimate for a '
              'city and is labelled to users. Use only when the pipeline is '
              'delayed or wrong; clear it once the pipeline recovers.',
              style: context.fsmText.bodySmall?.copyWith(
                color: palette.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveOverrideCard extends StatelessWidget {
  final RiskOverride riskOverride;
  final VoidCallback? onClear;

  const _ActiveOverrideCard({
    required this.riskOverride,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final a = RiskVisuals.resolve(context, riskOverride.riskLevel);
    return Container(
      padding: const EdgeInsets.all(ForeSeeMeSpacing.lg),
      decoration: ForeSeeMeSurface.card(context, radius: ForeSeeMeRadius.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ACTIVE OVERRIDE',
            style: text.labelSmall?.copyWith(letterSpacing: 1.2),
          ),
          const SizedBox(height: ForeSeeMeSpacing.sm),
          Row(
            children: [
              Icon(a.icon, color: a.color, size: 20),
              const SizedBox(width: ForeSeeMeSpacing.sm),
              Text(
                '${a.headline} · ${riskOverride.disease}',
                style: text.bodyLarge?.copyWith(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('Reason: ${riskOverride.reason}', style: text.bodySmall),
          Text('By: ${riskOverride.authorEmail}', style: text.bodySmall),
          const SizedBox(height: ForeSeeMeSpacing.md),
          AppButton(
            text: 'Clear override',
            isOutlined: true,
            onPressed: onClear,
          ),
        ],
      ),
    );
  }
}

class _CityDropdown extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _CityDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    return _dropShell(
      context,
      DropdownButton<String>(
        value: value,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        dropdownColor: palette.surfaceContainerHigh,
        style: context.fsmText.bodyLarge?.copyWith(color: palette.textPrimary),
        items: [
          for (final c in kSupportedCities)
            DropdownMenuItem(value: c, child: Text(c)),
        ],
        onChanged: (v) => v == null ? null : onChanged(v),
      ),
    );
  }
}

class _DiseaseDropdown extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _DiseaseDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    return _dropShell(
      context,
      DropdownButton<String>(
        value: value,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        dropdownColor: palette.surfaceContainerHigh,
        style: context.fsmText.bodyLarge?.copyWith(color: palette.textPrimary),
        items: [
          for (final d in _kDiseases)
            DropdownMenuItem(value: d, child: Text(d)),
        ],
        onChanged: (v) => v == null ? null : onChanged(v),
      ),
    );
  }
}

Widget _dropShell(BuildContext context, Widget child) => Container(
  padding: const EdgeInsets.symmetric(horizontal: ForeSeeMeSpacing.lg),
  decoration: BoxDecoration(
    color: ForeSeeMeSurface.fill(context),
    borderRadius: BorderRadius.circular(ForeSeeMeRadius.sm),
    border: Border.all(color: ForeSeeMeSurface.stroke(context)),
  ),
  child: child,
);

class _LevelSelector extends StatelessWidget {
  final RiskLevel value;
  final ValueChanged<RiskLevel> onChanged;
  const _LevelSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final level in RiskLevel.values) ...[
          Expanded(child: _chip(context, level)),
          if (level != RiskLevel.values.last)
            const SizedBox(width: ForeSeeMeSpacing.sm),
        ],
      ],
    );
  }

  Widget _chip(BuildContext context, RiskLevel level) {
    final a = RiskVisuals.resolve(context, level);
    final palette = context.fsmPalette;
    final selected = level == value;
    return Semantics(
      button: true,
      selected: selected,
      label: a.label,
      child: GestureDetector(
        onTap: () => onChanged(level),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: ForeSeeMeSpacing.md),
          decoration: BoxDecoration(
            color: selected ? a.fill : ForeSeeMeSurface.fill(context),
            borderRadius: BorderRadius.circular(ForeSeeMeRadius.sm),
            border: Border.all(
              color: selected ? a.color : ForeSeeMeSurface.stroke(context),
            ),
          ),
          child: Column(
            children: [
              Icon(a.icon, color: a.color, size: 18),
              const SizedBox(height: ForeSeeMeSpacing.xs),
              Text(
                a.label,
                style: context.fsmText.bodySmall?.copyWith(
                  color: selected ? a.color : palette.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReasonField extends StatelessWidget {
  final TextEditingController controller;
  const _ReasonField({required this.controller});

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    return TextField(
      controller: controller,
      maxLines: 3,
      maxLength: 200,
      style: text.bodyLarge?.copyWith(color: palette.textPrimary),
      decoration: InputDecoration(
        hintText:
            'e.g. Pipeline delayed; AQI spiked per PMD advisory 2026-07-02.',
        hintStyle: text.bodySmall,
        filled: true,
        fillColor: ForeSeeMeSurface.fill(context),
        counterStyle: text.bodySmall,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ForeSeeMeRadius.sm),
          borderSide: BorderSide(color: ForeSeeMeSurface.stroke(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ForeSeeMeRadius.sm),
          borderSide: BorderSide(color: palette.secondary),
        ),
      ),
    );
  }
}
