import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/a11y.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_map_style.dart';

/// Floating chrome for the Risk Map, transcribed from the approved prototype
/// (`docs/Design/ForeSeeMe Risk Map.html`).
///
/// Every widget here is presentation only — it takes values and callbacks and
/// owns no state, no provider and no navigation decision. Scope is the Risk Map
/// screen; nothing else in the app imports this file.

/// Mono type for technical labels. Built from the design system's existing
/// [ForeSeeMeTelemetry] (IBM Plex Mono — the prototype's own mono face), so
/// this screen adds no second typography system; only size, tracking and colour
/// vary per the prototype.
///
/// The prototype expresses tracking in `em`; it is converted here to the
/// logical pixels Flutter wants (`size * em`).
TextStyle mapMono(
  BuildContext context, {
  required double size,
  double em = 0,
  required Color color,
  FontWeight weight = FontWeight.w400,
}) => context.fsmTelemetry.channel.copyWith(
  fontSize: size,
  letterSpacing: size * em,
  color: color,
  fontWeight: weight,
  height: 1.25,
);

/// The prototype's frosted panel: translucent fill, hairline border, backdrop
/// blur. Blur is dropped under the reduced-transparency accessibility setting,
/// where [A11y] also makes the fill carry the contrast on its own.
class MapGlassPanel extends StatelessWidget {
  const MapGlassPanel({
    super.key,
    required this.child,
    this.radius = 14,
    this.blur = 14,
    this.padding = EdgeInsets.zero,
    this.borderColor,
    this.color,
    this.boxShadow,
  });

  final Widget child;
  final double radius;
  final double blur;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;
  final Color? color;
  final List<BoxShadow>? boxShadow;

  @override
  Widget build(BuildContext context) {
    final t = RiskMapTheme.of(context);
    final opaque = A11y.reduceTransparency(context);
    final fill = color ?? t.panel;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: boxShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: A11y.blurSigma(context, sigma: blur),
            sigmaY: A11y.blurSigma(context, sigma: blur),
          ),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: opaque ? Color.alphaBlend(fill, t.mapBg) : fill,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: borderColor ?? t.hair),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A 48×48 glass control — the prototype's single button shape for every map
/// affordance. 48dp square, so it meets the minimum touch target unchanged.
class MapIconButton extends StatelessWidget {
  const MapIconButton({
    super.key,
    required this.semanticLabel,
    required this.onPressed,
    this.icon,
    this.label,
    this.active = false,
    this.radius = 15,
  });

  final String semanticLabel;
  final VoidCallback onPressed;

  /// Icon form. Exactly one of [icon] / [label] is used.
  final IconData? icon;

  /// Mono text form (the prototype's FIELD / BASE toggle).
  final String? label;

  /// Accent treatment for a control that is currently on.
  final bool active;

  final double radius;

  @override
  Widget build(BuildContext context) {
    final t = RiskMapTheme.of(context);
    final ink = active ? RiskMapTheme.accent : t.ink;

    return Semantics(
      button: true,
      label: semanticLabel,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: MapGlassPanel(
          radius: radius,
          color: active
              ? RiskMapTheme.accent.withValues(alpha: 0.16)
              : null,
          borderColor: active
              ? RiskMapTheme.accent.withValues(alpha: 0.5)
              : null,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(radius),
              child: SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: label != null
                      ? Text(
                          label!,
                          style: mapMono(
                            context,
                            size: 9,
                            em: 0.08,
                            color: active ? RiskMapTheme.accent : t.ink2,
                          ),
                        )
                      : Icon(icon, size: 19, color: ink),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The top "CURRENT REGION" bar: a live teal status dot, the region name, and
/// the region-picker control.
class MapRegionBar extends StatelessWidget {
  const MapRegionBar({
    super.key,
    required this.regionName,
    required this.onSearch,
    required this.searchOpen,
  });

  final String regionName;
  final VoidCallback onSearch;
  final bool searchOpen;

  @override
  Widget build(BuildContext context) {
    final t = RiskMapTheme.of(context);

    return MapGlassPanel(
      radius: 14,
      padding: const EdgeInsets.only(left: 14),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            // Live dot with the prototype's 4px accent halo.
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: RiskMapTheme.accent,
                boxShadow: [
                  BoxShadow(
                    color: RiskMapTheme.accent.withValues(alpha: 0.16),
                    spreadRadius: 4,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CURRENT REGION',
                    style: mapMono(context, size: 9, em: 0.16, color: t.ink2),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    regionName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.fsmText.bodyMedium?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: t.ink,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            Semantics(
              button: true,
              label: searchOpen ? 'Close region list' : 'Choose a region',
              onTap: onSearch,
              child: ExcludeSemantics(
                child: Material(
                  color: t.btn,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: onSearch,
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Icon(
                        searchOpen ? Icons.close_rounded : Icons.search_rounded,
                        size: 19,
                        color: t.ink,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The prototype's signature **RISK FIELD puck** — the concentric field mark,
/// the level, its trend, and the freshness line.
class RiskFieldPuck extends StatelessWidget {
  const RiskFieldPuck({
    super.key,
    required this.style,
    required this.levelLabel,
    required this.trendLabel,
    required this.confidenceLabel,
    required this.freshnessLabel,
    required this.freshnessColor,
  });

  final RiskFieldStyle style;

  /// Written level, from `RiskVisuals` — so the puck agrees with the sheet.
  final String levelLabel;
  final String trendLabel;
  final String confidenceLabel;
  final String freshnessLabel;
  final Color freshnessColor;

  @override
  Widget build(BuildContext context) {
    final t = RiskMapTheme.of(context);

    return MapGlassPanel(
      radius: 18,
      blur: 16,
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 11),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.32),
          blurRadius: 40,
          offset: const Offset(0, 18),
        ),
      ],
      child: SizedBox(
        width: 178 - 26,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The panel is a fixed 178dp wide, so both labels flex: at a large
            // text scale the header truncates rather than overflowing.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    'RISK FIELD',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mapMono(context, size: 9, em: 0.16, color: t.ink2),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    confidenceLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: mapMono(context, size: 9, em: 0.1, color: t.ink2),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                _FieldMark(style: style),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        levelLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.fsmText.titleMedium?.copyWith(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.17,
                          color: t.ink,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        trendLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: mapMono(context, size: 10, color: t.ink2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Container(
              height: 1,
              color: t.hair,
              margin: const EdgeInsets.only(top: 10, bottom: 8),
            ),
            Text(
              freshnessLabel,
              style: mapMono(
                context,
                size: 9.5,
                em: 0.06,
                color: freshnessColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The 46×46 concentric field mark: a radial glow under two rings and a solid
/// core — the puck's miniature of the field drawn on the map.
class _FieldMark extends StatelessWidget {
  const _FieldMark({required this.style});

  final RiskFieldStyle style;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      height: 46,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(0, -0.24),
                  radius: 0.72,
                  colors: [
                    style.color.withValues(alpha: 0.45),
                    style.color.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            top: 7,
            bottom: 7,
            left: 7,
            right: 7,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: style.color.withValues(alpha: 0.9),
                  width: 1.5,
                ),
              ),
            ),
          ),
          Positioned.fill(
            top: 15,
            bottom: 15,
            left: 15,
            right: 15,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: style.color.withValues(alpha: 0.45),
                ),
              ),
            ),
          ),
          Positioned.fill(
            top: 21,
            bottom: 21,
            left: 21,
            right: 21,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: style.color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The prototype's data-condition banner (stale / offline / not refreshed).
class MapBanner extends StatelessWidget {
  const MapBanner({super.key, required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = RiskMapTheme.of(context);
    return MapGlassPanel(
      radius: 13,
      color: color.withValues(alpha: 0.14),
      borderColor: color.withValues(alpha: 0.42),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: context.fsmText.bodySmall?.copyWith(
                fontSize: 11.5,
                height: 1.35,
                color: t.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The legend body: a swatch, a three-bar elevation glyph encoding how many
/// contours the level draws, and the level name.
///
/// The elevation glyph is the accessibility point — it restates intensity as
/// height, so the legend does not rely on hue.
class RiskFieldLegendBody extends StatelessWidget {
  const RiskFieldLegendBody({super.key});

  static const Map<String, List<double>> _heights = {
    'LOW': [4, 3, 2],
    'MEDIUM': [8, 6, 4],
    'HIGH': [12, 9, 6],
    'UNKNOWN': [2, 2, 2],
  };

  static const Map<String, double> _swatchAlpha = {
    'LOW': 0.18,
    'MEDIUM': 0.20,
    'HIGH': 0.24,
    'UNKNOWN': 0,
  };

  static const Map<String, double> _borderAlpha = {
    'LOW': 0.5,
    'MEDIUM': 0.55,
    'HIGH': 0.6,
    'UNKNOWN': 0.6,
  };

  @override
  Widget build(BuildContext context) {
    final t = RiskMapTheme.of(context);

    return MapGlassPanel(
      radius: 14,
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'RISK LEVEL',
            style: mapMono(context, size: 9, em: 0.16, color: t.ink2),
          ),
          const SizedBox(height: 9),
          for (final style in RiskFieldStyle.all) ...[
            if (style != RiskFieldStyle.all.first) const SizedBox(height: 7),
            _LegendRow(style: style, ink: t.ink),
          ],
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.style, required this.ink});

  final RiskFieldStyle style;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final heights = RiskFieldLegendBody._heights[style.label]!;
    final swatchAlpha = RiskFieldLegendBody._swatchAlpha[style.label]!;
    final borderAlpha = RiskFieldLegendBody._borderAlpha[style.label]!;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Swatch — dashed for the uncertain level, so it is a different kind
        // of mark rather than a fainter one.
        CustomPaint(
          size: const Size(26, 12),
          painter: _SwatchPainter(
            fill: style.color.withValues(alpha: swatchAlpha),
            border: style.color.withValues(alpha: borderAlpha),
            dashed: style.isUnknown,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 26,
          height: 12,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 2),
                Expanded(
                  child: Container(
                    height: heights[i],
                    color: style.color.withValues(
                      alpha: [0.85, 0.6, 0.35][i],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          style.label,
          style: mapMono(context, size: 9.5, em: 0.1, color: ink),
        ),
      ],
    );
  }
}

// ── Sheet sections ───────────────────────────────────────────────────────────

/// One measured cell in the sheet's telemetry grid.
@immutable
class MapTelemetryCell {
  const MapTelemetryCell({
    required this.label,
    required this.value,
    required this.unit,
  });

  final String label;
  final String value;
  final String unit;
}

/// The telemetry strip: equal columns separated by hairlines, each carrying a
/// label, a measured value and its unit.
///
/// Runs edge to edge in the prototype, so the sheet gives this row no
/// horizontal padding of its own.
///
/// Only cells the caller actually has data for are passed in — the grid never
/// pads itself out with placeholder readings.
class MapTelemetryGrid extends StatelessWidget {
  const MapTelemetryGrid({super.key, required this.cells});

  final List<MapTelemetryCell> cells;

  @override
  Widget build(BuildContext context) {
    if (cells.isEmpty) return const SizedBox.shrink();
    final t = RiskMapTheme.of(context);

    return ColoredBox(
      color: t.hair,
      // The hairline separators are full-height gaps between stretched cells,
      // which needs the row's height resolved before its children lay out.
      child: IntrinsicHeight(
        child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < cells.length; i++) ...[
            if (i > 0) const SizedBox(width: 1),
            Expanded(
              child: Container(
                color: t.sheetCell,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cells[i].label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mapMono(
                        context,
                        size: 8.5,
                        em: 0.14,
                        color: t.ink2,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      cells[i].value,
                      maxLines: 1,
                      style: mapMono(context, size: 16, color: t.ink),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      cells[i].unit,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mapMono(context, size: 9, color: t.ink2),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
        ),
      ),
    );
  }
}

/// The "WHY THIS RISK" bar strip.
///
/// Heights are a deterministic function of the estimate's **own stored feature
/// values** (AQI, temperature, humidity) using the prototype's exact ramp —
/// it visualises the readings already shown above it and asserts no causal
/// claim of its own. With no readings it renders the flat uncertain strip.
class MapWhyBars extends StatelessWidget {
  const MapWhyBars({super.key, required this.drivers, required this.color});

  /// Normalised driver values, or empty for the uncertain strip.
  final List<double> drivers;
  final Color color;

  static const int _count = 24;

  @override
  Widget build(BuildContext context) {
    final flat = drivers.isEmpty;

    return SizedBox(
      height: 26,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < _count; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Expanded(
              child: Container(
                height: flat ? 2 : _heightFor(i),
                decoration: BoxDecoration(
                  color: color.withValues(
                    alpha: flat ? 0.5 : 0.32 + (i % 8) * 0.08,
                  ),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  double _heightFor(int i) {
    final v = drivers[(i ~/ 8).clamp(0, drivers.length - 1)];
    final shaped = 4 + v * 20 * (0.72 + 0.28 * math.sin(i * 1.7));
    return math.max(3.0, shaped.roundToDouble());
  }
}

class _SwatchPainter extends CustomPainter {
  const _SwatchPainter({
    required this.fill,
    required this.border,
    required this.dashed,
  });

  final Color fill;
  final Color border;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
      const Radius.circular(3),
    );
    if (fill.a > 0) {
      canvas.drawRRect(rect, Paint()..color = fill);
    }
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = border;

    if (!dashed) {
      canvas.drawRRect(rect, stroke);
      return;
    }
    // Flutter has no dashed border, so the uncertain swatch is walked out.
    final path = Path()..addRRect(rect);
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final end = (d + 3).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(d, end), stroke);
        d = end + 3;
      }
    }
  }

  @override
  bool shouldRepaint(_SwatchPainter old) =>
      old.fill != fill || old.border != border || old.dashed != dashed;
}
