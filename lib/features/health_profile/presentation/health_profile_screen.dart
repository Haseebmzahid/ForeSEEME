import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/app_colors.dart';
import 'package:fyp_foreseeme/core/theme/app_theme.dart';
import 'package:fyp_foreseeme/core/widgets/app_button.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/core/widgets/app_scaffold.dart';
import 'package:fyp_foreseeme/core/widgets/app_skeleton.dart';
import 'package:fyp_foreseeme/core/widgets/error_state.dart';

import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/health_profile/domain/models/health_profile_model.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_state.dart';

class HealthProfileScreen extends ConsumerStatefulWidget {
  final bool isEditMode;

  const HealthProfileScreen({super.key, this.isEditMode = false});

  @override
  ConsumerState<HealthProfileScreen> createState() =>
      _HealthProfileScreenState();
}

class _HealthProfileScreenState extends ConsumerState<HealthProfileScreen> {
  final List<String> _cities = [
    'Lahore',
    'Islamabad',
    'Karachi',
    'Rawalpindi',
    'Peshawar',
  ];

  final List<String> _conditionsOptions = [
    'Asthma',
    'Diabetes',
    'Hypertension',
    'Heart Disease',
    'None',
  ];

  String? _selectedCity;
  final Set<String> _selectedConditions = {};

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
      _selectedCity = _cities.contains(profile.city) ? profile.city : null;
      _selectedConditions
        ..clear()
        ..addAll(profile.chronicConditions.where(_conditionsOptions.contains));
    });
  }

  void _onConditionToggle(String condition) {
    setState(() {
      if (condition == 'None') {
        _selectedConditions.clear();
        _selectedConditions.add('None');
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

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: AppTextStyles.bodyText.copyWith(color: Colors.white),
        ),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(AppSpacing.md),
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

    if (_selectedConditions.isEmpty) {
      _showError('Please select at least one condition or "None".');
      return;
    }

    final uid = ref.read(authStateProvider).value?.uid;
    if (uid == null) return;

    if (widget.isEditMode) {
      await ref
          .read(healthProfileNotifierProvider.notifier)
          .updateProfile(
            uid: uid,
            city: _selectedCity!,
            conditions: _selectedConditions.toList(),
          );
    } else {
      await ref
          .read(healthProfileNotifierProvider.notifier)
          .saveProfile(
            uid: uid,
            city: _selectedCity!,
            conditions: _selectedConditions.toList(),
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
    final editProfileAsync = widget.isEditMode
        ? ref.watch(currentHealthProfileProvider)
        : null;
    if (widget.isEditMode &&
        !_prefilled &&
        (editProfileAsync?.hasValue ?? false)) {
      // Schedule outside the build phase (setState can't run synchronously
      // here). Runs once: `_applyExistingProfile` flips `_prefilled`, which
      // stops this branch from re-scheduling on the next build.
      final profile = editProfileAsync!.value;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyExistingProfile(profile);
      });
    }
    final showPrefillSkeleton =
        widget.isEditMode &&
        !_prefilled &&
        (editProfileAsync?.isLoading ?? false);
    final prefillError = widget.isEditMode && !_prefilled
        ? editProfileAsync?.error
        : null;

    ref.listen<HealthProfileState>(healthProfileNotifierProvider, (prev, next) {
      if (next is HealthProfileStateSaved) {
        // Trigger profile existence refresh. The router's logic handles /home automatically on non-edit flows
        ref.invalidate(profileExistsProvider);
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
                  'conditions': _selectedConditions.toList(),
                },
              );
            }
          });
        }
      } else if (next is HealthProfileStateError) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      next.message,
                      style: AppTextStyles.bodyText.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              margin: const EdgeInsets.all(AppSpacing.md),
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
      canPop: _currentStep == 0 || profileState is HealthProfileStateSaved,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _currentStep != 0) _goToCityStep();
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
    return AppScaffold(
      backgroundColor: AppColors.background,
      appBar: widget.isEditMode
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: BackButton(color: AppColors.textPrimary),
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
                    height: widget.isEditMode ? AppSpacing.xs : AppSpacing.lg,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimensions.paddingHorizontal,
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
                            : _buildConditionsStep(),
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
                AppDimensions.paddingHorizontal,
              ).copyWith(top: AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.background,
                border: Border(
                  top: BorderSide(
                    color: AppColors.border.withValues(alpha: 0.3),
                  ),
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
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            flex: 2,
                            child: AppButton(
                              text: widget.isEditMode
                                  ? 'Update Profile'
                                  : 'Continue',
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
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppDimensions.paddingHorizontal,
        AppSpacing.lg,
        AppDimensions.paddingHorizontal,
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
                style: AppTextStyles.heading1,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          AppReveal(
            delayMs: 50,
            child: Text(
              widget.isEditMode
                  ? 'Update your underlying health conditions.'
                  : "Let's personalize your medical experience.",
              style: AppTextStyles.bodyText.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          AppReveal(
            delayMs: 100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Select Your City', style: AppTextStyles.heading2),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: _cities.map((city) {
                    final isSelected = _selectedCity == city;
                    return ChoiceChip(
                      label: Text(city),
                      labelStyle: AppTextStyles.bodyText.copyWith(
                        color: isSelected
                            ? Colors.white
                            : AppColors.textPrimary,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                      selected: isSelected,
                      onSelected: (_) => setState(() => _selectedCity = city),
                      selectedColor: AppColors.primary,
                      backgroundColor: AppColors.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(100),
                        side: BorderSide(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.border,
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

  Widget _buildConditionsStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppDimensions.paddingHorizontal,
        AppSpacing.lg,
        AppDimensions.paddingHorizontal,
        120,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppReveal(
            child: Semantics(
              header: true,
              child: Text(
                'Underlying Conditions',
                style: AppTextStyles.heading2,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          AppReveal(
            delayMs: 50,
            child: Text(
              'Select any conditions that apply to you.',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppReveal(
            delayMs: 100,
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: _conditionsOptions.map((condition) {
                final isSelected = _selectedConditions.contains(condition);
                return FilterChip(
                  label: Text(condition),
                  labelStyle: AppTextStyles.bodyText.copyWith(
                    color: isSelected
                        ? AppColors.primaryDark
                        : AppColors.textPrimary,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                  selected: isSelected,
                  onSelected: (_) => _onConditionToggle(condition),
                  selectedColor: AppColors.primary.withValues(alpha: 0.15),
                  backgroundColor: AppColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(32),
                    side: BorderSide(
                      color: isSelected ? AppColors.primary : AppColors.border,
                      width: isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  showCheckmark: true,
                  checkmarkColor: AppColors.primaryDark,
                );
              }).toList(),
            ),
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
    return Semantics(
      label: 'Step ${current + 1} of $total',
      child: Row(
        children: [
          Text(
            'Step ${current + 1} of $total',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Row(
              children: List.generate(total, (i) {
                final filled = i <= current;
                return Expanded(
                  child: Container(
                    margin: EdgeInsets.only(
                      right: i == total - 1 ? 0 : AppSpacing.xs,
                    ),
                    height: 4,
                    decoration: BoxDecoration(
                      color: filled ? AppColors.primary : AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
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
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.paddingHorizontal,
      ),
      child: AppSkeleton(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.md),
            const SkeletonBar(width: double.infinity, height: 4, radius: 2),
            const SizedBox(height: AppSpacing.xxl),
            const SkeletonBar(width: 200, height: 28),
            const SizedBox(height: AppSpacing.xs),
            const SkeletonBar(width: 260, height: 16),
            const SizedBox(height: AppSpacing.xxl),
            const SkeletonBar(width: 140, height: 20),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: List.generate(
                5,
                (_) => const SkeletonBox(width: 92, height: 40, radius: 100),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
