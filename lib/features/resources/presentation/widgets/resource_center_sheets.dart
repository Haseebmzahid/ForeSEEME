import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/resource_article.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/resource_center_chrome.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/resource_center_style.dart';

/// The Resource Center's three overlays — search, emergency and facility —
/// transcribed from the prototype.
///
/// All three are pushed on the **root** navigator so they cover the app's
/// floating `AppBottomNavBar`, exactly as the prototype's overlays cover its own
/// mock navigation. The prototype's `rise` keyframe
/// (`translateY(26px) → 0`, `opacity 0 → 1`, `cubic-bezier(.2,.8,.3,1)`) is the
/// transition for each of them.

/// `cubic-bezier(.2,.8,.3,1)` — the prototype's house curve.
const Curve _rise = Cubic(0.2, 0.8, 0.3, 1);

/// The prototype's `rise` entrance, applied to a full-bleed overlay.
Widget _riseTransition(Animation<double> animation, Widget child) {
  final curved = CurvedAnimation(parent: animation, curve: _rise);
  return FadeTransition(
    opacity: curved,
    child: AnimatedBuilder(
      animation: curved,
      builder: (context, inner) => Transform.translate(
        offset: Offset(0, 26 * (1 - curved.value)),
        child: inner,
      ),
      child: child,
    ),
  );
}

// ── Search ───────────────────────────────────────────────────────────────────

/// Opens the prototype's search layer: a full-bleed panel over an opaque
/// `bg2 → bg` gradient, with the field already focused.
Future<void> showRcSearch({
  required BuildContext context,
  required ResourceCenterTheme theme,
  required List<ResourceArticle> articles,
  required String Function(ResourceArticle) metaLine,
  required void Function(ResourceArticle) onOpen,
}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: false,
      transitionDuration: AppMotion.reduceMotion(context)
          ? Duration.zero
          : const Duration(milliseconds: 320),
      reverseTransitionDuration: AppMotion.reduceMotion(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      pageBuilder: (context, _, _) => RcSearchLayer(
        theme: theme,
        articles: articles,
        metaLine: metaLine,
        onOpen: onOpen,
      ),
      transitionsBuilder: (context, animation, _, child) =>
          _riseTransition(animation, child),
    ),
  );
}

/// The search layer itself. Filtering is the prototype's own predicate — title,
/// preview and category, case-insensitive — run over whatever list the screen
/// hands in (already narrowed by the active category).
class RcSearchLayer extends StatefulWidget {
  const RcSearchLayer({
    super.key,
    required this.theme,
    required this.articles,
    required this.metaLine,
    required this.onOpen,
  });

  final ResourceCenterTheme theme;
  final List<ResourceArticle> articles;
  final String Function(ResourceArticle) metaLine;
  final void Function(ResourceArticle) onOpen;

  @override
  State<RcSearchLayer> createState() => _RcSearchLayerState();
}

class _RcSearchLayerState extends State<RcSearchLayer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Matches on title, summary, **every** category the resource is filed
  /// under, and the publisher — so "WHO", "heart" and "air quality" all find
  /// the resources a reader would expect them to.
  List<ResourceArticle> get _results {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.articles;
    return widget.articles.where((a) {
      final categories = a.categories.map(resourceCatLabel).join(' ');
      final haystack =
          '${a.title} ${a.summary} $categories ${a.sourceName} '
                  '${a.authority.shortLabel}'
              .toLowerCase();
      return haystack.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final pad = rcPad(context);
    final results = _results;
    final hasQuery = _query.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: true,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [theme.bg2, theme.bg],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(pad, 10, pad, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(color: theme.haloS, blurRadius: 30),
                          ],
                        ),
                        child: RcGlass(
                          theme: theme,
                          radius: 16,
                          blur: 20,
                          fill: theme.glass2,
                          borderColor: theme.accent,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: SizedBox(
                            height: 46,
                            child: Row(
                              children: [
                                Container(
                                  width: 13,
                                  height: 13,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: theme.accent,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: _controller,
                                    focusNode: _focus,
                                    autofocus: true,
                                    onChanged: (v) => setState(() => _query = v),
                                    cursorColor: theme.accent,
                                    style: rcBody(
                                      context,
                                      size: 14,
                                      color: theme.fg,
                                    ),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      border: InputBorder.none,
                                      hintText: 'Search verified guidance',
                                      hintStyle: rcBody(
                                        context,
                                        size: 14,
                                        color: theme.dim,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Semantics(
                      button: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 44),
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          alignment: Alignment.center,
                          child: Text(
                            'CLOSE',
                            style: rcMono(
                              context,
                              size: 10,
                              em: 0.14,
                              color: theme.dim,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(pad, 16, pad, 6),
                child: Text(
                  hasQuery ? '${results.length} MATCHES IN FIELD' : 'FULL FIELD',
                  style: rcMono(
                    context,
                    size: 9,
                    em: 0.2,
                    color: theme.mono,
                  ),
                ),
              ),
              Expanded(
                child: results.isEmpty
                    ? SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(pad + 6, 34, pad + 6, 40),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Nothing matches this view.',
                              style: rcDisplay(
                                context,
                                size: 16,
                                color: theme.fg,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Try a broader term, or return to the full '
                              'knowledge field.',
                              style: rcBody(
                                context,
                                size: 12,
                                color: theme.dim,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 12),
                            RcPillButton(
                              theme: theme,
                              label: 'EXPLORE ALL GUIDANCE',
                              onTap: () {
                                _controller.clear();
                                setState(() => _query = '');
                              },
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.fromLTRB(pad, 4, pad, 40),
                        itemCount: results.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final article = results[i];
                          return AppReveal(
                            delayMs: (i * 40).clamp(0, 240),
                            offsetY: 26,
                            child: RcSearchResultCard(
                              theme: theme,
                              article: article,
                              metaLine: widget.metaLine(article),
                              onTap: () {
                                Navigator.of(context).pop();
                                widget.onOpen(article);
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Bottom sheets ────────────────────────────────────────────────────────────

/// Presents [child] as the prototype's bottom sheet: a blurred scrim that fades
/// in, and a rounded glass panel that rises.
/// The prototype's scrim is a fixed near-black in **both** themes
/// (`rgba(2,8,9,·)`) — it is the stage going dark behind the sheet, not a
/// surface that re-tints with the palette.
const Color _scrimInk = Color(0xFF020809);

Future<void> _showRcSheet({
  required BuildContext context,
  required ResourceCenterTheme theme,
  required double scrimAlpha,
  required double scrimBlur,
  required WidgetBuilder builder,
}) {
  final reduce = AppMotion.reduceMotion(context);
  return showGeneralDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: reduce
        ? Duration.zero
        : const Duration(milliseconds: 340),
    pageBuilder: (context, _, _) => const SizedBox.shrink(),
    transitionBuilder: (context, animation, _, _) {
      final curved = CurvedAnimation(parent: animation, curve: _rise);
      return Stack(
        children: [
          // `IgnorePointer` so the modal barrier beneath still receives the
          // tap-outside-to-dismiss — a `ColoredBox` with a visible colour
          // absorbs hits on its own.
          Positioned.fill(
            child: IgnorePointer(
              child: FadeTransition(
                opacity: curved,
                child: BackdropFilter(
                  filter: rcBlur(context, scrimBlur),
                  child: ColoredBox(
                    color: _scrimInk.withValues(alpha: scrimAlpha),
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(curved),
              child: FadeTransition(opacity: curved, child: builder(context)),
            ),
          ),
        ],
      );
    },
  );
}

/// The panel body shared by both sheets: a rounded glass slab with a grab
/// handle.
class _RcSheetShell extends StatelessWidget {
  const _RcSheetShell({
    required this.theme,
    required this.borderColor,
    required this.children,
  });

  final ResourceCenterTheme theme;
  final Color borderColor;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final pad = rcPad(context);
    // `AppShell` runs `Scaffold(extendBody: true)`, so `padding.bottom` already
    // carries the floating nav bar's height. The sheet sits above the bar and
    // only needs the prototype's own 30px of breathing room plus that inset.
    final bottom = 30 + MediaQuery.paddingOf(context).bottom;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: rcBlur(context, 30),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.solidify(context, theme.sheet),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(top: BorderSide(color: borderColor)),
            boxShadow: theme.sheetShadow,
          ),
          child: SafeArea(
            top: false,
            bottom: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(pad, 18, pad, bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.line2,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `IMMEDIATE HELP` — the emergency sheet.
///
/// The prototype's second action is a fixture "severe episode guidance"
/// article. Production routes it to the app's real nearby-care directory
/// instead: it is the escalation ForeSeeMe can actually perform, and inventing
/// an emergency article the catalogue does not contain would be a fabricated
/// medical claim.
Future<void> showRcEmergencySheet({
  required BuildContext context,
  required ResourceCenterTheme theme,
  required String contactName,
  required String contactDescription,
  required VoidCallback onCall,
  required VoidCallback onFindCare,
}) {
  return _showRcSheet(
    context: context,
    theme: theme,
    scrimAlpha: 0.62, // `rgba(2,8,9,.62)`
    scrimBlur: 8,
    builder: (sheetContext) => _RcSheetShell(
      theme: theme,
      borderColor: theme.coral.withValues(alpha: 0.4),
      children: [
        Text(
          'IMMEDIATE HELP',
          style: rcMono(sheetContext, size: 9, em: 0.24, color: theme.coral),
        ),
        const SizedBox(height: 6),
        Semantics(
          header: true,
          child: Text(
            'Need help now?',
            style: rcDisplay(
              sheetContext,
              size: 21,
              em: -0.02,
              weight: FontWeight.w600,
              color: theme.fg,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'ForeSeeMe is not an emergency service and does not assess your '
          'condition.',
          style: rcBody(
            sheetContext,
            size: 12.5,
            color: theme.dim,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        _RcSheetAction(
          theme: theme,
          label: 'Call $contactName',
          sublabel: contactDescription,
          gradient: theme.emergencyActionFill,
          borderColor: theme.coral.withValues(alpha: 0.55),
          onTap: () {
            Navigator.of(sheetContext).pop();
            onCall();
          },
        ),
        const SizedBox(height: 12),
        _RcSheetMonoAction(
          theme: theme,
          label: 'FIND NEAREST CARE',
          onTap: () {
            Navigator.of(sheetContext).pop();
            onFindCare();
          },
        ),
        const SizedBox(height: 16),
        Text(
          'FOR EMERGENCIES, CALL YOUR LOCAL EMERGENCY NUMBER. FORESEEME DOES '
          'NOT ROUTE EMERGENCY CALLS.',
          style: rcMono(
            sheetContext,
            size: 9,
            em: 0.1,
            color: theme.mono,
            height: 1.6,
          ),
        ),
      ],
    ),
  );
}

/// The facility sheet. Every value shown is one Places actually returned —
/// where it returned nothing, the prototype's own honest placeholder
/// (`HOURS UNKNOWN`) is used rather than an invented opening time.
Future<void> showRcFacilitySheet({
  required BuildContext context,
  required ResourceCenterTheme theme,
  required String name,
  required String type,
  required String distance,
  required String hours,
  required String updated,
  required VoidCallback onDirections,
  String? phone,
  VoidCallback? onCall,
}) {
  return _showRcSheet(
    context: context,
    theme: theme,
    scrimAlpha: 0.55, // the facility sheet's lighter `rgba(2,8,9,.55)`
    scrimBlur: 6,
    builder: (sheetContext) => _RcSheetShell(
      theme: theme,
      borderColor: theme.line2,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    type,
                    style: rcMono(
                      sheetContext,
                      size: 9,
                      em: 0.22,
                      color: theme.mono,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Semantics(
                    header: true,
                    child: Text(
                      name,
                      style: rcDisplay(
                        sheetContext,
                        size: 19,
                        em: -0.01,
                        color: theme.fg,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  distance,
                  style: rcDisplay(
                    sheetContext,
                    size: 26,
                    weight: FontWeight.w600,
                    color: theme.accent,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'STRAIGHT LINE',
                  style: rcMono(
                    sheetContext,
                    size: 8.5,
                    em: 0.14,
                    color: theme.mono,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _RcFactChip(theme: theme, label: hours),
            _RcFactChip(theme: theme, label: updated),
            if (phone != null) _RcFactChip(theme: theme, label: phone),
          ],
        ),
        const SizedBox(height: 16),
        _RcSheetAction(
          theme: theme,
          label: 'Get directions',
          borderColor: theme.accent,
          fill: theme.haloS,
          onTap: () {
            Navigator.of(sheetContext).pop();
            onDirections();
          },
        ),
        if (onCall != null) ...[
          const SizedBox(height: 12),
          _RcSheetMonoAction(
            theme: theme,
            label: 'CALL FACILITY',
            onTap: () {
              Navigator.of(sheetContext).pop();
              onCall();
            },
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'FACILITY RECORD FROM THE PLACES DIRECTORY. OPENING HOURS ARE NOT '
          'CONFIRMED BY FORESEEME.',
          style: rcMono(
            sheetContext,
            size: 9,
            em: 0.1,
            color: theme.mono,
            height: 1.6,
          ),
        ),
      ],
    ),
  );
}

class _RcFactChip extends StatelessWidget {
  const _RcFactChip({required this.theme, required this.label});

  final ResourceCenterTheme theme;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: theme.solidify(context, theme.glass),
        border: Border.all(color: theme.line),
      ),
      child: Text(
        label,
        style: rcMono(context, size: 8.5, em: 0.12, color: theme.dim),
      ),
    );
  }
}

/// The sheets' primary control — a 52px slab in display type.
class _RcSheetAction extends StatelessWidget {
  const _RcSheetAction({
    required this.theme,
    required this.label,
    required this.borderColor,
    required this.onTap,
    this.sublabel,
    this.gradient,
    this.fill,
  });

  final ResourceCenterTheme theme;
  final String label;
  final String? sublabel;
  final Color borderColor;
  final Gradient? gradient;
  final Color? fill;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: sublabel == null ? label : '$label. $sublabel',
      child: PressableScale(
        onTap: onTap,
        child: GestureDetector(
        behavior: HitTestBehavior.opaque,
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: gradient,
              color: gradient == null ? fill : null,
              border: Border.all(color: borderColor),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: rcDisplay(
                    context,
                    size: 15,
                    weight: FontWeight.w600,
                    color: theme.fg,
                  ),
                ),
                if (sublabel != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    sublabel!,
                    textAlign: TextAlign.center,
                    style: rcMono(
                      context,
                      size: 8.5,
                      em: 0.12,
                      color: theme.mono,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The sheets' secondary control — tracked mono on glass.
class _RcSheetMonoAction extends StatelessWidget {
  const _RcSheetMonoAction({
    required this.theme,
    required this.label,
    required this.onTap,
  });

  final ResourceCenterTheme theme;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: PressableScale(
        onTap: onTap,
        child: GestureDetector(
        behavior: HitTestBehavior.opaque,
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 48),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: theme.solidify(context, theme.glass),
              border: Border.all(color: theme.line2),
            ),
            child: Text(
              label,
              style: rcMono(context, size: 10.5, em: 0.14, color: theme.fg),
            ),
          ),
        ),
      ),
    );
  }
}
