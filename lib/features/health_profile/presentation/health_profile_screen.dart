import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/app_colors.dart';
import 'package:fyp_foreseeme/core/theme/app_theme.dart';
import 'package:fyp_foreseeme/core/widgets/app_button.dart';
import 'package:fyp_foreseeme/core/widgets/app_scaffold.dart';

import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
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

    // Load existing preferences if edit mode
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadExistingProfile();
    });
  }

  Future<void> _loadExistingProfile() async {
    // If edit mode or if the profile somehow exists, we can fetch it, but it's optional for MVP.
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
      body: FadeTransition(
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
                          onSelected: (_) => _onConditionToggle(condition),
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
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(
          AppDimensions.paddingHorizontal,
        ).copyWith(top: AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.background,
          border: Border(
            top: BorderSide(color: AppColors.border.withValues(alpha: 0.3)),
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
