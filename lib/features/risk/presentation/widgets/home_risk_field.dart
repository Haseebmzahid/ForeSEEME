import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/core/widgets/app_skeleton.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/risk/domain/constants/city_coordinates.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_override.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/trend_direction.dart';
import 'package:fyp_foreseeme/features/risk/domain/services/risk_staleness.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_override_provider.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_field.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_override_notice.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_visuals.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/staleness_indicator.dart';

/// Home's hero: the [RiskField] with its environmental instrumentation.
///
/// Bound live to [currentCityRiskProvider] (ADR-001 — the app reads risk from
/// `riskEstimates` only) and renders every state the provider can be in:
/// loading, data, operator override, empty and error. Every value on this
/// surface is read from the stored estimate or an existing domain service —
/// nothing is derived to fill a slot, and a channel with no stored value is
/// omitted rather than shown as zero.
///
/// This supersedes `RiskCard` as Home's hero. Both read the same providers and
/// hold the same contracts (override precedence, staleness, the low-confidence
/// treatment); `RiskCard` is left in place, still compiling and still covered by
/// `risk_card_test.dart`, but no screen renders it any more — removing it is a
/// separate decision, not part of this design pass.
class HomeRiskField extends ConsumerWidget {
  const HomeRiskField({super.key, this.onTap});

  /// Opens the full risk detail. Applied to the surface's own semantics node —
  /// the one that carries the readings — so a screen reader announces the
  /// values and the action together rather than as two separate nodes.
  ///
  /// Deliberately not applied to the error state, where `Retry` is the action.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final riskAsync = ref.watch(currentCityRiskProvider);
    // An active operator override transparently supersedes the model estimate
    // here, exactly as it does on the RiskCard.
    final override = ref.watch(currentCityOverrideProvider).asData?.value;

    return riskAsync.when(
      loading: () => const _FieldSkeleton(),
      error: (_, _) => override != null
          ? _OverrideField(riskOverride: override, onTap: onTap)
          : _UnavailableField(
              headline: "Couldn't load risk",
              body:
                  'You may be offline. Pull the latest when your connection '
                  'is back.',
              onRetry: () {
                ref.invalidate(userCityProvider);
                ref.invalidate(currentCityRiskProvider);
              },
            ),
      data: (estimate) {
        if (override != null) {
          return _OverrideField(riskOverride: override, onTap: onTap);
        }
        if (estimate == null) {
          final city = ref.watch(userCityProvider).value;
          final where = (city != null && city.isNotEmpty) ? city : 'your city';
          return _UnavailableField(
            city: city,
            headline: 'No estimate yet',
            body:
                "We don't have an environmental risk estimate for $where this "
                'week. New estimates arrive weekly — check back soon.',
          );
        }
        return _EstimateField(estimate: estimate, onTap: onTap);
      },
    );
  }
}

/// Wraps a risk surface as a single accessible, pressable node: the semantics
/// label describes the readings AND the action, and the press animation matches
/// every other tappable card on Home.
class _Tappable extends StatelessWidget {
  const _Tappable({
    required this.label,
    required this.onTap,
    required this.child,
  });

  final String label;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: onTap != null,
      label: onTap == null ? label : '$label Opens risk details.',
      onTap: onTap,
      child: ExcludeSemantics(
        child: PressableScale(onTap: onTap, child: child),
      ),
    );
  }
}

// ── Data state ───────────────────────────────────────────────────────────────

class _EstimateField extends ConsumerWidget {
  const _EstimateField({required this.estimate, this.onTap});

  final RiskEstimateModel estimate;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = RiskVisuals.resolve(
      context,
      estimate.riskLevel,
      lowConfidence: estimate.lowConfidence,
    );
    final stale = isRiskStale(estimate.generatedAt);
    final confidencePct = (estimate.confidence * 100).round();
    final trend = ref.watch(riskTrendProvider).asData?.value;

    final field = RiskFieldState.forEstimate(
      level: estimate.riskLevel,
      confidence: estimate.confidence,
      lowConfidence: estimate.lowConfidence,
      stale: stale,
    );

    return _Tappable(
      onTap: onTap,
      label:
          '${estimate.city} regional risk: ${appearance.headline}, '
          '${estimate.disease}. $confidencePct percent confidence. '
          'Air quality index ${estimate.aqi.round()}, '
          'temperature ${estimate.temperature.round()} degrees Celsius, '
          '${estimate.humidity.round()} percent humidity. '
          'Updated ${riskAgeLabel(estimate.generatedAt)}.',
      child: _FieldShell(
        city: estimate.city,
        state: field,
        tint: appearance.color,
        readout: _RiskReadout(
          appearance: appearance,
          caption: _fieldCaption(field.tone),
        ),
        channels: [
          _Channel(label: 'AQI', value: estimate.aqi.round().toString()),
          _Channel(label: 'TEMP', value: '${estimate.temperature.round()}°'),
          _Channel(
            label: 'HUMIDITY',
            value: estimate.humidity.round().toString(),
            unit: '%',
          ),
          // The design's fourth channel is rainfall, which the risk contract
          // does not carry. Rather than fabricate a reading, the slot shows
          // the estimate's own subject — a real, stored value.
          _Channel(label: 'DISEASE', value: estimate.disease),
        ],
        telemetry: [
          _Telemetry(label: 'CONFIDENCE', value: '$confidencePct%'),
          _Telemetry(
            label: 'UPDATED',
            value: riskAgeLabel(estimate.generatedAt),
            emphasis: stale ? _TelemetryEmphasis.caution : null,
          ),
          _Telemetry(
            label: 'TREND',
            value: _trendReadout(trend),
            emphasis: _TelemetryEmphasis.tint,
          ),
        ],
        footer: RiskStalenessNotice(generatedAt: estimate.generatedAt),
      ),
    );
  }
}

// ── Operator override ────────────────────────────────────────────────────────

class _OverrideField extends StatelessWidget {
  const _OverrideField({required this.riskOverride, this.onTap});

  final RiskOverride riskOverride;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final appearance = RiskVisuals.resolve(context, riskOverride.riskLevel);

    // An operator-set level carries no model confidence, so the field is drawn
    // at full definition and its confidence channel reads as absent, never 100%.
    final field = RiskFieldState.forEstimate(
      level: riskOverride.riskLevel,
      confidence: 1.0,
    );

    return _Tappable(
      onTap: onTap,
      label:
          'Operator-set risk for ${riskOverride.city}: '
          '${appearance.headline}, ${riskOverride.disease}. '
          'Reason: ${riskOverride.reason}',
      child: _FieldShell(
        city: riskOverride.city,
        state: field,
        tint: appearance.color,
        trailing: const OverrideBadge(),
        readout: _RiskReadout(appearance: appearance, caption: 'SET MANUALLY'),
        channels: [_Channel(label: 'DISEASE', value: riskOverride.disease)],
        telemetry: [
          const _Telemetry(label: 'CONFIDENCE', value: '—'),
          const _Telemetry(label: 'SOURCE', value: 'operator'),
        ],
        footer: Padding(
          padding: const EdgeInsets.only(top: ForeSeeMeSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.notes_rounded, size: 13, color: palette.textTertiary),
              const SizedBox(width: ForeSeeMeSpacing.sm),
              Expanded(
                child: Text(
                  riskOverride.reason,
                  style: text.bodySmall?.copyWith(color: palette.textTertiary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Empty / error ────────────────────────────────────────────────────────────

/// The explicit gap. A flat dashed lattice with no tint and no crest — a
/// different kind of object from a low reading, so an absent estimate can never
/// be mistaken for a reassuring one.
class _UnavailableField extends StatelessWidget {
  const _UnavailableField({
    required this.headline,
    required this.body,
    this.city,
    this.onRetry,
  });

  final String headline;
  final String body;
  final String? city;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final tint = palette.onSurfaceVariant;

    // Deliberately NOT wrapped in a merged/excluded semantics node: this state
    // can contain a `Retry` control, and collapsing the subtree would take that
    // action away from a screen reader. Its content is plain text, so it reads
    // correctly as-is.
    return _FieldShell(
      city: city,
      state: RiskFieldState.unavailable,
      tint: tint,
      readout: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('REGIONAL RISK', style: context.fsmTelemetry.channel),
          const SizedBox(height: ForeSeeMeSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.help_outline_rounded, color: tint, size: 22),
              const SizedBox(width: ForeSeeMeSpacing.sm),
              Text(
                headline,
                style: text.displaySmall?.copyWith(fontSize: 24, color: tint),
              ),
            ],
          ),
          const SizedBox(height: ForeSeeMeSpacing.sm),
          Text('NO ESTIMATE AVAILABLE', style: context.fsmTelemetry.caption),
        ],
      ),
      channels: const [],
      telemetry: const [
        _Telemetry(label: 'CONFIDENCE', value: '—'),
        _Telemetry(label: 'UPDATED', value: '—'),
        _Telemetry(label: 'TREND', value: '—'),
      ],
      footer: Padding(
        padding: const EdgeInsets.only(top: ForeSeeMeSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              body,
              style: text.bodyMedium?.copyWith(color: palette.textSecondary),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: ForeSeeMeSpacing.md),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(
                    foregroundColor: palette.primary,
                    // Keeps the control at the 48dp minimum touch target.
                    padding: const EdgeInsets.symmetric(
                      horizontal: ForeSeeMeSpacing.lg,
                      vertical: ForeSeeMeSpacing.md,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(ForeSeeMeRadius.xs),
                      side: BorderSide(
                        color: palette.primary.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Retry'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Loading ──────────────────────────────────────────────────────────────────

/// Mirrors the loaded layout's silhouette — headline block, channel grid and
/// telemetry footer — so the surface does not reflow when data lands.
class _FieldSkeleton extends StatelessWidget {
  const _FieldSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(ForeSeeMeSpacing.xl),
      decoration: ForeSeeMeSurface.card(context, radius: ForeSeeMeRadius.xl),
      child: const AppSkeleton(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SkeletonBar(width: 160, height: 10),
            SizedBox(height: 28),
            Center(child: SkeletonBar(width: 190, height: 30)),
            SizedBox(height: 12),
            Center(child: SkeletonBar(width: 110, height: 10)),
            SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SkeletonBar(width: 56, height: 22),
                SkeletonBar(width: 56, height: 22),
              ],
            ),
            SizedBox(height: 44),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SkeletonBar(width: 56, height: 22),
                SkeletonBar(width: 72, height: 22),
              ],
            ),
            SizedBox(height: 40),
            SkeletonBar(width: double.infinity, height: 34),
          ],
        ),
      ),
    );
  }
}

// ── Shell ────────────────────────────────────────────────────────────────────

/// The instrument housing: provenance strip, the field, and the readouts
/// anchored to it.
class _FieldShell extends StatelessWidget {
  const _FieldShell({
    required this.state,
    required this.tint,
    required this.readout,
    required this.channels,
    required this.telemetry,
    this.city,
    this.trailing,
    this.footer,
  });

  final RiskFieldState state;
  final Color tint;
  final Widget readout;
  final List<_Channel> channels;
  final List<_Telemetry> telemetry;
  final String? city;
  final Widget? trailing;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final mono = context.fsmTelemetry;
    final coordinate = city == null ? null : kCityCoordinates[city];

    return Container(
      width: double.infinity,
      decoration: ForeSeeMeSurface.card(
        context,
        radius: ForeSeeMeRadius.xl,
        borderColor: tint.withValues(alpha: 0.22),
        shadow: context.fsmColors.shadows.strong,
      ),
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.fromLTRB(
        ForeSeeMeSpacing.xl,
        ForeSeeMeSpacing.lg,
        ForeSeeMeSpacing.xl,
        ForeSeeMeSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Provenance strip — where this reading is from, on a hairline rule.
          Padding(
            padding: const EdgeInsets.only(bottom: ForeSeeMeSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    city == null
                        ? 'REGIONAL FIELD'
                        : '${city!.toUpperCase()} · REGIONAL FIELD',
                    style: mono.strip,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ?trailing,
                if (trailing == null && coordinate != null)
                  Text(
                    _formatCoordinate(coordinate),
                    style: mono.strip,
                    maxLines: 1,
                  ),
              ],
            ),
          ),
          Container(height: 1, color: palette.outlineVariant),

          LayoutBuilder(
            builder: (context, constraints) {
              // Proportional to width so the field keeps the prototype's
              // aspect on a 360dp phone and a 412dp one alike, bounded so it
              // never dominates a small screen or floats on a large one.
              final target = (constraints.maxWidth * 0.95).clamp(260.0, 380.0);
              return Stack(
                children: [
                  // Decorative: every value it encodes is stated in text by the
                  // readouts, and the shell announces them as one label.
                  Positioned.fill(
                    child: RiskField(state: state, tint: tint),
                  ),
                  ConstrainedBox(
                    constraints: BoxConstraints(minHeight: target),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                            top: ForeSeeMeSpacing.xxl,
                          ),
                          child: readout,
                        ),
                        if (channels.isNotEmpty)
                          _ChannelGrid(channels: channels),
                        _TelemetryFooter(items: telemetry, tint: tint),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          ?footer,
        ],
      ),
    );
  }
}

// ── Readout ──────────────────────────────────────────────────────────────────

class _RiskReadout extends StatelessWidget {
  const _RiskReadout({required this.appearance, required this.caption});

  final RiskAppearance appearance;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final mono = context.fsmTelemetry;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('REGIONAL RISK', style: mono.channel),
        const SizedBox(height: ForeSeeMeSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(appearance.icon, color: appearance.color, size: 24),
            const SizedBox(width: ForeSeeMeSpacing.md),
            Flexible(
              child: Text(
                appearance.headline,
                style: context.fsmText.displaySmall?.copyWith(
                  fontSize: 30,
                  color: appearance.color,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: ForeSeeMeSpacing.sm),
        Text(caption, style: mono.caption, textAlign: TextAlign.center),
      ],
    );
  }
}

// ── Environmental channels ───────────────────────────────────────────────────

/// One measured channel: its tracked label, the stored value, and an optional
/// unit. Only channels with a real stored value are ever constructed.
class _Channel {
  const _Channel({required this.label, required this.value, this.unit});

  final String label;
  final String value;
  final String? unit;
}

/// Channels anchored to the field they describe — alternating edges at two
/// elevations, mirroring the instrument layout of the prototype.
class _ChannelGrid extends StatelessWidget {
  const _ChannelGrid({required this.channels});

  final List<_Channel> channels;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < channels.length; i += 2) {
      final left = channels[i];
      final right = i + 1 < channels.length ? channels[i + 1] : null;
      if (rows.isNotEmpty) {
        rows.add(const SizedBox(height: ForeSeeMeSpacing.xxl));
      }
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _ChannelReadout(channel: left)),
            if (right != null)
              Expanded(child: _ChannelReadout(channel: right, alignEnd: true)),
          ],
        ),
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }
}

class _ChannelReadout extends StatelessWidget {
  const _ChannelReadout({required this.channel, this.alignEnd = false});

  final _Channel channel;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final mono = context.fsmTelemetry;
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(channel.label, style: mono.channel, maxLines: 1),
        const SizedBox(height: ForeSeeMeSpacing.xs),
        Text.rich(
          TextSpan(
            text: channel.value,
            style: mono.readout,
            children: channel.unit == null
                ? null
                : [TextSpan(text: channel.unit, style: mono.unit)],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: alignEnd ? TextAlign.right : TextAlign.left,
        ),
      ],
    );
  }
}

// ── Telemetry footer ─────────────────────────────────────────────────────────

enum _TelemetryEmphasis { tint, caution }

class _Telemetry {
  const _Telemetry({required this.label, required this.value, this.emphasis});

  final String label;
  final String value;
  final _TelemetryEmphasis? emphasis;
}

class _TelemetryFooter extends StatelessWidget {
  const _TelemetryFooter({required this.items, required this.tint});

  final List<_Telemetry> items;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final mono = context.fsmTelemetry;

    Color? colorFor(_TelemetryEmphasis? emphasis) => switch (emphasis) {
      _TelemetryEmphasis.tint => tint,
      _TelemetryEmphasis.caution => context.fsmColors.warning,
      null => null,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(height: 1, color: palette.outlineVariant),
        const SizedBox(height: ForeSeeMeSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: Container(
                  padding: EdgeInsets.only(
                    left: i == 0 ? 0 : ForeSeeMeSpacing.md,
                  ),
                  decoration: i == 0
                      ? null
                      : BoxDecoration(
                          border: Border(
                            left: BorderSide(color: palette.outlineVariant),
                          ),
                        ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(items[i].label, style: mono.channel, maxLines: 1),
                      const SizedBox(height: ForeSeeMeSpacing.xs),
                      Text(
                        items[i].value,
                        style: mono.value.copyWith(
                          color: colorFor(items[i].emphasis),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ── Vocabulary ───────────────────────────────────────────────────────────────

/// Describes the field's own visual character. Purely a restatement of the tone
/// already shown as a label and a glyph — it adds no claim of its own.
String _fieldCaption(RiskFieldTone tone) => switch (tone) {
  RiskFieldTone.low => 'STABLE FIELD',
  RiskFieldTone.moderate => 'ACTIVE FIELD',
  RiskFieldTone.high => 'ELEVATED FIELD',
  RiskFieldTone.unknown => 'NOT ENOUGH CERTAINTY',
};

/// Telemetry form of the trend. Uses the same vocabulary as the shared
/// `TrendBadge` so the two can never drift, with a directional glyph so it
/// survives greyscale, and an explicit dash — never a guessed arrow — when
/// history is insufficient.
String _trendReadout(TrendDirection? direction) => switch (direction) {
  TrendDirection.rising => '↑ RISING',
  TrendDirection.stable => '→ STABLE',
  TrendDirection.falling => '↓ FALLING',
  TrendDirection.insufficient => '— INSUFFICIENT',
  null => '—',
};

/// Formats a city centroid as a coordinate readout, e.g. `31.550°N 74.344°E`.
/// Pakistan's cities are all north/east, but the hemisphere is derived from the
/// value rather than assumed.
String _formatCoordinate(CityCoordinate c) {
  final ns = c.lat >= 0 ? 'N' : 'S';
  final ew = c.lon >= 0 ? 'E' : 'W';
  return '${c.lat.abs().toStringAsFixed(3)}°$ns '
      '${c.lon.abs().toStringAsFixed(3)}°$ew';
}
