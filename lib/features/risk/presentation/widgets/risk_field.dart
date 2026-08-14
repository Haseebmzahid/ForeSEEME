import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:fyp_foreseeme/core/theme/a11y.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_visuals.dart';

/// The **Risk Field** — ForeSeeMe's signature visual: regional risk drawn as a
/// stacked field of atmospheric isolines seen in perspective.
///
/// The field encodes state on **four independent channels**, so a level is never
/// carried by colour alone (the same accessibility contract [RiskVisuals] holds):
///
///  * **crest elevation** — magnitude of the estimate;
///  * **isoline count + turbulence** — instability of the field;
///  * **thermal tint** — the semantic level, resolved from the active theme;
///  * **glyph + written label** — supplied by the surrounding readout.
///
/// A fifth, quieter channel carries *epistemic* state: model confidence drives
/// line **definition** (see [RiskFieldState.definition]), and an estimate that is
/// unavailable or too unreliable to classify renders as a flat **dashed lattice**
/// with no tint and no crest — visually a different kind of object from a low
/// reading, not a quieter version of it.
///
/// Every visual property is a deterministic function of application state and
/// the animation phase. Nothing here is random, and nothing here invents a value.
///
/// Rendering is a single [CustomPainter] over paths, gradients and transforms —
/// no images, no SVG, no additional package.

// ── State encoding ───────────────────────────────────────────────────────────

/// The semantic tone of a field. [unknown] is a first-class value, not a
/// degenerate [low] — it renders as a different object entirely.
enum RiskFieldTone { low, moderate, high, unknown }

/// The full, deterministic visual encoding of a risk state.
///
/// Pure data (no Flutter dependency beyond [immutable]) so the mapping from
/// application state to visual channels is directly unit-testable without
/// pumping a widget.
@immutable
class RiskFieldState {
  /// Semantic tone — selects the tint and the field's character.
  final RiskFieldTone tone;

  /// Number of isolines drawn front-to-back.
  final int isolines;

  /// Crest elevation, as a fraction of the field's height budget.
  final double elevation;

  /// Isoline turbulence — how strongly the wave term perturbs each line.
  final double turbulence;

  /// Whether isolines are drawn as a dashed lattice (the "no estimate" object).
  final bool dashed;

  /// Line definition, `0.35`–`1.0`, driven by model confidence. A less certain
  /// estimate is drawn less sharply; it is never drawn as a *different* level.
  final double definition;

  /// Whether the estimate is past its freshness threshold. A muted field drops
  /// its ambient energy so a stale reading never looks live.
  final bool muted;

  const RiskFieldState({
    required this.tone,
    required this.isolines,
    required this.elevation,
    required this.turbulence,
    required this.definition,
    this.dashed = false,
    this.muted = false,
  });

  /// Confidence `[0,1]` → definition `[0.35, 1.0]`. Kept off zero so a
  /// low-confidence field is still legible rather than invisible.
  static double definitionFor(double confidence) =>
      0.35 + confidence.clamp(0.0, 1.0) * 0.65;

  /// The field for a real estimate.
  ///
  /// [lowConfidence] wins over [level]: when the backend flags the
  /// classification as unreliable, the field renders as [unavailable]'s lattice
  /// rather than asserting a crest the model does not support. This mirrors
  /// [RiskVisuals.of], so the field and the headline can never disagree.
  factory RiskFieldState.forEstimate({
    required RiskLevel level,
    required double confidence,
    bool lowConfidence = false,
    bool stale = false,
  }) {
    if (lowConfidence) {
      return RiskFieldState(
        tone: RiskFieldTone.unknown,
        isolines: 12,
        elevation: 0.10,
        turbulence: 0.18,
        dashed: true,
        definition: definitionFor(confidence),
        muted: stale,
      );
    }
    final definition = definitionFor(confidence);
    return switch (level) {
      RiskLevel.low => RiskFieldState(
        tone: RiskFieldTone.low,
        isolines: 14,
        elevation: 0.30,
        turbulence: 0.34,
        definition: definition,
        muted: stale,
      ),
      RiskLevel.medium => RiskFieldState(
        tone: RiskFieldTone.moderate,
        isolines: 16,
        elevation: 0.60,
        turbulence: 0.80,
        definition: definition,
        muted: stale,
      ),
      RiskLevel.high => RiskFieldState(
        tone: RiskFieldTone.high,
        isolines: 19,
        elevation: 0.96,
        turbulence: 1.30,
        definition: definition,
        muted: stale,
      ),
    };
  }

  /// The explicit gap: no estimate at all (none stored yet, or the read failed).
  /// A flat dashed lattice with no crest and no tint.
  static const RiskFieldState unavailable = RiskFieldState(
    tone: RiskFieldTone.unknown,
    isolines: 12,
    elevation: 0.10,
    turbulence: 0.18,
    dashed: true,
    definition: 0.35,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RiskFieldState &&
          other.tone == tone &&
          other.isolines == isolines &&
          other.elevation == elevation &&
          other.turbulence == turbulence &&
          other.dashed == dashed &&
          other.definition == definition &&
          other.muted == muted;

  @override
  int get hashCode => Object.hash(
    tone,
    isolines,
    elevation,
    turbulence,
    dashed,
    definition,
    muted,
  );
}

// ── Widget ───────────────────────────────────────────────────────────────────

/// Paints a [RiskFieldState] with a slow ambient phase drift.
///
/// Motion is a single low-frequency drift on the wave term — it communicates
/// "this is a live field", nothing more. It never pulses for attention and never
/// escalates with risk.
///
/// The drift stops entirely in two cases, and the ticker is not merely slowed
/// but never started:
///
///  * under `prefers-reduced-motion`;
///  * on the dashed lattice — an absent or unreliable estimate is **static**,
///    because there is no live field to convey. Motion is one more channel that
///    must not imply data the app does not have.
class RiskField extends StatefulWidget {
  const RiskField({super.key, required this.state, required this.tint});

  /// The deterministic visual encoding to render.
  final RiskFieldState state;

  /// The thermal tint — resolved by the caller from the active theme (via
  /// [RiskVisuals.colorOf]) so the field tracks light/dark like every other
  /// risk surface.
  final Color tint;

  @override
  State<RiskField> createState() => _RiskFieldState();
}

class _RiskFieldState extends State<RiskField>
    with SingleTickerProviderStateMixin {
  /// ~24 fps. The field's motion carries no detail that a higher rate would
  /// reveal, and the painter's per-frame path build is the expensive part.
  static const Duration _frame = Duration(milliseconds: 42);

  /// Phase advance per frame — a drift of roughly 0.02 Hz on the wave term.
  static const double _step = 0.028;

  /// Starting phase for the still (reduced-motion) render, chosen so the field
  /// is fully formed rather than caught at a flat point of the wave.
  static const double _restPhase = 1.4;

  Ticker? _ticker;
  double _phase = _restPhase;
  Duration _last = Duration.zero;
  bool _motionEnabled = false;

  /// The drift runs only for a live, classified field that the user has not
  /// asked to hold still.
  bool get _shouldDrift =>
      !widget.state.dashed && !AppMotion.reduceMotion(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion(_shouldDrift);
  }

  @override
  void didUpdateWidget(RiskField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The field can switch between a live estimate and the lattice in place
    // (a refresh that comes back empty), so motion is re-evaluated on update.
    _syncMotion(_shouldDrift);
  }

  void _syncMotion(bool enabled) {
    if (enabled == _motionEnabled) return;
    _motionEnabled = enabled;
    if (enabled) {
      _ticker ??= createTicker(_onTick);
      _ticker!.start();
    } else {
      _ticker?.stop();
    }
  }

  void _onTick(Duration elapsed) {
    if (elapsed - _last < _frame) return;
    _last = elapsed;
    setState(() => _phase += _step);
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;

    // The opaque colour actually behind the field, used for depth occlusion and
    // the horizon fog. Composited so it is correct on the translucent card fill
    // in both themes and under the reduced-transparency fallback.
    final backdrop = A11y.compositeOver(
      ForeSeeMeSurface.fill(context),
      palette.background,
    );

    // Isolating the animation keeps the repaint off the readouts stacked above.
    return RepaintBoundary(
      child: CustomPaint(
        painter: _RiskFieldPainter(
          state: widget.state,
          phase: _phase,
          tint: widget.tint,
          line: palette.onSurface,
          backdrop: backdrop,
          peakLabelStyle: context.fsmTelemetry.channel.copyWith(fontSize: 8),
          textScaler: MediaQuery.textScalerOf(context),
        ),
        isComplex: true,
        willChange: _motionEnabled,
        size: Size.infinite,
      ),
    );
  }
}

// ── Painter ──────────────────────────────────────────────────────────────────

/// One sampled isoline: its points, the un-elevated baseline it sits on, its
/// depth `t` (0 = furthest, 1 = nearest) and its strongest sample.
class _Isoline {
  const _Isoline(this.points, this.baseY, this.t, this.peak);

  final List<Offset> points;
  final double baseY;
  final double t;
  final double peak;
}

class _RiskFieldPainter extends CustomPainter {
  _RiskFieldPainter({
    required this.state,
    required this.phase,
    required this.tint,
    required this.line,
    required this.backdrop,
    required this.peakLabelStyle,
    required this.textScaler,
  });

  final RiskFieldState state;
  final double phase;
  final Color tint;
  final Color line;
  final Color backdrop;
  final TextStyle peakLabelStyle;
  final TextScaler textScaler;

  /// Samples per isoline. Fixed, so cost scales only with [RiskFieldState.isolines].
  static const int _samples = 54;

  /// Columns where a meridian is drawn across the isolines.
  static const List<double> _meridians = [0.14, 0.28, 0.42, 0.58, 0.72, 0.86];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    final rows = _buildGrid(w, h);
    // A slow breath on the ambient layers; barely-there on the dashed lattice.
    final breath = 1 + math.sin(phase * 0.42) * (state.dashed ? 0.01 : 0.045);
    // A stale field keeps its shape but loses its ambient energy.
    final energy = state.muted ? 0.45 : 1.0;

    _paintAtmosphere(canvas, w, h, breath, energy);

    // Parallax: the mesh drifts fractionally against the fixed atmosphere,
    // which reads as depth without moving any measured value.
    canvas.save();
    canvas.translate(
      math.sin(phase * 0.31) * 3.2,
      math.cos(phase * 0.24) * 2.0,
    );
    _paintIsolines(canvas, rows, h);
    _paintMeridians(canvas, rows);
    if (!state.dashed) _paintApex(canvas, rows);
    canvas.restore();
  }

  // ── Geometry ───────────────────────────────────────────────────────────────

  /// Builds the perspective grid.
  ///
  /// Each isoline is a Gaussian envelope (a single central crest) perturbed by a
  /// two-term wave; rows are spaced non-linearly toward the viewer and widen as
  /// they approach, which is what produces the perspective read.
  List<_Isoline> _buildGrid(double w, double h) {
    final rows = <_Isoline>[];
    final count = state.isolines;
    final yBack = h * 0.30;
    final yFront = h * 0.90;

    for (var i = 0; i < count; i++) {
      final t = count > 1 ? i / (count - 1) : 1.0;
      final rowWidth = w * (0.48 + 0.52 * t);
      final x0 = (w - rowWidth) / 2;
      final baseY = yBack + (yFront - yBack) * math.pow(t, 1.45);
      final rowAmplitude = state.elevation * h * 0.30 * (0.38 + 0.62 * t);
      // Depth envelope — the crest lives in the middle distance, so the nearest
      // ridges stay readable as foreground rather than swallowing the peak.
      final depthEnvelope = math.exp(-math.pow((t - 0.60) / 0.46, 2));

      final points = <Offset>[];
      var peak = 0.0;
      for (var j = 0; j <= _samples; j++) {
        final u = j / _samples;
        final x = x0 + rowWidth * u;
        final envelope = math.exp(-math.pow((u - 0.5) / 0.29, 2));
        final wave =
            math.sin(u * 7.4 + phase + i * 0.55) * 0.34 +
            math.sin(u * 13.7 - phase * 0.8 + i * 0.28) * 0.16;
        final e = math.max(
          0.0,
          envelope * depthEnvelope * (1 + wave * state.turbulence),
        );
        if (e > peak) peak = e;
        points.add(Offset(x, baseY - rowAmplitude * e));
      }
      rows.add(_Isoline(points, baseY, t, peak));
    }
    return rows;
  }

  // ── Layers ─────────────────────────────────────────────────────────────────

  /// Ambient wash, thermal glow, core, horizon rule, fog and ground shadow —
  /// everything behind the mesh.
  void _paintAtmosphere(
    Canvas canvas,
    double w,
    double h,
    double breath,
    double energy,
  ) {
    final flat = state.dashed;

    _radialWash(
      canvas,
      Offset(w / 2, h * 0.58),
      w * 0.62 * breath,
      h * 0.38 * breath,
      tint.withValues(alpha: (flat ? 0.05 : 0.15) * energy),
    );
    _radialWash(
      canvas,
      Offset(w / 2, h * 0.54),
      w * 0.42 * breath,
      h * 0.28 * breath,
      tint.withValues(alpha: (flat ? 0.03 : 0.22) * energy),
    );
    if (!flat) {
      _radialWash(
        canvas,
        Offset(w / 2, h * 0.50),
        w * 0.17 * breath,
        h * 0.10 * breath,
        tint.withValues(alpha: 0.28 * energy),
      );
    }

    // Horizon hairline — the datum the field is measured against.
    canvas.drawLine(
      Offset(w * 0.14, h * 0.30),
      Offset(w * 0.86, h * 0.30),
      Paint()
        ..color = line.withValues(alpha: 0.10)
        ..strokeWidth = 1,
    );

    // Fog above the horizon, so back isolines dissolve rather than being clipped.
    final fogRect = Rect.fromLTWH(0, 0, w, h * 0.34);
    canvas.drawRect(
      fogRect,
      Paint()
        ..shader = ui.Gradient.linear(fogRect.topCenter, fogRect.bottomCenter, [
          backdrop.withValues(alpha: 0.92),
          backdrop.withValues(alpha: 0.0),
        ]),
    );

    // Contact shadow under the nearest ridges.
    _radialWash(
      canvas,
      Offset(w / 2, h * 0.955),
      w * 0.40,
      h * 0.055,
      const Color(0xFF000000).withValues(alpha: 0.35 * energy),
    );
  }

  /// A centre-bright radial wash on an elliptical footprint.
  void _radialWash(
    Canvas canvas,
    Offset center,
    double rx,
    double ry,
    Color color,
  ) {
    if (rx <= 0 || ry <= 0 || color.a == 0) return;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(1.0, ry / rx);
    canvas.drawCircle(
      Offset.zero,
      rx,
      Paint()
        ..shader = ui.Gradient.radial(Offset.zero, rx, [
          color,
          color.withValues(alpha: 0.0),
        ]),
    );
    canvas.restore();
  }

  /// The isolines themselves: an occluding fill per row, the base stroke, and —
  /// on a tinted field — the thermal hot-line and the travelling sweep.
  void _paintIsolines(Canvas canvas, List<_Isoline> rows, double h) {
    // Sweep position, wrapped over a range wider than the row so the highlight
    // spends part of its cycle off-screen (a pass, not a pulse).
    final sweep = (phase * 0.055) % 1.7 - 0.35;

    for (final row in rows) {
      final path = _lineThrough(row.points);

      // Depth occlusion: each row fills to the bottom in the backdrop colour,
      // hiding the rows behind it. This is what makes the stack read as terrain.
      final fill = Path.from(path)
        ..lineTo(row.points.last.dx, h + 4)
        ..lineTo(row.points.first.dx, h + 4)
        ..close();
      canvas.drawPath(
        fill,
        Paint()..color = backdrop.withValues(alpha: 0.72 + 0.22 * row.t),
      );

      final basePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.round
        ..color = line.withValues(
          alpha: (0.09 + 0.28 * row.t) * state.definition,
        );
      canvas.drawPath(state.dashed ? _dash(path, 3, 7) : path, basePaint);

      if (state.dashed || row.peak <= 0.12) continue;

      // Thermal hot-line: the tint concentrated where the crest actually is.
      final x0 = row.points.first.dx;
      final x1 = row.points.last.dx;
      final hot = (0.16 + 0.62 * math.min(1.0, row.peak)) * state.definition;
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.25
          ..shader = ui.Gradient.linear(
            Offset(x0, 0),
            Offset(x1, 0),
            [
              tint.withValues(alpha: 0.0),
              tint.withValues(alpha: 0.95 * hot),
              tint.withValues(alpha: 0.0),
            ],
            const [0.0, 0.5, 1.0],
          ),
      );

      // Travelling sweep — only on the front half, where the design's own
      // opacity ramp makes it visible at all. The highlight band is positioned
      // by moving the gradient's endpoints rather than its stops, so it can
      // travel cleanly off both edges (the default clamp tile mode extends the
      // transparent ends).
      if (row.t <= 0.3) continue;
      final rowWidth = x1 - x0;
      final band = rowWidth * 0.16;
      if (band <= 0) continue;
      final centre = x0 + rowWidth * sweep;
      final sweepAlpha = (0.20 + 0.45 * row.t) * state.definition;
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..shader = ui.Gradient.linear(
            Offset(centre - band, 0),
            Offset(centre + band, 0),
            [
              line.withValues(alpha: 0.0),
              line.withValues(alpha: 0.5 * sweepAlpha),
              line.withValues(alpha: 0.0),
            ],
            const [0.0, 0.5, 1.0],
          ),
      );
    }
  }

  /// Meridians running front-to-back through the stack, with a tip dot on the
  /// nearest row — the cross-hatch that makes the field read as a surface.
  void _paintMeridians(Canvas canvas, List<_Isoline> rows) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = line.withValues(alpha: 0.075 * state.definition);
    final dot = Paint()
      ..color = line.withValues(alpha: 0.28 * state.definition);

    for (final u in _meridians) {
      final j = (u * _samples).round();
      final points = [for (final row in rows) row.points[j]];
      canvas.drawPath(_lineThrough(points), paint);
      canvas.drawCircle(points.last, 1.2, dot);
    }
  }

  /// The apex marker: a dropline to the baseline, a slow ring, a dot and a
  /// `PEAK` label. Marks where the field is highest — a readout, not decoration.
  void _paintApex(Canvas canvas, List<_Isoline> rows) {
    Offset? apex;
    var apexBase = 0.0;
    for (final row in rows) {
      for (final p in row.points) {
        if (apex == null || p.dy < apex.dy) {
          apex = p;
          apexBase = row.baseY;
        }
      }
    }
    if (apex == null) return;

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = tint.withValues(alpha: 0.28);

    canvas.drawPath(
      _dash(
        Path()
          ..moveTo(apex.dx, apex.dy - 6)
          ..lineTo(apex.dx, apexBase),
        2,
        5,
      ),
      stroke,
    );
    canvas.drawCircle(
      apex,
      8 + math.sin(phase * 0.9) * 1.6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = tint.withValues(alpha: 0.22),
    );
    canvas.drawCircle(apex, 2.6, Paint()..color = tint);

    final label = TextPainter(
      text: TextSpan(
        text: 'PEAK',
        style: peakLabelStyle.copyWith(color: line.withValues(alpha: 0.55)),
      ),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout();
    label.paint(canvas, Offset(apex.dx + 13, apex.dy - label.height / 2));
  }

  // ── Path helpers ───────────────────────────────────────────────────────────

  static Path _lineThrough(List<Offset> points) {
    final path = Path();
    if (points.isEmpty) return path;
    path.moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    return path;
  }

  /// Flutter has no dashed stroke, so the dashed lattice is built by walking the
  /// path and extracting alternating segments.
  static Path _dash(Path source, double dash, double gap) {
    final result = Path();
    for (final metric in source.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + dash, metric.length);
        result.addPath(metric.extractPath(distance, end), Offset.zero);
        distance = end + gap;
      }
    }
    return result;
  }

  @override
  bool shouldRepaint(_RiskFieldPainter old) =>
      old.phase != phase ||
      old.state != state ||
      old.tint != tint ||
      old.line != line ||
      old.backdrop != backdrop;
}
