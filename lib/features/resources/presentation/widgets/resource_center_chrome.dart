import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/resource_article.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/resource_center_style.dart';

/// Every glass surface, control and row the Resource Center prototype draws,
/// transcribed from `docs/Design/ForeSeeMe Resource Center.html`.
///
/// Nothing here reads a provider — each widget takes the values it renders, so
/// the screen stays the only place that knows where data comes from.

// ── Primitives ───────────────────────────────────────────────────────────────

/// The prototype's one glass recipe: a translucent fill behind a backdrop blur,
/// with a hairline rim. Collapses to an opaque surface under reduced
/// transparency, where [rcBlur] drops the blur.
class RcGlass extends StatelessWidget {
  const RcGlass({
    super.key,
    required this.theme,
    required this.child,
    this.radius = 22,
    this.fill,
    this.borderColor,
    this.blur = 20,
    this.padding,
    this.shadow,
    this.gradient,
  });

  final ResourceCenterTheme theme;
  final Widget child;
  final double radius;
  final Color? fill;
  final Color? borderColor;
  final double blur;
  final EdgeInsetsGeometry? padding;
  final List<BoxShadow>? shadow;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final border = BorderRadius.circular(radius);
    final surface = ClipRRect(
      borderRadius: border,
      child: BackdropFilter(
        filter: rcBlur(context, blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: gradient == null
                ? theme.solidify(context, fill ?? theme.glass)
                : null,
            gradient: gradient,
            borderRadius: border,
            border: Border.all(color: borderColor ?? theme.line),
          ),
          child: child,
        ),
      ),
    );

    if (shadow == null) return surface;
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: border, boxShadow: shadow),
      child: surface,
    );
  }
}

/// The prototype's card-opening gesture, verbatim: the card lifts
/// (`scale(1.05) translateY(-6px)` plus `0 26px 50px …, 0 0 42px var(--halo)`),
/// the destination opens 180ms later, and the lift settles back after 480ms.
///
/// It replaces a plain press-scale here because the lift *is* the transition —
/// the article grows out of the card the user pushed.
class RcLift extends StatefulWidget {
  const RcLift({
    super.key,
    required this.theme,
    required this.onTap,
    required this.child,
    this.radius = 22,
  });

  final ResourceCenterTheme theme;
  final VoidCallback onTap;
  final Widget child;
  final double radius;

  @override
  State<RcLift> createState() => _RcLiftState();
}

class _RcLiftState extends State<RcLift> {
  bool _lifted = false;
  Timer? _open;
  Timer? _settle;

  @override
  void dispose() {
    _open?.cancel();
    _settle?.cancel();
    super.dispose();
  }

  void _handleTap() {
    if (AppMotion.reduceMotion(context)) {
      widget.onTap();
      return;
    }
    setState(() => _lifted = true);
    _open = Timer(const Duration(milliseconds: 180), widget.onTap);
    _settle = Timer(const Duration(milliseconds: 480), () {
      if (mounted) setState(() => _lifted = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final reduce = AppMotion.reduceMotion(context);
    const duration = Duration(milliseconds: 260);
    const curve = Cubic(0.2, 0.8, 0.3, 1);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handleTap,
      child: AnimatedContainer(
        duration: reduce ? Duration.zero : duration,
        curve: curve,
        transform: Matrix4.identity()..translateByDouble(0, _lifted ? -6 : 0, 0, 1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          boxShadow: _lifted ? widget.theme.liftShadow : const [],
        ),
        child: AnimatedScale(
          scale: _lifted ? 1.05 : 1.0,
          duration: reduce ? Duration.zero : duration,
          curve: curve,
          child: widget.child,
        ),
      ),
    );
  }
}

/// A tracked section rule: `LABEL ───────────── trailing`.
class RcSectionHeader extends StatelessWidget {
  const RcSectionHeader({
    super.key,
    required this.theme,
    required this.label,
    this.trailing,
    this.labelColor,
  });

  final ResourceCenterTheme theme;
  final String label;
  final String? trailing;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: rcMono(
              context,
              size: 9.5,
              em: 0.24,
              color: labelColor ?? theme.mono,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Container(height: 1, color: theme.line)),
        if (trailing != null) ...[
          const SizedBox(width: 10),
          Text(
            trailing!,
            style: rcMono(context, size: 9, color: theme.mono),
          ),
        ],
      ],
    );
  }
}

// ── Header ───────────────────────────────────────────────────────────────────

/// The eyebrow + headline + appearance toggle at the top of the field.
class RcHeader extends StatelessWidget {
  const RcHeader({
    super.key,
    required this.theme,
    required this.onToggleTheme,
  });

  final ResourceCenterTheme theme;
  final VoidCallback onToggleTheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'FORESEEME · RESOURCE CENTER',
                style: rcMono(
                  context,
                  size: 9.5,
                  em: 0.26,
                  color: theme.mono,
                ),
              ),
              const SizedBox(height: 7),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 250),
                child: Semantics(
                  header: true,
                  child: Text(
                    "Knowledge for what's happening around you.",
                    style: rcDisplay(
                      context,
                      size: 25,
                      em: -0.02,
                      color: theme.fg,
                      height: 1.15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Semantics(
          button: true,
          label: theme.isDark ? 'Switch to light theme' : 'Switch to dark theme',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggleTheme,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: ClipOval(
                  child: BackdropFilter(
                    filter: rcBlur(context, 14),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.solidify(context, theme.glass),
                        border: Border.all(color: theme.line),
                      ),
                      // The prototype's glyph: a ring half-filled with the
                      // current ink — a day/night dial, not an icon font.
                      child: Center(
                        child: Container(
                          width: 13,
                          height: 13,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: theme.fg),
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                theme.fg,
                                theme.fg,
                                theme.fg.withValues(alpha: 0),
                                theme.fg.withValues(alpha: 0),
                              ],
                              stops: const [0.0, 0.5, 0.5, 1.0],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Search + emergency ───────────────────────────────────────────────────────

/// The resting search control — a 48px glass slab that opens the search field.
class RcSearchButton extends StatelessWidget {
  const RcSearchButton({
    super.key,
    required this.theme,
    required this.onTap,
  });

  final ResourceCenterTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Search verified guidance',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: RcGlass(
          theme: theme,
          radius: 16,
          blur: 18,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            height: 46,
            child: Row(
              children: [
                _Loupe(color: theme.dim),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Search verified guidance',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: rcBody(context, size: 13.5, color: theme.dim),
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

/// The prototype draws its search glyph as a bare 13px ring, not an icon.
class _Loupe extends StatelessWidget {
  const _Loupe({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 13,
      height: 13,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 1.5),
      ),
    );
  }
}

/// `Need help now?` — the coral banner, plus the standing line beneath it that
/// makes clear ForeSeeMe is not the emergency service.
class RcEmergencyBanner extends StatelessWidget {
  const RcEmergencyBanner({
    super.key,
    required this.theme,
    required this.onTap,
  });

  final ResourceCenterTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          label: 'Need help now? Emergency contacts and immediate-action '
              'guidance.',
          child: PressableScale(
            onTap: onTap,
            child: RcGlass(
                theme: theme,
                radius: 18,
                blur: 16,
                gradient: theme.emergencyFill,
                borderColor: theme.coral.withValues(alpha: 0.34),
                padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: theme.coral.withValues(alpha: 0.14),
                        border: Border.all(
                          color: theme.coral.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Center(
                        child: Container(
                          width: 2,
                          height: 14,
                          decoration: BoxDecoration(
                            color: theme.coral,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Need help now?',
                            style: rcDisplay(
                              context,
                              size: 15,
                              em: -0.01,
                              weight: FontWeight.w600,
                              color: theme.fg,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Emergency contacts and immediate-action guidance.',
                            style: rcBody(
                              context,
                              size: 11.5,
                              color: theme.dim,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    RcChevron(color: theme.coral, size: 7, stroke: 1.5),
                  ],
                ),
              ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Text(
            'FOR EMERGENCIES, CALL YOUR LOCAL EMERGENCY NUMBER.',
            style: rcMono(
              context,
              size: 9,
              em: 0.1,
              color: theme.mono,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

/// The prototype's chevron: a rotated square corner, not a glyph.
class RcChevron extends StatelessWidget {
  const RcChevron({
    super.key,
    required this.color,
    this.size = 6,
    this.stroke = 1,
    this.back = false,
  });

  final Color color;
  final double size;
  final double stroke;

  /// A back chevron rotates the other pair of edges.
  final bool back;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: 0.7853981634, // 45°
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          border: back
              ? Border(
                  left: BorderSide(color: color, width: stroke),
                  bottom: BorderSide(color: color, width: stroke),
                )
              : Border(
                  right: BorderSide(color: color, width: stroke),
                  top: BorderSide(color: color, width: stroke),
                ),
        ),
      ),
    );
  }
}

// ── Category rail ────────────────────────────────────────────────────────────

/// The prototype's filter: no chips, just a row of dots on a hairline. The
/// selected dot grows from 7px to 12px and takes the accent, its halo and its
/// glow; the label brightens with it.
class RcCategoryRail extends StatelessWidget {
  const RcCategoryRail({
    super.key,
    required this.theme,
    required this.pad,
    required this.selected,
    required this.onSelected,
  });

  final ResourceCenterTheme theme;
  final double pad;

  /// `null` is the prototype's `ALL`.
  final ResourceTopic? selected;
  final ValueChanged<ResourceTopic?> onSelected;

  @override
  Widget build(BuildContext context) {
    final entries = <(ResourceTopic?, String)>[
      (null, 'ALL'),
      for (final t in ResourceTopic.values) (t, resourceCatLabel(t)),
    ];

    return SizedBox(
      height: 64,
      child: Stack(
        children: [
          // The hairline the dots sit on: `top:19px`, fading at both ends.
          Positioned(
            left: 0,
            right: 0,
            top: 19,
            height: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.line2.withValues(alpha: 0),
                    theme.line2,
                    theme.line2,
                    theme.line2.withValues(alpha: 0),
                  ],
                  stops: const [0.0, 0.12, 0.88, 1.0],
                ),
              ),
            ),
          ),
          ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: pad),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(width: 20),
            itemBuilder: (context, i) {
              final (topic, label) = entries[i];
              return _CategoryDot(
                theme: theme,
                label: label,
                on: selected == topic,
                onTap: () => onSelected(topic),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CategoryDot extends StatelessWidget {
  const _CategoryDot({
    required this.theme,
    required this.label,
    required this.on,
    required this.onTap,
  });

  final ResourceCenterTheme theme;
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final reduce = AppMotion.reduceMotion(context);
    final duration = reduce ? Duration.zero : const Duration(milliseconds: 300);
    const curve = Cubic(0.2, 0.8, 0.3, 1);
    final dot = on ? 12.0 : 7.0;

    return Semantics(
      button: true,
      selected: on,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              SizedBox(
                height: 14,
                child: Center(
                  child: AnimatedContainer(
                    duration: duration,
                    curve: curve,
                    width: dot,
                    height: dot,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: on
                          ? theme.accent
                          : theme.dim.withValues(alpha: 0.6),
                      boxShadow: on
                          ? [
                              BoxShadow(color: theme.haloS, spreadRadius: 5),
                              BoxShadow(color: theme.halo, blurRadius: 16),
                            ]
                          : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              AnimatedDefaultTextStyle(
                duration: duration,
                curve: AppMotion.curve,
                style: rcMono(
                  context,
                  size: 9,
                  em: 0.14,
                  color: on ? theme.fg : theme.dim.withValues(alpha: 0.65),
                ),
                child: Text(label, maxLines: 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Cards ────────────────────────────────────────────────────────────────────

/// A grid card in `EXPLORE HEALTH KNOWLEDGE`. `wide` is the prototype's
/// `data-span="2"` — a card that takes the full row.
class RcResourceCard extends StatelessWidget {
  const RcResourceCard({
    super.key,
    required this.theme,
    required this.article,
    required this.metaLine,
    required this.onTap,
  });

  final ResourceCenterTheme theme;
  final ResourceArticle article;

  /// The prototype's `read · source` line.
  final String metaLine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final catColor = resourceCatColor(theme, article.topic);

    return RcLift(
      theme: theme,
      onTap: onTap,
      child: Semantics(
        button: true,
        label: '${resourceCatLabel(article.topic)}. ${article.title}',
        child: RcGlass(
          theme: theme,
          fill: theme.card,
          radius: 22,
          child: Stack(
            children: [
              Positioned.fill(
                child: ResourceArtLayer(
                  art: resourceArtFor(article.topic),
                  theme: theme,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            resourceCatLabel(article.topic),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: rcMono(
                              context,
                              size: 8.5,
                              em: 0.18,
                              color: catColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Opacity(
                          opacity: 0.8,
                          child: Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: catColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      article.title,
                      style: rcDisplay(
                        context,
                        size: 15,
                        em: -0.01,
                        color: theme.fg,
                        height: 1.24,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      article.summary,
                      style: rcBody(context, size: 11.5, color: theme.dim),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      metaLine,
                      style: rcMono(
                        context,
                        size: 8.5,
                        em: 0.12,
                        color: theme.mono,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A card on the contextual rail — the prototype's fixed 214×184 slab, with the
/// category at the top and the title anchored to the bottom.
class RcRelevantCard extends StatelessWidget {
  const RcRelevantCard({
    super.key,
    required this.theme,
    required this.article,
    required this.metaLine,
    required this.onTap,
  });

  final ResourceCenterTheme theme;
  final ResourceArticle article;
  final String metaLine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 214,
      child: RcLift(
        theme: theme,
        onTap: onTap,
        child: Semantics(
          button: true,
          label: '${resourceCatLabel(article.topic)}. ${article.title}',
          child: RcGlass(
            theme: theme,
            fill: theme.card,
            radius: 22,
            // The prototype fixes this card at 184px. Held rigid it clips its
            // own title at large text scales, so the height becomes a floor and
            // the rail stretches to the tallest card instead.
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 184),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ResourceArtLayer(
                      art: resourceArtFor(article.topic),
                      theme: theme,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: theme.accent,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                resourceCatLabel(article.topic),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: rcMono(
                                  context,
                                  size: 8.5,
                                  em: 0.18,
                                  color: theme.mono,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                article.title,
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: rcDisplay(
                                  context,
                                  size: 15.5,
                                  em: -0.01,
                                  color: theme.fg,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              metaLine,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: rcMono(
                                context,
                                size: 8.5,
                                em: 0.12,
                                color: theme.mono,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A search result — the prototype's flatter 18px card.
class RcSearchResultCard extends StatelessWidget {
  const RcSearchResultCard({
    super.key,
    required this.theme,
    required this.article,
    required this.metaLine,
    required this.onTap,
  });

  final ResourceCenterTheme theme;
  final ResourceArticle article;
  final String metaLine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final catColor = resourceCatColor(theme, article.topic);

    return Semantics(
      button: true,
      label: '${resourceCatLabel(article.topic)}. ${article.title}',
      child: PressableScale(
        onTap: onTap,
        child: RcGlass(
          theme: theme,
          fill: theme.card,
          radius: 18,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ResourceArtLayer(
                    art: resourceArtFor(article.topic),
                    theme: theme,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        resourceCatLabel(article.topic),
                        style: rcMono(
                          context,
                          size: 8.5,
                          em: 0.18,
                          color: catColor,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        article.title,
                        style: rcDisplay(
                          context,
                          size: 14.5,
                          color: theme.fg,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        metaLine,
                        style: rcMono(
                          context,
                          size: 8.5,
                          em: 0.12,
                          color: theme.mono,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ),
      ),
    );
  }
}

/// A `FULL CATALOGUE` row: an index, the title, its category, a chevron.
class RcCatalogueRow extends StatelessWidget {
  const RcCatalogueRow({
    super.key,
    required this.theme,
    required this.index,
    required this.article,
    required this.onTap,
  });

  final ResourceCenterTheme theme;
  final int index;
  final ResourceArticle article;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${article.title}. ${resourceCatLabel(article.topic)}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 2),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.line)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: MediaQuery.textScalerOf(context).scale(18),
                child: Text(
                  index.toString().padLeft(2, '0'),
                  style: rcMono(context, size: 9, color: theme.mono),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      article.title,
                      style: rcBody(
                        context,
                        size: 13,
                        color: theme.fg,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      resourceCatLabel(article.topic),
                      style: rcMono(
                        context,
                        size: 8.5,
                        em: 0.14,
                        color: theme.mono,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              RcChevron(color: theme.dim),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Facilities ───────────────────────────────────────────────────────────────

/// One row under the radar.
class RcFacilityRow extends StatelessWidget {
  const RcFacilityRow({
    super.key,
    required this.theme,
    required this.name,
    required this.meta,
    required this.distance,
    required this.onTap,
  });

  final ResourceCenterTheme theme;
  final String name;
  final String meta;
  final String distance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$name. $meta. $distance',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.line)),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: theme.accent),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: rcDisplay(
                        context,
                        size: 13.5,
                        color: theme.fg,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      meta,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: rcMono(
                        context,
                        size: 8.5,
                        em: 0.12,
                        color: theme.mono,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                distance,
                style: rcMono(context, size: 11, color: theme.accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The prototype's "no facilities" panel, under the radar.
class RcFacilityNotice extends StatelessWidget {
  const RcFacilityNotice({
    super.key,
    required this.theme,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
    this.busy = false,
  });

  final ResourceCenterTheme theme;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: rcDisplay(context, size: 15, color: theme.fg),
          ),
          const SizedBox(height: 12),
          Text(
            body,
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
            label: actionLabel,
            onTap: onAction,
            busy: busy,
            accented: false,
          ),
        ],
      ),
    );
  }
}

// ── Buttons, skeletons, empty ────────────────────────────────────────────────

/// The prototype's tracked pill control (`EXPLORE ALL GUIDANCE`,
/// `WIDEN SEARCH RADIUS`).
class RcPillButton extends StatelessWidget {
  const RcPillButton({
    super.key,
    required this.theme,
    required this.label,
    required this.onTap,
    this.accented = true,
    this.busy = false,
  });

  final ResourceCenterTheme theme;
  final String label;
  final VoidCallback onTap;
  final bool accented;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: PressableScale(
        onTap: busy ? null : onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: accented
                  ? theme.haloS
                  : theme.solidify(context, theme.glass2),
              border: Border.all(
                color: accented ? theme.accent : theme.line2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy) ...[
                  SizedBox(
                    width: 11,
                    height: 11,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.4,
                      color: theme.accent,
                    ),
                  ),
                  const SizedBox(width: 9),
                ],
                Text(
                  label,
                  style: rcMono(
                    context,
                    size: 10,
                    em: 0.16,
                    color: theme.fg,
                  ),
                ),
              ],
            ),
        ),
      ),
    );
  }
}

/// `ASSEMBLING KNOWLEDGE FIELD` — the prototype's four shimmering slabs. The
/// sweep is the CSS `shimmer` keyframe: a 320px band scrolled across the slab.
class RcFieldSkeletons extends StatefulWidget {
  const RcFieldSkeletons({super.key, required this.theme});

  final ResourceCenterTheme theme;

  /// `skeletons: [{h:120},{h:158},{h:158},{h:96}]`.
  static const List<double> heights = [120, 158, 158, 96];

  @override
  State<RcFieldSkeletons> createState() => _RcFieldSkeletonsState();
}

class _RcFieldSkeletonsState extends State<RcFieldSkeletons>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!AppMotion.reduceMotion(context) && !_sweep.isAnimating) {
      _sweep.repeat();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ASSEMBLING KNOWLEDGE FIELD',
          style: rcMono(context, size: 9.5, em: 0.24, color: theme.mono),
        ),
        const SizedBox(height: 14),
        for (final h in RcFieldSkeletons.heights)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: AnimatedBuilder(
              animation: _sweep,
              builder: (context, _) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    height: h,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: theme.line),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment(-1 + 2 * _sweep.value, 0),
                      widthFactor: 1.8,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: theme.skeletonSweep,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// `Nothing matches this view.` — the prototype's dashed empty panel.
class RcEmptyField extends StatelessWidget {
  const RcEmptyField({
    super.key,
    required this.theme,
    required this.onReset,
    this.body = 'The knowledge field has no entries for this combination yet.',
  });

  final ResourceCenterTheme theme;
  final VoidCallback onReset;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 26),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: theme.solidify(context, theme.glass),
        border: Border.all(color: theme.line2, style: BorderStyle.solid),
      ),
      child: Column(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: theme.line2),
            ),
            child: Center(
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: theme.line2),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Nothing matches this view.',
            textAlign: TextAlign.center,
            style: rcDisplay(context, size: 16, color: theme.fg),
          ),
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 230),
            child: Text(
              body,
              textAlign: TextAlign.center,
              style: rcBody(context, size: 12, color: theme.dim, height: 1.5),
            ),
          ),
          const SizedBox(height: 16),
          RcPillButton(
            theme: theme,
            label: 'EXPLORE ALL GUIDANCE',
            onTap: onReset,
          ),
        ],
      ),
    );
  }
}
