import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/a11y.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/features/profile/presentation/widgets/profile_hub_motion.dart';

import 'add_medication_chrome.dart';
import 'add_medication_style.dart';

/// The three bottom sheets the Add / Edit Medication prototype defines: the
/// reminder-time picker, the save confirmation, and the save failure.
///
/// They are presentation only. Each returns its outcome through
/// [Navigator.pop] and decides nothing itself.

// ── Sheet shell ──────────────────────────────────────────────────────────────

/// The prototype's sheet material: a `--sheet` slab with a 28px top radius, a
/// hairline top border, a blurred backdrop and a lifted shadow.
class _SheetShell extends StatelessWidget {
  const _SheetShell({
    required this.child,
    required this.topBorder,
    this.padding = const EdgeInsets.fromLTRB(18, 20, 18, 22),
  });

  final Widget child;
  final Color topBorder;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = AddMedTheme.of(context);
    final opaque = A11y.reduceTransparency(context);
    const radius = BorderRadius.vertical(top: Radius.circular(28));

    return Padding(
      // Sheets sit above the keyboard, never behind it.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withValues(
                alpha: theme.isDark ? 0.55 : 0.16,
              ),
              blurRadius: 60,
              offset: const Offset(0, -24),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: addMedBlur(context, 20),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: opaque ? theme.bg2 : theme.sheet,
                border: Border(top: BorderSide(color: topBorder)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(padding: padding, child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A 52dp sheet button. [primary] fills it with the accent and its glow.
class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.onTap,
    this.primary = false,
    this.width,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final theme = AddMedTheme.of(context);
    return AddMedGlass(
      onTap: onTap,
      radius: 18,
      blur: 0,
      rim: false,
      padding: EdgeInsets.zero,
      pressedScale: 0.98,
      sinkY: 0,
      solidFill: primary ? theme.accent : Colors.transparent,
      borderColor: primary ? Colors.transparent : theme.bd,
      shadow: primary ? theme.accentButtonShadow : const [],
      semanticLabel: label,
      child: SizedBox(
        width: width,
        height: 52,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: addMedSans(
                context,
                size: 15,
                weight: primary ? FontWeight.w600 : FontWeight.w500,
                color: primary ? theme.onAccent : theme.txt,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Reminder-time picker ─────────────────────────────────────────────────────

/// The prototype's own time picker: three snapping columns under a lit
/// selection band, four presets, and a non-blocking notice when the chosen time
/// already belongs to another reminder.
///
/// Returns the chosen time as minutes past midnight, or null if dismissed.
class AddMedTimePickerSheet extends StatefulWidget {
  const AddMedTimePickerSheet({
    super.key,
    required this.index,
    required this.initialMinutes,
    required this.otherMinutes,
  });

  final int index;
  final int initialMinutes;

  /// The other reminders' times, used for the clash notice.
  final List<int> otherMinutes;

  @override
  State<AddMedTimePickerSheet> createState() => _AddMedTimePickerSheetState();
}

class _AddMedTimePickerSheetState extends State<AddMedTimePickerSheet> {
  late FixedExtentScrollController _hours;
  late FixedExtentScrollController _minutes;
  late FixedExtentScrollController _period;

  late int _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialMinutes;
    final h24 = _value ~/ 60;
    var h = h24 % 12;
    if (h == 0) h = 12;
    _hours = FixedExtentScrollController(initialItem: h - 1);
    _minutes = FixedExtentScrollController(
      initialItem: ((_value % 60) / 5).round() % 12,
    );
    _period = FixedExtentScrollController(initialItem: h24 < 12 ? 0 : 1);
  }

  @override
  void dispose() {
    _hours.dispose();
    _minutes.dispose();
    _period.dispose();
    super.dispose();
  }

  /// The prototype's `readColumns()`: recompose the minute-of-day from the
  /// three columns.
  void _read() {
    final h = _hours.selectedItem % 12 + 1;
    final m = (_minutes.selectedItem % 12) * 5;
    final pm = _period.selectedItem % 2 == 1;
    var h24 = h % 12;
    if (pm) h24 += 12;
    final next = h24 * 60 + m;
    if (next != _value) setState(() => _value = next);
  }

  /// The prototype's `setPick(mins)`: a preset moves the columns, which then
  /// report the new value back through [_read].
  void _applyPreset(int mins) {
    final h24 = mins ~/ 60;
    var h = h24 % 12;
    if (h == 0) h = 12;
    const duration = Duration(milliseconds: 260);
    const curve = Cubic(0.2, 0.8, 0.2, 1);
    _hours.animateToItem(h - 1, duration: duration, curve: curve);
    _minutes.animateToItem((mins % 60) ~/ 5, duration: duration, curve: curve);
    _period.animateToItem(h24 < 12 ? 0 : 1, duration: duration, curve: curve);
    setState(() => _value = mins);
  }

  @override
  Widget build(BuildContext context) {
    final theme = AddMedTheme.of(context);
    final clash = widget.otherMinutes.contains(_value);

    return _SheetShell(
      topBorder: theme.bd,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: theme.bd,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Reminder ${widget.index + 1} time',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: addMedSans(
                    context,
                    size: 17,
                    weight: FontWeight.w600,
                    em: -0.02,
                    color: theme.txt,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                addMedFormatTime(_value),
                style: addMedMono(context, size: 15, color: theme.accent),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 176,
            child: Stack(
              children: [
                // The lit selection band the columns snap into.
                Positioned(
                  left: 0,
                  right: 0,
                  top: 66,
                  height: 44,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.accSoft,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: theme.accent.withValues(alpha: 0.32),
                        ),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: _WheelColumn(
                        controller: _hours,
                        count: 12,
                        label: (i) => (i + 1).toString().padLeft(2, '0'),
                        fontSize: 20,
                        semanticLabel: 'Hour',
                        onChanged: _read,
                      ),
                    ),
                    SizedBox(
                      width: 8,
                      child: Center(
                        child: Text(
                          ':',
                          style: addMedMono(
                            context,
                            size: 20,
                            color: theme.txt3,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _WheelColumn(
                        controller: _minutes,
                        count: 12,
                        label: (i) => (i * 5).toString().padLeft(2, '0'),
                        fontSize: 20,
                        semanticLabel: 'Minute',
                        onChanged: _read,
                      ),
                    ),
                    Expanded(
                      child: _WheelColumn(
                        controller: _period,
                        count: 2,
                        label: (i) => i == 0 ? 'AM' : 'PM',
                        fontSize: 18,
                        em: 0.06,
                        semanticLabel: 'AM or PM',
                        onChanged: _read,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final preset in const <MapEntry<String, int>>[
                  MapEntry('Morning 8:00', 480),
                  MapEntry('Noon 12:00', 720),
                  MapEntry('Evening 6:00', 1080),
                  MapEntry('Bedtime 10:00', 1320),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: AddMedTagChip(
                      label: preset.key,
                      minHeight: 38,
                      selected: _value == preset.value,
                      onTap: () => _applyPreset(preset.value),
                    ),
                  ),
              ],
            ),
          ),
          if (clash)
            const AddMedNotice(
              text: 'Another reminder already uses this time — two '
                  'notifications will arrive together.',
              warning: true,
              padding: EdgeInsets.only(top: 12),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              _SheetButton(
                label: 'Cancel',
                width: 108,
                onTap: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SheetButton(
                  label: 'Set time',
                  primary: true,
                  onTap: () => Navigator.of(context).pop(_value),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One snapping column of the picker.
///
/// [ListWheelScrollView] is what draws the prototype's `rotateX` /
/// `translateZ` / `scale` falloff — the CSS recomputes those per item on every
/// scroll frame; the wheel does the same projection natively, so the falloff is
/// not hand-rolled a second time. `diameterRatio: 1.3` is the wheel whose
/// 44px item subtends the prototype's own 22° per step.
class _WheelColumn extends StatelessWidget {
  const _WheelColumn({
    required this.controller,
    required this.count,
    required this.label,
    required this.fontSize,
    required this.semanticLabel,
    required this.onChanged,
    this.em = 0,
  });

  final FixedExtentScrollController controller;
  final int count;
  final String Function(int index) label;
  final double fontSize;
  final double em;
  final String semanticLabel;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = AddMedTheme.of(context);
    return Semantics(
      label: semanticLabel,
      child: ListWheelScrollView.useDelegate(
        controller: controller,
        itemExtent: 44,
        diameterRatio: 1.3,
        perspective: 0.003,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: (_) => onChanged(),
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: count,
          builder: (context, index) => AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final selected = controller.hasClients
                  ? controller.selectedItem == index
                  : controller.initialItem == index;
              return Center(
                child: Text(
                  label(index),
                  style: addMedMono(
                    context,
                    size: fontSize,
                    em: em,
                    color: selected ? theme.txt : theme.txt2,
                    weight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── Save confirmation ────────────────────────────────────────────────────────

/// Shown once the medication is stored and its reminders are scheduled.
///
/// Pops `true` from `Add another`, and `false` (or null, on a dismiss) from
/// `Done` — the caller decides what each means.
class AddMedSuccessSheet extends StatelessWidget {
  const AddMedSuccessSheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.reminderLine,
    required this.offerAnother,
  });

  final String title;
  final String subtitle;
  final String reminderLine;

  /// False in edit mode, where "add another" is not the next thing anyone wants.
  final bool offerAnother;

  @override
  Widget build(BuildContext context) {
    final theme = AddMedTheme.of(context);

    Widget tick(String text) => Padding(
      padding: const EdgeInsets.only(top: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 16,
            height: 16,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.accSoft,
            ),
            child: Icon(Icons.check_rounded, size: 10, color: theme.accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: addMedSans(
                context,
                size: 12.5,
                color: theme.txt2,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );

    return _SheetShell(
      topBorder: theme.accent.withValues(alpha: 0.34),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const _SuccessMark(),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: addMedSans(
                        context,
                        size: 18,
                        weight: FontWeight.w600,
                        em: -0.02,
                        color: theme.txt,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: addMedSans(
                        context,
                        size: 12.5,
                        color: theme.txt2,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 17),
          AddMedGlass(
            radius: 18,
            blur: 0,
            rim: false,
            shadow: const [],
            solidFill: theme.field,
            borderColor: theme.bd,
            padding: const EdgeInsets.fromLTRB(15, 5, 15, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                tick('Active in your medication list'),
                tick(reminderLine),
                tick('Doses will appear in Daily Check-In'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (offerAnother) ...[
                Expanded(
                  child: _SheetButton(
                    label: 'Add another',
                    onTap: () => Navigator.of(context).pop(true),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: _SheetButton(
                  label: 'Done',
                  primary: true,
                  onTap: () => Navigator.of(context).pop(false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The confirmation tick and its two expanding rings (`fm-pop` + `fm-ripple`).
class _SuccessMark extends StatelessWidget {
  const _SuccessMark();

  @override
  Widget build(BuildContext context) {
    final theme = AddMedTheme.of(context);

    final mark = Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.accSoft,
        border: Border.all(color: theme.accent.withValues(alpha: 0.45)),
        boxShadow: [BoxShadow(color: theme.glow, blurRadius: 26)],
      ),
      child: Icon(Icons.check_rounded, size: 22, color: theme.accent),
    );

    if (AppMotion.reduceMotion(context)) return mark;

    return SizedBox(
      width: 46,
      height: 46,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          for (var i = 0; i < 2; i++)
            AmbientLoop(
              period: const Duration(milliseconds: 1600),
              restT: 0,
              builder: (context, t, _) {
                final phase = (t + i * 0.45) % 1;
                return Opacity(
                  opacity: 0.7 * (1 - phase),
                  child: Transform.scale(
                    scale: 0.7 + phase * 1.2,
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: theme.accent),
                      ),
                    ),
                  ),
                );
              },
            ),
          mark,
        ],
      ),
    );
  }
}

// ── Save failure ─────────────────────────────────────────────────────────────

/// Shown when the save did not happen. Pops `true` from `Try again`.
class AddMedFailSheet extends StatelessWidget {
  const AddMedFailSheet({
    super.key,
    required this.title,
    required this.tag,
    required this.body,
  });

  final String title;
  final String tag;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = AddMedTheme.of(context);

    return _SheetShell(
      topBorder: theme.warn.withValues(alpha: 0.4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.warn.withValues(alpha: 0.12),
                  border: Border.all(color: theme.warn.withValues(alpha: 0.45)),
                ),
                child: AddMedBangGlyph(
                  size: 26,
                  color: theme.warn,
                  borderWidth: 0,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: addMedSans(
                        context,
                        size: 18,
                        weight: FontWeight.w600,
                        em: -0.02,
                        color: theme.txt,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tag,
                      style: addMedMono(
                        context,
                        size: 9.5,
                        em: 0.14,
                        color: theme.warn,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          AddMedGlass(
            radius: 18,
            blur: 0,
            rim: false,
            shadow: const [],
            solidFill: theme.field,
            borderColor: theme.bd,
            padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
            child: Text(
              body,
              style: addMedSans(
                context,
                size: 13,
                color: theme.txt2,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _SheetButton(
                label: 'Keep editing',
                width: 122,
                onTap: () => Navigator.of(context).pop(false),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SheetButton(
                  label: 'Try again',
                  primary: true,
                  onTap: () => Navigator.of(context).pop(true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
