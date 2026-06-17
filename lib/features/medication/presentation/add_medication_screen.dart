import 'dart:ui';

import 'package:fyp_foreseeme/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/medication_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/enums/medication_enums.dart';
import 'package:google_fonts/google_fonts.dart';
import 'medication_notifier.dart';

const _kTeal = Color(0xFF006D77);
const _kCyan = Color(0xFF28DDE8);

class AddMedicationScreen extends ConsumerStatefulWidget {
  const AddMedicationScreen({super.key});

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
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: _reminderTimes[index] ?? TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: _kCyan,
              onPrimary: Colors.black,
              surface: Color(0xFF0A1628),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
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
    final hour = time.hour == 0 ? 12 : (time.hour > 12 ? time.hour - 12 : time.hour);
    final minute = time.minute.toString().padLeft(2, '0');
    final suffix = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  Future<void> _saveMedication() async {
    if (ref.read(medicationNotifierProvider).isLoading) return;

    if (!_formKey.currentState!.validate()) return;
    if (_reminderToggle && _reminderTimes.any((t) => t == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please select all required reminder times',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
      return;
    }
    final user = ref.read(authStateProvider).value;
    if (user == null || user.uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'You must be signed in to save medication.',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
      return;
    }

    final medication = MedicationModel(
      id: '',
      uid: user.uid,
      name: _nameController.text.trim(),
      dosage: _dosageController.text.trim(),
      type: _selectedType,
      frequency: _selectedFrequency,
      reminderTimes: _reminderToggle
          ? _reminderTimes.map((t) => _formatTimeForModel(t!)).toList()
          : [],
      isActive: true,
      createdAt: DateTime.now(),
    );

    try {
      await ref
          .read(medicationNotifierProvider.notifier)
          .addMedication(medication);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Medication saved successfully',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(medicationNotifierProvider).isLoading;
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        title: Text(
          'Add Medication',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: -0.2,
          ),
        ),
        iconTheme: const IconThemeData(color: _kCyan),
      ),
      body: Stack(
        children: [
          // Ambient background gradient
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF06111D), Color(0xFF081220), Color(0xFF040A12)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
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
                    
                    const SizedBox(height: 12),
                    
                    // Quick Suggestions (Static UI element to match reference)
                    _buildSuggestionChips(),
                    
                    const SizedBox(height: 24),

                    // Medication Form Card
                    _GlassContainer(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'MEDICATION FORM',
                            style: GoogleFonts.manrope(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                              color: _kTeal,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              _buildTypeCard(MedicationType.pill, Icons.medication_rounded, 'Pill'),
                              const SizedBox(width: 12),
                              _buildTypeCard(MedicationType.syrup, Icons.water_drop_rounded, 'Syrup'),
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
                          Text(
                            'Dosage',
                            style: GoogleFonts.manrope(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildDosageInput(),
                          const SizedBox(height: 24),
                          Text(
                            'Frequency',
                            style: GoogleFonts.manrope(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
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
                          Text(
                            'Schedule Time',
                            style: GoogleFonts.manrope(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
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
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Reminder',
                                    style: GoogleFonts.manrope(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Get notified 15 mins before',
                                    style: GoogleFonts.manrope(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white.withValues(alpha: 0.5),
                                    ),
                                  ),
                                ],
                              ),
                              Switch(
                                value: _reminderToggle,
                                onChanged: (val) => setState(() => _reminderToggle = val),
                                activeThumbColor: Colors.white,
                                activeTrackColor: _kCyan,
                                inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
                                inactiveThumbColor: Colors.white.withValues(alpha: 0.4),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // AI Interaction Check Card (Static to match reference)
                    _GlassContainer(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0D1F38),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _kTeal.withValues(alpha: 0.3),
                                width: 1,
                              ),
                            ),
                            child: const Icon(
                              Icons.health_and_safety_rounded,
                              color: _kCyan,
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
                                  style: GoogleFonts.spaceGrotesk(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'ForeSeeMe AI is analyzing potential interactions with your existing health data.',
                                  style: GoogleFonts.manrope(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                    color: Colors.white.withValues(alpha: 0.6),
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
            child: _GradientSaveButton(
              isLoading: isLoading,
              onPressed: _saveMedication,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNameInput() {
    return TextFormField(
      controller: _nameController,
      style: GoogleFonts.manrope(
        color: const Color(0xFF0A1628),
        fontWeight: FontWeight.w600,
        fontSize: 16,
      ),
      validator: (val) => (val == null || val.trim().isEmpty) ? 'Enter a name' : null,
      decoration: InputDecoration(
        hintText: 'Search medication name...',
        hintStyle: GoogleFonts.manrope(
          color: const Color(0xFF0A1628).withValues(alpha: 0.3),
          fontWeight: FontWeight.w500,
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        errorStyle: GoogleFonts.manrope(color: AppColors.error),
      ),
    );
  }

  Widget _buildSuggestionChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _SuggestionChip(label: 'Paracetamol', onPressed: () => _nameController.text = 'Paracetamol'),
          const SizedBox(width: 10),
          _SuggestionChip(label: 'Amoxicillin', onPressed: () => _nameController.text = 'Amoxicillin'),
          const SizedBox(width: 10),
          _SuggestionChip(label: 'Lisinopril', onPressed: () => _nameController.text = 'Lisinopril'),
        ],
      ),
    );
  }

  Widget _buildTypeCard(MedicationType type, IconData icon, String label) {
    final isSelected = _selectedType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedType = type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isSelected ? _kTeal.withValues(alpha: 0.15) : const Color(0xFF0D1F38),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? _kTeal : Colors.white.withValues(alpha: 0.05),
              width: 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? _kCyan : Colors.white.withValues(alpha: 0.7),
                size: 24,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDosageInput() {
    return TextFormField(
      controller: _dosageController,
      style: GoogleFonts.manrope(
        color: const Color(0xFF0A1628),
        fontWeight: FontWeight.w600,
        fontSize: 16,
      ),
      validator: (val) => (val == null || val.trim().isEmpty) ? 'Enter a dosage' : null,
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildFrequencyDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1F38),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<MedicationFrequency>(
          value: _selectedFrequency,
          isExpanded: true,
          dropdownColor: const Color(0xFF0D1F38),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white),
          style: GoogleFonts.manrope(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
          items: MedicationFrequency.values.map((freq) {
            return DropdownMenuItem(
              value: freq,
              child: Text(freq.label),
            );
          }).toList(),
          onChanged: _onFrequencyChanged,
        ),
      ),
    );
  }

  Widget _buildTimeInput(int index) {
    final time = _reminderTimes[index];
    final displayTime = time != null ? _formatTimeForDisplay(time) : 'Select Time';
    return GestureDetector(
      onTap: () => _pickTime(index),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          displayTime,
          style: GoogleFonts.manrope(
            color: time != null ? const Color(0xFF0A1628) : const Color(0xFF0A1628).withValues(alpha: 0.4),
            fontWeight: FontWeight.w600,
            fontSize: 16,
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: const Color(0xFF0D1F38).withValues(alpha: 0.45),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.05),
              width: 1.0,
            ),
          ),
          child: child,
        ),
      ),
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
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1F38).withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _kTeal.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: _kCyan,
          ),
        ),
      ),
    );
  }
}

// ── Gradient Save Button ──────────────────────────────────────────────────────

class _GradientSaveButton extends StatefulWidget {
  final bool isLoading;
  final VoidCallback onPressed;

  const _GradientSaveButton({
    required this.isLoading,
    required this.onPressed,
  });

  @override
  State<_GradientSaveButton> createState() => _GradientSaveButtonState();
}

class _GradientSaveButtonState extends State<_GradientSaveButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _isPressed ? 0.975 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              colors: [_kTeal, _kCyan],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            boxShadow: [
              BoxShadow(
                color: _kCyan.withValues(alpha: _isPressed ? 0.20 : 0.40),
                blurRadius: _isPressed ? 18 : 32,
                spreadRadius: -6,
                offset: Offset(0, _isPressed ? 4 : 10),
              ),
            ],
          ),
          child: Center(
            child: widget.isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.save_outlined, color: Colors.white, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        'Save Medication',
                        style: GoogleFonts.manrope(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
