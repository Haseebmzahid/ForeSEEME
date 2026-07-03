import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/app_design_v2.dart';
import 'package:fyp_foreseeme/core/widgets/app_button.dart';
import 'package:fyp_foreseeme/features/admin/presentation/admin_providers.dart';
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
/// submit or clear. No dashboards, batch tools, or user management (do not
/// over-build).
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
        error: (e, _) => _snack('Could not save override: $e', isError: true),
        data: (_) {
          if (previous is AsyncLoading) _snack('Override saved.');
        },
      );
    });

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
        title: Text('Risk Override', style: AppTextStylesV2.cardTitle),
      ),
      body: SafeArea(
        child: isAdminAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const _NotAuthorized(),
          data: (isAdmin) => isAdmin ? _form() : const _NotAuthorized(),
        ),
      ),
    );
  }

  Widget _form() {
    final controllerState = ref.watch(adminOverrideControllerProvider);
    final isBusy = controllerState.isLoading;
    final activeAsync = ref.watch(activeOverrideForCityProvider(_city));

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        _InfoBanner(),
        const SizedBox(height: 18),
        activeAsync.maybeWhen(
          data: (o) => o == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: _ActiveOverrideCard(
                    riskOverride: o,
                    onClear: isBusy
                        ? null
                        : () => ref
                            .read(adminOverrideControllerProvider.notifier)
                            .clear(_city),
                  ),
                ),
          orElse: () => const SizedBox.shrink(),
        ),
        _label('City'),
        _CityDropdown(
          value: _city,
          onChanged: (c) => setState(() => _city = c),
        ),
        const SizedBox(height: 18),
        _label('Risk level'),
        _LevelSelector(
          value: _level,
          onChanged: (l) => setState(() => _level = l),
        ),
        const SizedBox(height: 18),
        _label('Disease'),
        _DiseaseDropdown(
          value: _disease,
          onChanged: (d) => setState(() => _disease = d),
        ),
        const SizedBox(height: 18),
        _label('Reason (required, shown to users)'),
        _ReasonField(controller: _reasonController),
        const SizedBox(height: 24),
        AppButton(
          text: 'Apply override',
          isLoading: isBusy,
          onPressed: isBusy ? null : _submit,
        ),
      ],
    );
  }

  void _submit() {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      _snack('A reason is required — it is shown to users.', isError: true);
      return;
    }
    ref.read(adminOverrideControllerProvider.notifier).submit(
          city: _city,
          riskLevel: _level,
          disease: _disease,
          reason: reason,
        );
  }

  void _snack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColorsV2.riskHigh : AppColorsV2.teal,
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: AppTextStylesV2.microLabel),
      );
}

// ── Pieces ───────────────────────────────────────────────────────────────────

class _NotAuthorized extends StatelessWidget {
  const _NotAuthorized();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.lock_outline_rounded,
              size: 48,
              color: AppColorsV2.textTertiary,
            ),
            const SizedBox(height: 14),
            Text(
              'Not authorized',
              style: AppTextStylesV2.cardTitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'This area is restricted to operators. If you believe this is an '
              'error, contact an administrator.',
              style: AppTextStylesV2.body,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColorsV2.violet.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColorsV2.violet.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: AppColorsV2.violet,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'An override transparently replaces the automated estimate for a '
              'city and is labelled to users. Use only when the pipeline is '
              'delayed or wrong; clear it once the pipeline recovers.',
              style: AppTextStylesV2.caption.copyWith(
                color: AppColorsV2.textSecondary,
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

  const _ActiveOverrideCard({required this.riskOverride, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final a = RiskVisuals.forLevel(riskOverride.riskLevel);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColorsV2.glassFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColorsV2.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ACTIVE OVERRIDE', style: AppTextStylesV2.microLabel),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(a.icon, color: a.color, size: 20),
              const SizedBox(width: 8),
              Text(
                '${a.headline} · ${riskOverride.disease}',
                style: AppTextStylesV2.body.copyWith(
                  color: AppColorsV2.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('Reason: ${riskOverride.reason}', style: AppTextStylesV2.caption),
          Text('By: ${riskOverride.authorEmail}', style: AppTextStylesV2.caption),
          const SizedBox(height: 12),
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
    return _dropShell(
      DropdownButton<String>(
        value: value,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        dropdownColor: AppColorsV2.shellRaised,
        style: AppTextStylesV2.body.copyWith(color: AppColorsV2.textPrimary),
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
    return _dropShell(
      DropdownButton<String>(
        value: value,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        dropdownColor: AppColorsV2.shellRaised,
        style: AppTextStylesV2.body.copyWith(color: AppColorsV2.textPrimary),
        items: [
          for (final d in _kDiseases)
            DropdownMenuItem(value: d, child: Text(d)),
        ],
        onChanged: (v) => v == null ? null : onChanged(v),
      ),
    );
  }
}

Widget _dropShell(Widget child) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColorsV2.glassFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColorsV2.stroke),
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
          Expanded(child: _chip(level)),
          if (level != RiskLevel.values.last) const SizedBox(width: 10),
        ],
      ],
    );
  }

  Widget _chip(RiskLevel level) {
    final a = RiskVisuals.forLevel(level);
    final selected = level == value;
    return Semantics(
      button: true,
      selected: selected,
      label: a.label,
      child: GestureDetector(
        onTap: () => onChanged(level),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? a.fill : AppColorsV2.glassFill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? a.color : AppColorsV2.stroke,
            ),
          ),
          child: Column(
            children: [
              Icon(a.icon, color: a.color, size: 18),
              const SizedBox(height: 4),
              Text(
                a.label,
                style: AppTextStylesV2.caption.copyWith(
                  color: selected ? a.color : AppColorsV2.textSecondary,
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
    return TextField(
      controller: controller,
      maxLines: 3,
      maxLength: 200,
      style: AppTextStylesV2.body.copyWith(color: AppColorsV2.textPrimary),
      decoration: InputDecoration(
        hintText: 'e.g. Pipeline delayed; AQI spiked per PMD advisory 2026-07-02.',
        hintStyle: AppTextStylesV2.caption,
        filled: true,
        fillColor: AppColorsV2.glassFill,
        counterStyle: AppTextStylesV2.caption,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColorsV2.stroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColorsV2.teal),
        ),
      ),
    );
  }
}
