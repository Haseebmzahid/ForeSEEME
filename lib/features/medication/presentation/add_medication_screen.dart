import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/medication/domain/enums/medication_enums.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/medication_model.dart';
import 'package:fyp_foreseeme/features/medication/presentation/medication_hub_providers.dart';
import 'package:fyp_foreseeme/features/medication/presentation/widgets/add_medication_chrome.dart';
import 'package:fyp_foreseeme/features/medication/presentation/widgets/add_medication_sheets.dart';
import 'package:fyp_foreseeme/features/medication/presentation/widgets/add_medication_style.dart';
import 'medication_notifier.dart';

/// The **Add / Edit Medication screen**, implemented natively from the approved
/// prototype (`docs/Design/ForeSeeMe Add Medication (1).html`).
///
/// Behaviour is unchanged from the screen this replaces: the same
/// [MedicationNotifier] saves the same [MedicationModel] to the same Firestore
/// path and drives the same reminder-scheduling pipeline, and the screen
/// touches no repository and no Firebase SDK (Golden Rule 1). Only the
/// composition is new.
///
/// **Deliberate departures from the prototype**, recorded here so each is a
/// decision rather than a drift:
///
///  * The prototype's mock status bar (`9:41`, `LTE`, a battery) is dropped, as
///    it is on the Medications screen: it stands in for the real OS status bar,
///    and drawing a fake `9:41` in a shipping app would be fabricated
///    information.
///  * The prototype draws its **own on-screen keyboard**, because a web
///    prototype has none. Flutter has the real one; reproducing a fake keyboard
///    would break actual text entry. The footer still lifts above the keyboard
///    the way the prototype's does.
///  * The prototype's header carries a **theme toggle**. The app's theme is
///    chosen once in Profile; a second, screen-local switch would be a new
///    feature, not this prototype's layout.
///  * Section **5 · INSTRUCTIONS** is omitted. [MedicationModel] has no
///    instructions field, and adding one is a domain change this task
///    explicitly excludes — rendering a note field that silently discarded what
///    the user typed would be worse than not offering it.
///  * The prototype's *reminders failed to schedule* failure sheet is not
///    reachable: [MedicationNotifier.addMedication] treats scheduling as
///    best-effort and never reports it as a failure, so the app cannot honestly
///    tell the two apart. Only the save-failed variant is shown.
///  * The medication-name **suggestion chips** the previous screen offered are
///    kept, in the prototype's own chip material, directly under the name
///    field — existing behaviour the prototype's single name input has no slot
///    for.
///  * The prototype's `data-proto` state-switcher panel is prototype
///    furniture and is dropped.
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
  // ── The prototype's own constants ──────────────────────────────────────────

  /// `DEFAULT_TIMES` — the reminder times proposed for each frequency, as
  /// minutes past midnight.
  static const Map<int, List<int>> _defaultTimes = {
    1: [480],
    2: [480, 1200],
    3: [480, 840, 1200],
  };

  static const List<String> _suggestions = [
    'Paracetamol',
    'Amoxicillin',
    'Lisinopril',
  ];

  // ── Form state ─────────────────────────────────────────────────────────────

  final _nameController = TextEditingController();
  final _doseController = TextEditingController();
  final _scroll = ScrollController();

  final _nameKey = GlobalKey();
  final _doseKey = GlobalKey();
  final _freqKey = GlobalKey();
  final _timesKey = GlobalKey();

  MedicationType _type = MedicationType.pill;

  /// `mg` / `ml` / `pill`, the prototype's own unit tokens.
  String _unit = 'mg';

  /// Doses per day; `0` until the user picks one, which is what makes
  /// `HOW OFTEN` a required detail rather than a silently-defaulted one.
  int _freq = 0;

  /// Reminder times as minutes past midnight, in row order.
  List<int> _times = [];

  /// Field key → message, populated only once the user has tried to save.
  final Map<String, String> _errors = {};

  bool _saving = false;
  double _progress = 0;
  int _shake = 0;
  Timer? _progressTimer;

  bool get _isEditMode => widget.medication != null;

  @override
  void initState() {
    super.initState();
    final medication = widget.medication;
    if (medication == null) return;

    _nameController.text = medication.name;
    _type = medication.type;
    _freq = medication.frequency.expectedReminderCount;
    _times = _parseTimes(medication);

    final dose = _parseDosage(medication.dosage);
    _doseController.text = dose.$1;
    _unit = dose.$2;
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _nameController.dispose();
    _doseController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ── Model ↔ form ───────────────────────────────────────────────────────────

  /// The stored `HH:mm` reminder times as minutes past midnight, padded or
  /// truncated to the medication's frequency (as the previous screen did).
  List<int> _parseTimes(MedicationModel medication) {
    final expected = medication.frequency.expectedReminderCount;
    final parsed = <int>[];
    for (final value in medication.reminderTimes) {
      final parts = value.split(':');
      if (parts.length != 2) continue;
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      if (hour == null || minute == null) continue;
      parsed.add(hour * 60 + minute);
    }
    if (parsed.length > expected) return parsed.sublist(0, expected);
    final fallback = _defaultTimes[expected] ?? const [480];
    while (parsed.length < expected) {
      parsed.add(fallback[parsed.length]);
    }
    return parsed;
  }

  /// Splits a stored `dosage` string into the prototype's amount + unit pair.
  ///
  /// The field is free text in Firestore and always has been, so anything that
  /// does not parse keeps its digits in the amount and falls back to the unit
  /// the medication's type implies. Nothing about the stored shape changes:
  /// the two are recombined into the same single string on save.
  (String, String) _parseDosage(String dosage) {
    final fallbackUnit = _type == MedicationType.syrup ? 'ml' : 'mg';
    final match = RegExp(
      r'^\s*([0-9]*\.?[0-9]+)\s*([a-zA-Z]*)\s*$',
    ).firstMatch(dosage);
    if (match == null) return ('', fallbackUnit);

    final amount = match.group(1) ?? '';
    final unit = (match.group(2) ?? '').toLowerCase();
    return (
      amount,
      switch (unit) {
        'mg' => 'mg',
        'ml' => 'ml',
        'pill' || 'pills' || 'tablet' || 'tablets' => 'pill',
        _ => fallbackUnit,
      },
    );
  }

  /// The unit as it reads in the stored `dosage` string and in the preview.
  String _unitLabel(String amount) {
    if (_unit != 'pill') return _unit;
    return double.tryParse(amount) == 1 ? 'pill' : 'pills';
  }

  MedicationFrequency get _frequency => switch (_freq) {
    3 => MedicationFrequency.thriceDaily,
    2 => MedicationFrequency.twiceDaily,
    _ => MedicationFrequency.onceDaily,
  };

  String _formatForModel(int minutes) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  // ── Validation (the prototype's `valid()`, verbatim) ───────────────────────

  static const _requiredKeys = ['name', 'dose', 'freq', 'times'];

  List<String> get _missing {
    final out = <String>[];
    final dose = _doseController.text.trim();
    if (_nameController.text.trim().isEmpty) out.add('name');
    if (dose.isEmpty ||
        !RegExp(r'^\d+(\.\d+)?$').hasMatch(dose) ||
        (double.tryParse(dose) ?? 0) <= 0) {
      out.add('dose');
    }
    if (_freq == 0) out.add('freq');
    if (_times.isEmpty || _times.length != _freq || _duplicates.isNotEmpty) {
      out.add('times');
    }
    return out;
  }

  bool get _ready => _missing.isEmpty;

  /// Row indexes whose time is shared with another row.
  Set<int> get _duplicates {
    final out = <int>{};
    for (var i = 0; i < _times.length; i++) {
      for (var j = 0; j < _times.length; j++) {
        if (i != j && _times[i] == _times[j]) out.add(i);
      }
    }
    return out;
  }

  // ── Interactions ───────────────────────────────────────────────────────────

  void _clearError(String key) {
    if (_errors.remove(key) != null) setState(() {});
  }

  void _setType(MedicationType type) {
    setState(() {
      _type = type;
      // The prototype swaps the unit when it no longer suits the form.
      if (type == MedicationType.syrup && _unit == 'mg') _unit = 'ml';
      if (type == MedicationType.pill && _unit == 'ml') _unit = 'mg';
    });
  }

  /// The prototype's `setFreq(n, keep)`: a fresh choice proposes the default
  /// times, while `Add a … reminder` keeps the times already set.
  void _setFrequency(int n, {bool keep = false}) {
    if (n < 1 || n > 3) return;
    setState(() {
      final previous = List<int>.from(_times);
      _freq = n;
      final base = _defaultTimes[n]!;
      _times = [
        for (var i = 0; i < base.length; i++)
          keep && i < previous.length ? previous[i] : base[i],
      ];
      _errors.remove('freq');
      _errors.remove('times');
    });
  }

  void _removeTime(int index) {
    if (_freq <= 1) return;
    setState(() {
      _times.removeAt(index);
      _freq = _times.length;
      _errors.remove('times');
    });
  }

  Future<void> _pickTime(int index) async {
    FocusScope.of(context).unfocus();
    final theme = AddMedTheme.of(context);
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: theme.scrim,
      builder: (_) => AddMedTimePickerSheet(
        index: index,
        initialMinutes: _times[index],
        otherMinutes: [
          for (var i = 0; i < _times.length; i++)
            if (i != index) _times[i],
        ],
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _times[index] = picked;
      _errors.remove('times');
    });
  }

  /// The prototype's `showAllErrors()`: every missing detail is named at once,
  /// the CTA shakes, and the view scrolls to the first offender.
  void _showAllErrors() {
    final missing = _missing;
    final dose = _doseController.text.trim();
    final messages = <String, String>{
      'name': 'Add the medication name so you recognise the reminder.',
      'dose': dose.isEmpty
          ? 'Enter how much you take at one time, e.g. 500.'
          : 'Use numbers only, like 500 — then pick mg, ml or pills.',
      'freq': 'Choose how many times a day you take this.',
      'times': _duplicates.isNotEmpty
          ? 'Two reminders share the same time. Move one so you are not '
                'alerted twice.'
          : 'Set a time for every reminder.',
    };

    setState(() {
      _errors.clear();
      for (final key in _requiredKeys) {
        if (missing.contains(key)) _errors[key] = messages[key]!;
      }
      _shake++;
    });

    final target = switch (missing.first) {
      'name' => _nameKey,
      'dose' => _doseKey,
      'freq' => _freqKey,
      _ => _timesKey,
    }.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(
        target,
        duration: AppMotion.reduceMotion(context)
            ? Duration.zero
            : const Duration(milliseconds: 320),
        curve: AppMotion.curve,
        alignment: 0.15,
      );
    }
  }

  void _submit() {
    if (_saving) return;
    if (!_ready) {
      _showAllErrors();
      return;
    }
    FocusScope.of(context).unfocus();
    _save();
  }

  Future<void> _save() async {
    final user = ref.read(authStateProvider).value;
    if (user == null || user.uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must be signed in to save medication.'),
        ),
      );
      return;
    }

    setState(() {
      _saving = true;
      _progress = 0.46;
    });
    // The prototype's second progress step. Cancelled the moment the save
    // settles, so no timer outlives the screen.
    _progressTimer?.cancel();
    _progressTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted && _saving) setState(() => _progress = 0.92);
    });

    final amount = _doseController.text.trim();
    final existing = widget.medication;
    final medication = MedicationModel(
      id: existing?.id ?? '',
      uid: existing?.uid ?? user.uid,
      name: _nameController.text.trim(),
      dosage: '$amount ${_unitLabel(amount)}',
      type: _type,
      frequency: _frequency,
      reminderTimes: _times.map(_formatForModel).toList(),
      isActive: existing?.isActive ?? true,
      createdAt: existing?.createdAt ?? DateTime.now(),
    );

    try {
      final notifier = ref.read(medicationNotifierProvider.notifier);
      if (_isEditMode) {
        await notifier.updateMedication(medication);
      } else {
        await notifier.addMedication(medication);
      }
      if (!mounted) return;
      _endSaving();
      await _showSuccess(medication);
    } catch (e) {
      if (!mounted) return;
      _endSaving();
      await _showFailure(e);
    }
  }

  void _endSaving() {
    _progressTimer?.cancel();
    setState(() {
      _saving = false;
      _progress = 0;
    });
  }

  Future<void> _showSuccess(MedicationModel medication) async {
    final theme = AddMedTheme.of(context);
    final times = _times.map(addMedFormatTime).toList();
    final freqText = switch (_freq) {
      3 => 'thrice daily',
      2 => 'twice daily',
      _ => 'once daily',
    };

    final another = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      barrierColor: theme.scrim,
      builder: (_) => AddMedSuccessSheet(
        title: '${medication.name} ${_isEditMode ? 'updated' : 'added'}',
        subtitle: '${medication.dosage} · $freqText · '
            '${_freq == 1 ? '1 reminder active' : '$_freq reminders active'}',
        reminderLine: 'Reminders set for ${_joinTimes(times)}',
        offerAnother: !_isEditMode,
      ),
    );
    if (!mounted) return;

    if (another == true) {
      _reset();
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _showFailure(Object error) async {
    final theme = AddMedTheme.of(context);
    final name = _nameController.text.trim().isEmpty
        ? 'this medication'
        : _nameController.text.trim();

    final retry = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: theme.scrim,
      builder: (_) => AddMedFailSheet(
        title: _isEditMode
            ? 'Couldn’t update $name'
            : 'Couldn’t save $name',
        tag: 'SAVE FAILED',
        body: 'Nothing was saved and no reminders were scheduled. Your entries '
            'are still here — try again in a moment.\n\n$error',
      ),
    );
    if (retry == true && mounted) await _save();
  }

  /// `08:00 AM, 02:00 PM and 08:00 PM`.
  String _joinTimes(List<String> times) {
    if (times.length <= 1) return times.isEmpty ? 'no times yet' : times.first;
    return '${times.sublist(0, times.length - 1).join(', ')} and ${times.last}';
  }

  /// The prototype's `reset()` behind `Add another`.
  void _reset() {
    setState(() {
      _nameController.clear();
      _doseController.clear();
      _type = MedicationType.pill;
      _unit = 'mg';
      _freq = 0;
      _times = [];
      _errors.clear();
    });
    _scroll.jumpTo(0);
  }

  Future<void> _confirmArchive() async {
    final medication = widget.medication;
    if (medication == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Archive Medication?'),
        content: const Text(
          'This medication will no longer appear in your active medications.\n\n'
          'Your adherence history will remain available.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref
          .read(medicationNotifierProvider.notifier)
          .archiveMedication(medication.uid, medication.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Archive failed: $e')),
      );
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = AddMedTheme.of(context);
    // The same wall-clock seam the Medications screen reads, so the NOW marker
    // and today's schedule can never disagree — and so tests can pin it.
    final now = ref.watch(hubNowProvider);
    // Watched, not read at save time: it keeps the auth stream subscribed for
    // this screen's lifetime, so `_save` reads a resolved user instead of
    // racing the stream's first event and refusing a save the signed-in user
    // is entitled to make.
    ref.watch(authStateProvider);

    return Scaffold(
      backgroundColor: theme.bg,
      // The shell Scaffold already lifts this screen above the keyboard;
      // resizing again here would subtract the inset twice.
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          AddMedBackdrop(scroll: _scroll),
          SafeArea(
            bottom: false,
            // The form and the footer are siblings in a column, not layers in a
            // stack: the footer owns its space, so no field can ever scroll
            // underneath the CTA.
            child: Column(
              children: [
                AddMedHeader(
                  title: _isEditMode ? 'Edit medication' : 'Add medication',
                  subtitle: _isEditMode
                      ? 'Changes reschedule the reminders'
                      : 'Set it up once — reminders follow',
                  onBack: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: _form(context, now.hour * 60 + now.minute),
                ),
                _footer(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _form(BuildContext context, int nowMinutes) {
    final theme = AddMedTheme.of(context);
    final amount = _doseController.text.trim();
    final duplicates = _duplicates;

    // The prototype reveals its first nine scroll children on entry
    // (`delay: 60 + i * 55`).
    var revealIndex = 0;
    Widget reveal(Widget child) {
      final index = revealIndex++;
      return index < 9
          ? AppReveal(delayMs: 60 + index * 55, offsetY: 22, child: child)
          : child;
    }

    return ListView(
      controller: _scroll,
      // The prototype's `padding: 108px 18px 172px`. Its 108px top covered the
      // status bar and the header, which are real widgets above this list; its
      // 172px bottom covered a footer that overlaid the scroller, and the
      // footer now sits in its own region below it.
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
      children: [
        reveal(
          AddMedSchedulePreview(
            name: _nameController.text.trim().isEmpty
                ? null
                : _nameController.text.trim(),
            meta: _previewMeta(amount),
            isPill: _type == MedicationType.pill,
            ready: _ready,
            minutes: _times,
            nowMinutes: nowMinutes,
            scroll: _scroll,
          ),
        ),

        // ── 1 · MEDICATION ────────────────────────────────────────────────
        const SizedBox(height: 22),
        reveal(const AddMedSectionLabel(label: '1 · MEDICATION')),
        const SizedBox(height: 10),
        reveal(
          Column(
            key: _nameKey,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AddMedFieldShell(
                hasError: _errors.containsKey('name'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AddMedFieldLabel('NAME', required: true),
                    AddMedInput(
                      controller: _nameController,
                      hintText: 'e.g. Metformin',
                      fontSize: 17,
                      textCapitalization: TextCapitalization.words,
                      onChanged: (_) {
                        _clearError('name');
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ),
              if (_errors.containsKey('name'))
                AddMedNotice(text: _errors['name']!)
              else
                const AddMedHelp(
                  'Exactly as printed on the label or prescription',
                ),
              // Existing behaviour, in the prototype's chip material: the
              // three quick names the previous screen offered.
              const SizedBox(height: 10),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final suggestion in _suggestions)
                    AddMedTagChip(
                      label: suggestion,
                      selected:
                          _nameController.text.trim().toLowerCase() ==
                          suggestion.toLowerCase(),
                      onTap: () {
                        _nameController.text = suggestion;
                        _clearError('name');
                        setState(() {});
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        reveal(
          Row(
            children: [
              Expanded(
                child: AddMedTypeCard(
                  label: 'Pill',
                  isPill: true,
                  selected: _type == MedicationType.pill,
                  onTap: () => _setType(MedicationType.pill),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AddMedTypeCard(
                  label: 'Syrup',
                  isPill: false,
                  selected: _type == MedicationType.syrup,
                  onTap: () => _setType(MedicationType.syrup),
                ),
              ),
            ],
          ),
        ),

        // ── 2 · DOSAGE ────────────────────────────────────────────────────
        const SizedBox(height: 24),
        reveal(const AddMedSectionLabel(label: '2 · DOSAGE')),
        const SizedBox(height: 10),
        reveal(
          Column(
            key: _doseKey,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AddMedFieldShell(
                hasError: _errors.containsKey('dose'),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const AddMedFieldLabel('AMOUNT', required: true),
                          AddMedInput(
                            controller: _doseController,
                            hintText: '500',
                            fontSize: 17,
                            mono: true,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            textInputAction: TextInputAction.done,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.]'),
                              ),
                            ],
                            onChanged: (_) {
                              _clearError('dose');
                              setState(() {});
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    for (final unit in const [
                      ('mg', 'mg'),
                      ('ml', 'ml'),
                      ('pill', 'pills'),
                    ]) ...[
                      if (unit.$1 != 'mg') const SizedBox(width: 5),
                      AddMedUnitButton(
                        label: unit.$2,
                        selected: _unit == unit.$1,
                        onTap: () => setState(() => _unit = unit.$1),
                      ),
                    ],
                  ],
                ),
              ),
              if (_errors.containsKey('dose'))
                AddMedNotice(text: _errors['dose']!)
              else
                const AddMedHelp('Numbers only — the unit is set beside it'),
            ],
          ),
        ),

        // ── 3 · HOW OFTEN ─────────────────────────────────────────────────
        const SizedBox(height: 24),
        reveal(const AddMedSectionLabel(label: '3 · HOW OFTEN')),
        const SizedBox(height: 10),
        reveal(
          Column(
            key: _freqKey,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final option in const [
                      ('Once', 1),
                      ('Twice', 2),
                      ('Thrice', 3),
                    ]) ...[
                      if (option.$2 != 1) const SizedBox(width: 9),
                      Expanded(
                        child: AddMedFrequencyCard(
                          title: option.$1,
                          count: option.$2,
                          selected: _freq == option.$2,
                          onTap: () => _setFrequency(option.$2),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (_errors.containsKey('freq'))
                AddMedNotice(
                  text: _errors['freq']!,
                  padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
                ),
            ],
          ),
        ),

        // ── 4 · REMINDER TIMES ────────────────────────────────────────────
        const SizedBox(height: 24),
        reveal(
          AddMedSectionLabel(
            label: '4 · REMINDER TIMES',
            trailing: _freq == 0
                ? '—'
                : (_freq == 1 ? '1 TIME' : '$_freq TIMES'),
          ),
        ),
        const SizedBox(height: 10),
        Column(
          key: _timesKey,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_freq == 0)
              const AddMedReminderEmpty()
            else ...[
              for (var i = 0; i < _times.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                AddMedReminderRow(
                  index: i,
                  minutes: _times[i],
                  duplicate: duplicates.contains(i),
                  onChange: () => _pickTime(i),
                  onRemove: _freq > 1 ? () => _removeTime(i) : null,
                ),
              ],
              if (_freq < 3) ...[
                const SizedBox(height: 10),
                AddMedAddTimeButton(
                  label: _freq == 1
                      ? 'Add a second reminder'
                      : 'Add a third reminder',
                  onTap: () => _setFrequency(_freq + 1, keep: true),
                ),
              ],
            ],
            if (_errors.containsKey('times'))
              AddMedNotice(
                text: _errors['times']!,
                padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
              ),
          ],
        ),

        if (_isEditMode) ...[
          const SizedBox(height: 26),
          Container(
            height: 1,
            margin: const EdgeInsets.only(bottom: 20),
            child: CustomPaint(
              painter: AddMedDashedBorderPainter(color: theme.bd, radius: 0),
            ),
          ),
          AddMedArchiveButton(onTap: _confirmArchive),
        ],

        const SizedBox(height: 26),
        AddMedSaveNotes(
          reminderNote: _freq == 0
              ? 'Reminders scheduled on this phone'
              : _freq == 1
              ? '1 reminder scheduled on this phone'
              : '$_freq reminders scheduled on this phone',
        ),
      ],
    );
  }

  /// The preview's meta line: `500 mg · Twice daily`, or the placeholder.
  String _previewMeta(String amount) {
    final bits = <String>[];
    if (amount.isNotEmpty) bits.add('$amount ${_unitLabel(amount)}');
    if (_freq != 0) {
      bits.add(switch (_freq) {
        3 => 'Thrice daily',
        2 => 'Twice daily',
        _ => 'Once daily',
      });
    }
    return bits.isEmpty ? 'Dosage and frequency pending' : bits.join(' · ');
  }

  Widget _footer(BuildContext context) {
    final theme = AddMedTheme.of(context);
    final missing = _missing;
    final ready = missing.isEmpty && !_saving;

    final label = _saving
        ? (_progress > 0.5
              ? 'Scheduling ${_freq == 1 ? '1 reminder' : '$_freq reminders'}…'
              : 'Saving medication…')
        : (_isEditMode ? 'Save changes' : 'Add medication');

    final readyText = _saving
        ? 'SCHEDULING…'
        : ready
        ? (_isEditMode ? 'CHANGES READY' : 'READY TO SAVE')
        : '${missing.length} '
              '${missing.length == 1 ? 'DETAIL LEFT' : 'DETAILS LEFT'}';

    return Container(
      padding: EdgeInsets.fromLTRB(
        18,
        12,
        18,
        // `AppShell` runs `Scaffold(extendBody: true)`, so Flutter already
        // reports the floating bottom navigation's height as this body's
        // bottom padding — the same seam `MedOrbitFocusPanel` reads on Daily
        // Check-In. Adding the bar's height on top of that inset reserved the
        // band twice and stranded the CTA ~120dp above the bar; the inset
        // alone, plus the prototype's own 20px footer margin, settles it
        // directly above the navigation.
        20 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(gradient: theme.footerScrim),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AddMedReadyRow(
            label: readyText,
            ready: ready || _saving,
            satisfied: [
              for (final key in _requiredKeys) !missing.contains(key),
            ],
          ),
          AddMedCta(
            label: label,
            ready: ready,
            saving: _saving,
            progress: _progress,
            shake: _shake,
            onTap: _submit,
          ),
        ],
      ),
    );
  }
}
