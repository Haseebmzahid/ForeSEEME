import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/core/widgets/app_button.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/core/widgets/app_scaffold.dart';
import 'package:fyp_foreseeme/core/widgets/app_skeleton.dart';
import 'package:fyp_foreseeme/core/widgets/error_state.dart';
import 'package:fyp_foreseeme/core/widgets/app_text_field.dart';

import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/health_profile/domain/models/health_profile_model.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_state.dart';
import '../domain/constants/cities_constants.dart';
import '../domain/constants/conditions_constants.dart';

class HealthProfileScreen extends ConsumerStatefulWidget {
  final bool isEditMode;

  const HealthProfileScreen({super.key, this.isEditMode = false});

  @override
  ConsumerState<HealthProfileScreen> createState() =>
      _HealthProfileScreenState();
}

class _HealthProfileScreenState extends ConsumerState<HealthProfileScreen> {
  String? _selectedCity;
  final Set<String> _selectedConditions = {};
  final List<String> _customConditions = [];
  final _customConditionController = TextEditingController();
  String? _customConditionError;
  bool _dirty = false;
  bool _saveCompleted = false;

  // 2-step guided flow (S6C-03): 0 = city, 1 = conditions. Both steps write
  // into the same State fields above, so stepping back never loses a
  // selection — there is nothing to "restore", it was never cleared.
  int _currentStep = 0;

  // Edit mode only: whether the existing profile has been applied to the
  // fields above yet (guards against re-populating over the user's
  // in-progress edits on a later rebuild, and against getting stuck showing
  // the loading skeleton forever if the fetch resolves to no profile).
  bool _prefilled = false;

  /// Applies the fetched profile's real, already-saved selections to the form
  /// once (S6C-01) — restricted to the fixed option lists so stale/unknown
  /// stored values never select a chip the UI doesn't offer.
  void _applyExistingProfile(HealthProfileModel? profile) {
    if (_prefilled) return;
    setState(() {
      _prefilled = true;
      if (profile == null) return;
      _selectedCity = kSupportedCities.contains(profile.city)
          ? profile.city
          : null;
      _selectedConditions
        ..clear()
        ..addAll(
          profile.chronicConditions.where(kChronicConditions.contains),
        );
      _customConditions.addAll(profile.customConditions);
    });
  }

  void _onConditionToggle(String condition) {
    setState(() {
      _dirty = true;
      if (condition == 'None') {
        final shouldSelect = !_selectedConditions.contains('None');
        _selectedConditions.clear();
        if (shouldSelect) {
          _selectedConditions.add('None');
          _customConditions.clear();
          _customConditionError = null;
        }
      } else {
        _selectedConditions.remove('None');
        if (_selectedConditions.contains(condition)) {
          _selectedConditions.remove(condition);
        } else {
          _selectedConditions.add(condition);
        }
      }
    });
  }

  @override
  void dispose() {
    _customConditionController.dispose();
    super.dispose();
  }

  void _addCustomCondition() {
    final value = normalizeCustomCondition(_customConditionController.text);
    final error = validateCustomCondition(value, _customConditions);
    setState(() {
      _customConditionError = error;
      if (error != null) return;
      _dirty = true;
      _selectedConditions.remove('None');
      _customConditions.add(value);
      _customConditionController.clear();
    });
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard profile changes?'),
        content: const Text('Your changes have yet to be saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard changes'),
          ),
        ],
      ),
    );
    if (mounted && discard == true) context.pop();
  }

  void _showError(String message) {
    final palette = context.fsmPalette;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: context.fsmText.bodyLarge?.copyWith(color: palette.onError),
        ),
        backgroundColor: palette.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ForeSeeMeRadius.sm),
        ),
        margin: const EdgeInsets.all(ForeSeeMeSpacing.xxl),
      ),
    );
  }

  // AnimatedSwitcher (inside AppMotion.stateSwitcher) keeps the outgoing
  // child mounted for its whole fade-out. Keying the step subtree on
  // `_currentStep` itself means a fast Next → Back → Next (faster than the
  // 240ms transition) inserts a second child with the same key while the
  // first is still leaving — Flutter throws "Duplicate keys found." A
  // monotonically increasing key makes every transition unique regardless
  // of which step it lands on, so this can never collide.
  int _transitionKey = 0;

  void _goToConditionsStep() {
    if (_selectedCity == null) {
      _showError('Please select your city.');
      return;
    }
    setState(() {
      _currentStep = 1;
      _transitionKey++;
    });
  }

  void _goToCityStep() => setState(() {
    _currentStep = 0;
    _transitionKey++;
  });

  Future<void> _submit() async {
    if (_selectedCity == null) {
      _showError('Please select your city.');
      return;
    }

    final user = ref.read(authStateProvider).value;
    if (user == null || !user.emailVerified) return;
    final conditions = _selectedConditions.toList();
    final customConditions = List<String>.of(_customConditions);

    if (widget.isEditMode) {
      await ref
          .read(healthProfileNotifierProvider.notifier)
          .updateProfile(
            uid: user.uid,
            city: _selectedCity!,
            conditions: conditions,
            customConditions: customConditions,
          );
    } else {
      await ref
          .read(healthProfileNotifierProvider.notifier)
          .saveProfile(
            uid: user.uid,
            city: _selectedCity!,
            conditions: conditions,
            customConditions: customConditions,
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileState = ref.watch(healthProfileNotifierProvider);
    final isLoading = profileState is HealthProfileStateLoading;

    // Edit mode only: fetch the user's real, already-saved profile once so
    // the form opens prefilled instead of blank (S6C-01). Not watched outside
    // edit mode — a brand-new profile has nothing to fetch.
    final savedProfile = ref.watch(currentHealthProfileProvider);
    if (!_prefilled && savedProfile.hasValue) {
      // Schedule outside the build phase (setState can't run synchronously
      // here). Runs once: `_applyExistingProfile` flips `_prefilled`, which
      // stops this branch from re-scheduling on the next build.
      final profile = savedProfile.value;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyExistingProfile(profile);
      });
    }
    final prefillError = _prefilled ? null : savedProfile.error;
    final showPrefillSkeleton = !_prefilled && prefillError == null;

    ref.listen<HealthProfileState>(healthProfileNotifierProvider, (prev, next) {
      if (next is HealthProfileStateSaved) {
        setState(() => _saveCompleted = true);
        // Trigger profile existence refresh. The router's logic handles /home automatically on non-edit flows
        if (widget.isEditMode) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) context.pop();
          });
        } else {
          // Non-edit mode only ever runs once per account (the router only
          // routes here, un-edited, while the profile doesn't exist yet) —
          // so this is exactly first-run. Show the personalized "you're
          // set" confirmation (S6C-04) with the real just-saved city and
          // conditions, which itself hands off to the existing
          // value-explaining notification pre-prompt (S6C-02). Both are
          // pushed (not go), so the router's redirect never fights them —
          // it only forces `/home` from `/health-profile`/`/`/auth routes,
          // and by the time the user pops all the way back here, the
          // now-satisfied "has profile" redirect carries them the rest of
          // the way. No new navigation logic needed on the way back.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              context.push(
                '/profile-ready',
                extra: {
                  'city': _selectedCity,
                  'conditions': [
                    ..._selectedConditions,
                    ..._customConditions,
                  ],
                },
              );
              ref.invalidate(profileExistsProvider);
            }
          });
        }
      } else if (next is HealthProfileStateError) {
        if (mounted) {
          final palette = context.fsmPalette;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    color: palette.onError,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      next.message,
                      style: context.fsmText.bodyLarge?.copyWith(
                        color: palette.onError,
                      ),
                    ),
                  ),
                ],
              ),
              backgroundColor: palette.error,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ForeSeeMeRadius.sm),
              ),
              margin: const EdgeInsets.all(ForeSeeMeSpacing.xxl),
            ),
          );
        }
      }
    });

    return PopScope(
      // On step 2, back (system gesture, or the AppBar's back button in edit
      // mode) returns to step 1 instead of leaving the flow — "back
      // preserves entered data" is trivial here since nothing was ever
      // cleared, but leaving the screen entirely would still lose the
      // user's place in it. Once the save has actually succeeded, the
      // screen's own navigation (pop in edit mode) must go through as
      // normal, so the guard steps aside for that case.
      canPop:
          !isLoading &&
          ((_currentStep == 0 && !_dirty) ||
              _saveCompleted),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || isLoading) return;
        if (_currentStep != 0) {
          _goToCityStep();
        } else if (_dirty && context.canPop()) {
          _confirmDiscard();
        }
      },
      child: _buildScaffold(
        context,
        isLoading: isLoading,
        showPrefillSkeleton: showPrefillSkeleton,
        prefillError: prefillError,
      ),
    );
  }

  Widget _buildScaffold(
    BuildContext context, {
    required bool isLoading,
    required bool showPrefillSkeleton,
    required Object? prefillError,
  }) {
    final palette = context.fsmPalette;
    return AppScaffold(
      backgroundColor: palette.background,
      appBar: widget.isEditMode
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: BackButton(color: palette.textPrimary),
            )
          : null,
      body: prefillError != null
          ? ErrorState(
              title: "Couldn't load your profile",
              explanation:
                  'Something went wrong loading your saved city and '
                  'conditions. Please try again.',
              onRetry: () => ref.invalidate(currentHealthProfileProvider),
              detail: '$prefillError',
            )
          : showPrefillSkeleton
          ? const _HealthProfileSkeleton()
          : AppReveal(
              child: Column(
                children: [
                  SizedBox(
                    height: widget.isEditMode
                        ? ForeSeeMeSpacing.xs
                        : ForeSeeMeSpacing.huge,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: ForeSeeMeSpacing.gutter,
                    ),
                    child: _StepProgress(current: _currentStep, total: 2),
                  ),
                  Expanded(
                    child: AppMotion.stateSwitcher(
                      context,
                      KeyedSubtree(
                        key: ValueKey(_transitionKey),
                        child: _currentStep == 0
                            ? _buildCityStep()
                            : _buildConditionsStep(isLoading),
                      ),
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: (showPrefillSkeleton || prefillError != null)
          ? null
          : Container(
              padding: const EdgeInsets.all(
                ForeSeeMeSpacing.gutter,
              ).copyWith(top: ForeSeeMeSpacing.xxl),
              decoration: BoxDecoration(
                color: palette.background,
                border: Border(
                  top: BorderSide(color: palette.outlineVariant),
                ),
              ),
              child: SafeArea(
                child: _currentStep == 0
                    ? AppButton(text: 'Next', onPressed: _goToConditionsStep)
                    : Row(
                        children: [
                          Expanded(
                            child: AppButton(
                              text: 'Back',
                              isGhost: true,
                              onPressed: isLoading ? null : _goToCityStep,
                            ),
                          ),
                          const SizedBox(width: ForeSeeMeSpacing.xxl),
                          Expanded(
                            flex: 2,
                            child: AppButton(
                              text: widget.isEditMode
                                  ? 'Update Profile'
                                  : 'Save and continue',
                              isLoading: isLoading,
                              onPressed: isLoading ? null : _submit,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
    );
  }

  // ── Step 1: city ─────────────────────────────────────────────────────────

  Widget _buildCityStep() {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        ForeSeeMeSpacing.gutter,
        ForeSeeMeSpacing.huge,
        ForeSeeMeSpacing.gutter,
        120,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppReveal(
            child: Semantics(
              header: true,
              child: Text(
                widget.isEditMode ? 'Edit Health Profile' : 'Complete Profile',
                style: text.displayLarge?.copyWith(fontSize: 32),
              ),
            ),
          ),
          const SizedBox(height: ForeSeeMeSpacing.xs),
          AppReveal(
            delayMs: 50,
            child: Text(
              widget.isEditMode
                  ? 'Update your underlying health conditions.'
                  : "Let's personalize your medical experience.",
              style: text.bodyLarge?.copyWith(color: palette.textSecondary),
            ),
          ),
          const SizedBox(height: 80),
          AppReveal(
            delayMs: 100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Select Your City', style: text.headlineLarge),
                const SizedBox(height: ForeSeeMeSpacing.xxl),
                Wrap(
                  spacing: ForeSeeMeSpacing.md,
                  runSpacing: ForeSeeMeSpacing.md,
                  children: kSupportedCities.map((city) {
                    final isSelected = _selectedCity == city;
                    return ChoiceChip(
                      label: Text(city),
                      labelStyle: text.bodyLarge?.copyWith(
                        color: isSelected
                            ? palette.onPrimary
                            : palette.textPrimary,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                      selected: isSelected,
                      onSelected: (_) => setState(() {
                        _dirty = _dirty || city != _selectedCity;
                        _selectedCity = city;
                      }),
                      selectedColor: palette.primary,
                      backgroundColor: palette.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          ForeSeeMeRadius.full,
                        ),
                        side: BorderSide(
                          color: isSelected ? palette.primary : palette.outline,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      showCheckmark: false,
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 2: chronic conditions ──────────────────────────────────────────

  Widget _buildConditionsStep(bool isLoading) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        ForeSeeMeSpacing.gutter,
        ForeSeeMeSpacing.huge,
        ForeSeeMeSpacing.gutter,
        120,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppReveal(
            child: Semantics(
              header: true,
              child: Text('Underlying Conditions', style: text.headlineLarge),
            ),
          ),
          const SizedBox(height: ForeSeeMeSpacing.xs),
          AppReveal(
            delayMs: 50,
            child: Text(
              'Select any conditions that apply to you. This step is optional.',
              style: text.labelMedium?.copyWith(
                color: palette.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: ForeSeeMeSpacing.xxl),
          AppReveal(
            delayMs: 100,
            child: Wrap(
              spacing: ForeSeeMeSpacing.md,
              runSpacing: ForeSeeMeSpacing.md,
              children: kChronicConditions.map((condition) {
                final isSelected = _selectedConditions.contains(condition);
                return FilterChip(
                  label: Text(condition),
                  labelStyle: text.bodyLarge?.copyWith(
                    color: isSelected
                        ? palette.onPrimaryContainer
                        : palette.textPrimary,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                  selected: isSelected,
                  onSelected: isLoading
                      ? null
                      : (_) => _onConditionToggle(condition),
                  selectedColor: palette.primaryContainer,
                  backgroundColor: palette.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ForeSeeMeRadius.xxl),
                    side: BorderSide(
                      color: isSelected ? palette.primary : palette.outline,
                      width: isSelected
                          ? ForeSeeMeBorderWidth.thick
                          : ForeSeeMeBorderWidth.thin,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  showCheckmark: true,
                  checkmarkColor: palette.onPrimaryContainer,
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: ForeSeeMeSpacing.xxl),
          for (final condition in _customConditions)
            InputChip(
              label: Text(condition),
              onDeleted: isLoading
                  ? null
                  : () => setState(() {
                      _dirty = true;
                      _customConditions.remove(condition);
                      _customConditionError = null;
                    }),
            ),
          AppTextField(
            label: 'Custom condition',
            controller: _customConditionController,
            hint: 'Enter a condition name',
            onFieldSubmitted: isLoading
                ? null
                : (_) => _addCustomCondition(),
          ),
          if (_customConditionError case final error?)
            Semantics(liveRegion: true, child: Text(error)),
          TextButton(
            onPressed: isLoading ? null : _addCustomCondition,
            child: const Text('Add condition'),
          ),
        ],
      ),
    );
  }
}

/// A "Step X of N" label + segmented progress bar (Playbook S-1's stepper
/// polish). Purely presentational — [current] is 0-based.
class _StepProgress extends StatelessWidget {
  final int current;
  final int total;

  const _StepProgress({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    return Semantics(
      label: 'Step ${current + 1} of $total',
      child: ExcludeSemantics(
        child: Row(
          children: [
            Text(
              'Step ${current + 1} of $total',
              style: context.fsmText.labelMedium?.copyWith(
                color: palette.textSecondary,
              ),
            ),
            const SizedBox(width: ForeSeeMeSpacing.xxl),
            Expanded(
              child: Row(
                children: List.generate(total, (i) {
                  final filled = i <= current;
                  return Expanded(
                    child: Container(
                      margin: EdgeInsets.only(
                        right: i == total - 1 ? 0 : ForeSeeMeSpacing.xs,
                      ),
                      height: 4,
                      decoration: BoxDecoration(
                        color: filled ? palette.primary : palette.outline,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Edit-mode-only loading placeholder shown while the user's existing
/// profile is fetched to prefill the form (S6C-01). Mirrors step 1's real
/// shape — progress bar, heading, a row of city-chip-sized blocks — since
/// that's the step the form actually opens on (S6C-03), so the
/// skeleton-to-content swap is a single beat, not a layout jump.
class _HealthProfileSkeleton extends StatelessWidget {
  const _HealthProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: ForeSeeMeSpacing.gutter),
      child: AppSkeleton(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: ForeSeeMeSpacing.xxl),
            SkeletonBar(width: double.infinity, height: 4, radius: 2),
            SizedBox(height: 80),
            SkeletonBar(width: 200, height: 28),
            SizedBox(height: ForeSeeMeSpacing.xs),
            SkeletonBar(width: 260, height: 16),
            SizedBox(height: 80),
            SkeletonBar(width: 140, height: 20),
            SizedBox(height: ForeSeeMeSpacing.xxl),
            Wrap(
              spacing: ForeSeeMeSpacing.md,
              runSpacing: ForeSeeMeSpacing.md,
              children: [
                SkeletonBox(width: 92, height: 40, radius: 100),
                SkeletonBox(width: 92, height: 40, radius: 100),
                SkeletonBox(width: 92, height: 40, radius: 100),
                SkeletonBox(width: 92, height: 40, radius: 100),
                SkeletonBox(width: 92, height: 40, radius: 100),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
