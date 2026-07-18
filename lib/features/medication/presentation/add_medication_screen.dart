import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/medication_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/enums/medication_enums.dart';
import 'package:fyp_foreseeme/features/medication/presentation/widgets/med_primitives.dart';
import 'medication_notifier.dart';

class AddMedicationScreen extends ConsumerStatefulWidget {
  /// When set, the screen opens in edit mode pre-populated with this
  /// medication's values instead of creating a new one.
  final MedicationModel? medication;

  const AddMedicationScreen({super.key, this.medication});

  @override
  ConsumerState<AddMedicationScreen> createState() =>
      _AddMedicationScreenState();
}

class _AddMedicationScreenState extends ConsumerState<AddMedicationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _dosageController = TextEditingController();

  MedicationType _selectedType = MedicationType.pill;
  MedicationFrequency _selectedFrequency = MedicationFrequency.onceDaily;
  bool _reminderToggle = true;

  List<TimeOfDay?> _reminderTimes = [null];

  bool get _isEditMode => widget.medication != null;

  @override
  void initState() {
    super.initState();
    final medication = widget.medication;
    if (medication == null) return;

    _nameController.text = medication.name;
    _dosageController.text = medication.dosage;
    _selectedType = medication.type;
    _selectedFrequency = medication.frequency;
    _reminderToggle = medication.reminderTimes.isNotEmpty;
    _reminderTimes = _initialReminderTimes(medication);
  }

  /// Reminder times parsed from the medication, padded/truncated to match
  /// its frequency's expected count (mirrors [_onFrequencyChanged]).
  List<TimeOfDay?> _initialReminderTimes(MedicationModel medication) {
    final expectedCount = medication.frequency.expectedReminderCount;
    final parsed = medication.reminderTimes
        .map(_parseTimeOfDay)
        .toList(growable: true);

    if (parsed.length > expectedCount) {
      return parsed.sublist(0, expectedCount);
    }
    while (parsed.length < expectedCount) {
      parsed.add(null);
    }
    return parsed;
  }

  TimeOfDay? _parseTimeOfDay(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dosageController.dispose();
    super.dispose();
  }

  void _onFrequencyChanged(MedicationFrequency? newFrequency) {
    if (newFrequency == null) return;
    setState(() {
      _selectedFrequency = newFrequency;
      final expectedCount = newFrequency.expectedReminderCount;

      if (_reminderTimes.length > expectedCount) {
        _reminderTimes = _reminderTimes.sublist(0, expectedCount);
      } else {
        while (_reminderTimes.length < expectedCount) {
          _reminderTimes.add(null);
        }
      }
    });
  }

  Future<void> _pickTime(int index) async {
    // No Theme override: the picker inherits the app's ForeSeeMeTheme, so it is
    // correct in light and dark (it previously forced a dark ColorScheme).
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: _reminderTimes[index] ?? TimeOfDay.now(),
    );
    if (pickedTime != null) {
      setState(() {
        _reminderTimes[index] = pickedTime;
      });
    }
  }

  String _formatTimeForModel(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatTimeForDisplay(TimeOfDay time) {
    final hour = time.hour == 0
        ? 12
        : (time.hour > 12 ? time.hour - 12 : time.hour);
    final minute = time.minute.toString().padLeft(2, '0');
    final suffix = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  Future<void> _saveMedication() async {
    if (ref.read(medicationNotifierProvider).isLoading) return;

    if (!_formKey.currentState!.validate()) return;
    if (_reminderToggle && _reminderTimes.any((t) => t == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select all required reminder times')),
      );
      return;
    }
    final user = ref.read(authStateProvider).value;
    if (user == null || user.uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must be signed in to save medication.'),
        ),
      );
      return;
    }

    final existing = widget.medication;
    final medication = MedicationModel(
      id: existing?.id ?? '',
      uid: existing?.uid ?? user.uid,
      name: _nameController.text.trim(),
      dosage: _dosageController.text.trim(),
      type: _selectedType,
      frequency: _selectedFrequency,
      reminderTimes: _reminderToggle
          ? _reminderTimes.map((t) => _formatTimeForModel(t!)).toList()
          : [],
      isActive: existing?.isActive ?? true,
      createdAt: existing?.createdAt ?? DateTime.now(),
    );

    try {
      if (_isEditMode) {
        await ref
            .read(medicationNotifierProvider.notifier)
            .updateMedication(medication);
      } else {
        await ref
            .read(medicationNotifierProvider.notifier)
            .addMedication(medication);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEditMode
                ? 'Medication updated successfully'
                : 'Medication saved successfully',
          ),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_isEditMode ? 'Update' : 'Save'} failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final isLoading = ref.watch(medicationNotifierProvider).isLoading;

    return Scaffold(
      backgroundColor: palette.background,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        title: Text(
          _isEditMode ? 'Edit Medication' : 'Add Medication',
          style: context.fsmText.titleLarge?.copyWith(
            fontSize: 22,
            letterSpacing: -0.2,
          ),
        ),
        iconTheme: IconThemeData(color: palette.primary),
      ),
      body: Stack(
        children: [
          // Ambient design-system background gradient
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: context.fsmColors.gradients.surface,
              ),
            ),
          ),
          SafeArea(
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Main Search / Name Input
                    _buildNameInput(),

                    if (!_isEditMode) ...[
                      const SizedBox(height: 12),
                      // Quick Suggestions
                      _buildSuggestionChips(),
                    ],

                    const SizedBox(height: 24),

                    // Medication Form Card
                    _GlassContainer(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionLabel('MEDICATION FORM'),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              _buildTypeCard(
                                MedicationType.pill,
                                Icons.medication_rounded,
                                'Pill',
                              ),
                              const SizedBox(width: 12),
                              _buildTypeCard(
                                MedicationType.syrup,
                                Icons.water_drop_rounded,
                                'Syrup',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Dosage & Frequency Card
                    _GlassContainer(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _fieldLabel('Dosage'),
                          const SizedBox(height: 8),
                          _buildDosageInput(),
                          const SizedBox(height: 24),
                          _fieldLabel('Frequency'),
                          const SizedBox(height: 8),
                          _buildFrequencyDropdown(),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Schedule Time & Reminder Card
                    _GlassContainer(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _fieldLabel('Schedule Time'),
                          const SizedBox(height: 8),
                          ...List.generate(_reminderTimes.length, (index) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: _buildTimeInput(index),
                            );
                          }),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Reminder',
                                      style: context.fsmText.titleMedium
                                          ?.copyWith(fontSize: 15),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Get notified 15 mins before',
                                      style: context.fsmText.bodySmall?.copyWith(
                                        color: palette.textTertiary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Inherits the design system's primary via the
                              // active ColorScheme — no hand-set switch colours.
                              Switch(
                                value: _reminderToggle,
                                onChanged: (val) =>
                                    setState(() => _reminderToggle = val),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // AI Interaction Check Card
                    _GlassContainer(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: palette.secondary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(
                                ForeSeeMeRadius.md,
                              ),
                              border: Border.all(
                                color: palette.secondary.withValues(alpha: 0.3),
                                width: ForeSeeMeBorderWidth.thin,
                              ),
                            ),
                            child: Icon(
                              Icons.health_and_safety_rounded,
                              color: palette.secondary,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'AI Interaction Check',
                                  style: context.fsmText.titleLarge,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'ForeSeeMe AI is analyzing potential interactions with your existing health data.',
                                  style: context.fsmText.bodyMedium?.copyWith(
                                    fontSize: 13,
                                    color: palette.textSecondary,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Floating Bottom Button
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: MedGradientButton(
              icon: _isEditMode
                  ? Icons.check_circle_outline_rounded
                  : Icons.save_outlined,
              label: _isEditMode ? 'Save Changes' : 'Save Medication',
              isLoading: isLoading,
              onPressed: _saveMedication,
            ),
          ),
        ],
      ),
    );
  }

  /// Uppercase tracked section label.
  Widget _sectionLabel(String text) => Text(
    text,
    style: context.fsmText.labelSmall?.copyWith(
      fontSize: 12,
      letterSpacing: 1.2,
      fontWeight: FontWeight.w700,
      color: context.fsmPalette.secondary,
    ),
  );

  /// Sentence-case field label above an input.
  Widget _fieldLabel(String text) => Text(
    text,
    style: context.fsmText.bodyMedium?.copyWith(
      fontSize: 13,
      color: context.fsmPalette.textSecondary,
    ),
  );

  /// Shared premium form-field decoration, resolved from the design system.
  InputDecoration _fieldDecoration({String? hintText}) {
    final palette = context.fsmPalette;
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(ForeSeeMeRadius.sm),
      borderSide: BorderSide(color: color, width: width),
    );
    return InputDecoration(
      hintText: hintText,
      hintStyle: context.fsmText.bodyLarge?.copyWith(
        color: palette.textTertiary,
        fontWeight: FontWeight.w500,
      ),
      filled: true,
      fillColor: palette.surfaceContainerLowest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: border(palette.outline, ForeSeeMeBorderWidth.hairline),
      enabledBorder: border(palette.outline, ForeSeeMeBorderWidth.hairline),
      focusedBorder: border(palette.primary, ForeSeeMeBorderWidth.thick),
      errorBorder: border(palette.error, ForeSeeMeBorderWidth.thin),
      focusedErrorBorder: border(palette.error, ForeSeeMeBorderWidth.thick),
      errorStyle: context.fsmText.labelMedium?.copyWith(color: palette.error),
    );
  }

  Widget _buildNameInput() {
    return TextFormField(
      controller: _nameController,
      style: context.fsmText.bodyLarge?.copyWith(
        color: context.fsmPalette.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      cursorColor: context.fsmPalette.primary,
      validator: (val) =>
          (val == null || val.trim().isEmpty) ? 'Enter a name' : null,
      decoration: _fieldDecoration(hintText: 'Search medication name...'),
    );
  }

  Widget _buildSuggestionChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _SuggestionChip(
            label: 'Paracetamol',
            onPressed: () => _nameController.text = 'Paracetamol',
          ),
          const SizedBox(width: 10),
          _SuggestionChip(
            label: 'Amoxicillin',
            onPressed: () => _nameController.text = 'Amoxicillin',
          ),
          const SizedBox(width: 10),
          _SuggestionChip(
            label: 'Lisinopril',
            onPressed: () => _nameController.text = 'Lisinopril',
          ),
        ],
      ),
    );
  }

  Widget _buildTypeCard(MedicationType type, IconData icon, String label) {
    final palette = context.fsmPalette;
    final isSelected = _selectedType == type;
    return Expanded(
      child: Semantics(
        button: true,
        selected: isSelected,
        label: label,
        child: GestureDetector(
          onTap: () => setState(() => _selectedType = type),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: isSelected
                  ? palette.primary.withValues(alpha: 0.14)
                  : palette.surfaceContainerLow,
              borderRadius: BorderRadius.circular(ForeSeeMeRadius.md),
              border: Border.all(
                color: isSelected ? palette.primary : palette.outlineVariant,
                width: ForeSeeMeBorderWidth.thin,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  icon,
                  color: isSelected ? palette.primary : palette.textSecondary,
                  size: 24,
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: context.fsmText.bodySmall?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? palette.textPrimary
                        : palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDosageInput() {
    return TextFormField(
      controller: _dosageController,
      style: context.fsmText.bodyLarge?.copyWith(
        color: context.fsmPalette.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      cursorColor: context.fsmPalette.primary,
      validator: (val) =>
          (val == null || val.trim().isEmpty) ? 'Enter a dosage' : null,
      decoration: _fieldDecoration(),
    );
  }

  Widget _buildFrequencyDropdown() {
    final palette = context.fsmPalette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: palette.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(ForeSeeMeRadius.sm),
        border: Border.all(
          color: palette.outline,
          width: ForeSeeMeBorderWidth.hairline,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<MedicationFrequency>(
          value: _selectedFrequency,
          isExpanded: true,
          dropdownColor: palette.surface,
          borderRadius: BorderRadius.circular(ForeSeeMeRadius.sm),
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: palette.textSecondary,
          ),
          style: context.fsmText.bodyLarge?.copyWith(
            fontSize: 15,
            color: palette.textPrimary,
          ),
          items: MedicationFrequency.values.map((freq) {
            return DropdownMenuItem(value: freq, child: Text(freq.label));
          }).toList(),
          onChanged: _onFrequencyChanged,
        ),
      ),
    );
  }

  Widget _buildTimeInput(int index) {
    final palette = context.fsmPalette;
    final time = _reminderTimes[index];
    final displayTime = time != null
        ? _formatTimeForDisplay(time)
        : 'Select Time';
    return Semantics(
      button: true,
      label: 'Reminder time: $displayTime',
      child: GestureDetector(
        onTap: () => _pickTime(index),
        child: Container(
          width: double.infinity,
          // Matches the form fields' 56dp minimum tap height.
          constraints: const BoxConstraints(minHeight: 56),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: palette.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(ForeSeeMeRadius.sm),
            border: Border.all(
              color: palette.outline,
              width: ForeSeeMeBorderWidth.hairline,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.schedule_rounded,
                size: 18,
                color: palette.textSecondary,
              ),
              const SizedBox(width: 10),
              Text(
                displayTime,
                style: context.fsmText.bodyLarge?.copyWith(
                  color: time != null
                      ? palette.textPrimary
                      : palette.textTertiary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared Glass Container ────────────────────────────────────────────────────

class _GlassContainer extends StatelessWidget {
  final Widget child;

  const _GlassContainer({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: ForeSeeMeSurface.card(context),
      child: child,
    );
  }
}

// ── Suggestion Chip ─────────────────────────────────────────────────────────

class _SuggestionChip extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _SuggestionChip({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: palette.secondary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(ForeSeeMeRadius.full),
            border: Border.all(
              color: palette.secondary.withValues(alpha: 0.3),
              width: ForeSeeMeBorderWidth.thin,
            ),
          ),
          child: Text(
            label,
            style: context.fsmText.bodySmall?.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: palette.secondary,
            ),
          ),
        ),
      ),
    );
  }
}
