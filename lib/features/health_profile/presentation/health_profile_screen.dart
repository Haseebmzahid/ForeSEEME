import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/app_colors.dart';
import 'package:fyp_foreseeme/core/theme/app_theme.dart';
import 'package:fyp_foreseeme/core/widgets/app_button.dart';
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

class _HealthProfileScreenState extends ConsumerState<HealthProfileScreen>
    with SingleTickerProviderStateMixin {
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

  // Edit mode only: whether the existing profile has been applied to the
  // fields above yet (guards against re-populating over the user's
  // in-progress edits on a later rebuild, and against getting stuck showing
  // the loading skeleton forever if the fetch resolves to no profile).
  bool _prefilled = false;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic);
  }

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

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
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

  Future<void> _submit() async {
    if (_selectedCity == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please select your city.',
            style: AppTextStyles.bodyText.copyWith(color: Colors.white),
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(AppSpacing.md),
        ),
      );
      return;
    }

    if (_selectedConditions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please select at least one condition or "None".',
            style: AppTextStyles.bodyText.copyWith(color: Colors.white),
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(AppSpacing.md),
        ),
      );
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
          : FadeTransition(
              opacity: _fadeAnim,
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimensions.paddingHorizontal,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: widget.isEditMode
                                ? AppSpacing.xs
                                : AppSpacing.xxl,
                          ),

                          // Welcome & Context
                          Text(
                            widget.isEditMode
                                ? 'Edit Health Profile'
                                : 'Complete Profile',
                            style: AppTextStyles.heading1,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            widget.isEditMode
                                ? 'Update your underlying health conditions.'
                                : 'Let\'s personalize your medical experience.',
                            style: AppTextStyles.bodyText.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxl),

                          // City Selection Container
                          Text(
                            'Select Your City',
                            style: AppTextStyles.heading2,
                          ),
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
                                onSelected: (_) =>
                                    setState(() => _selectedCity = city),
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

                          const SizedBox(height: AppSpacing.xxl),

                          // Chronic Conditions Selection
                          Text(
                            'Underlying Conditions',
                            style: AppTextStyles.heading2,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'Select any conditions that apply to you.',
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.sm,
                            children: _conditionsOptions.map((condition) {
                              final isSelected = _selectedConditions.contains(
                                condition,
                              );
                              return FilterChip(
                                label: Text(condition),
                                labelStyle: AppTextStyles.bodyText.copyWith(
                                  color: isSelected
                                      ? AppColors.primaryDark
                                      : AppColors.textPrimary,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                                selected: isSelected,
                                onSelected: (_) =>
                                    _onConditionToggle(condition),
                                selectedColor: AppColors.primary.withValues(
                                  alpha: 0.15,
                                ),
                                backgroundColor: AppColors.surface,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(32),
                                  side: BorderSide(
                                    color: isSelected
                                        ? AppColors.primary
                                        : AppColors.border,
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

                          const SizedBox(height: 120), // Bottom padding
                        ],
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
                child: AppButton(
                  text: widget.isEditMode ? 'Update Profile' : 'Continue',
                  isLoading: isLoading,
                  onPressed: isLoading ? null : _submit,
                ),
              ),
            ),
    );
  }
}

/// Edit-mode-only loading placeholder shown while the user's existing
/// profile is fetched to prefill the form (S6C-01). Mirrors the real form's
/// shape — heading, a row of city-chip-sized blocks, a row of
/// condition-chip-sized blocks — so the skeleton-to-content swap is a single
/// beat, not a layout jump.
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
            const SizedBox(height: AppSpacing.xs),
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
            const SizedBox(height: AppSpacing.xxl),
            const SkeletonBar(width: 170, height: 20),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: List.generate(
                5,
                (_) => const SkeletonBox(width: 108, height: 44, radius: 32),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
