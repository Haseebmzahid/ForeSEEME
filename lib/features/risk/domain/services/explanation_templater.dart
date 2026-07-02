// Deterministic templating of a stored risk explanation into plain language.
//
// Framework-free (no `package:flutter`), mirroring `risk_driver_service.dart`:
// pure, reusable, unit-testable. It maps the backend's genuine, additive
// attributions (Sprint 5, Prompt 5) to sentences via FIXED templates — there is
// NO generative text and NO model here. It never recomputes, re-ranks, or
// reinterprets the attribution numbers: direction, magnitude, ordering, class
// names, confidence strength and values all come straight from the stored data
// (the backend is the single source of truth). The only transforms are cosmetic:
// mapping a feature key to a human label, choosing a fixed verb for a stored
// direction, and formatting a stored number for display.

import 'package:fyp_foreseeme/features/risk/domain/models/risk_attributions.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';

/// One driver rendered as plain language: a human [label], the stored
/// [direction] (for the widget's arrow icon), a formatted [valueText], and a
/// ready-to-render [sentence]. Non-diagnostic: sentences describe the *estimate*,
/// never the person's health.
class ExplanationDriver {
  final String label;
  final ContributionDirection direction;
  final String valueText;
  final String sentence;

  const ExplanationDriver({
    required this.label,
    required this.direction,
    required this.valueText,
    required this.sentence,
  });
}

/// A fully-templated, presentation-ready explanation. Holds only strings and the
/// stored [strength] enum (the widget maps that to an icon/label) — no framework
/// types, so it stays in the domain layer.
class ExplanationView {
  final String title;
  final String lead;
  final List<ExplanationDriver> drivers;
  final ConfidenceStrength strength;
  final String confidenceSentence;
  final String provenanceNote;

  const ExplanationView({
    required this.title,
    required this.lead,
    required this.drivers,
    required this.strength,
    required this.confidenceSentence,
    required this.provenanceNote,
  });
}

/// Turns a risk estimate's stored attributions into an [ExplanationView].
///
/// Returns `null` when the estimate carries no attributions (a pre-Sprint-5
/// document) — the UI then shows an "explanation unavailable" state rather than
/// inventing one.
class ExplanationTemplater {
  ExplanationTemplater._();

  static const String title = 'Why this estimate?';

  /// Build the templated view, or `null` if the estimate has no attributions.
  static ExplanationView? build(RiskEstimateModel estimate) {
    final attributions = estimate.attributions;
    if (attributions == null) return null;

    final drivers = attributions.topContributors
        .map(_driverLine)
        .toList(growable: false);

    return ExplanationView(
      title: title,
      lead:
          'The ${estimate.disease} risk estimate for ${estimate.city} was '
          'shaped most by these environmental signals:',
      drivers: drivers,
      strength: attributions.confidenceRationale.strength,
      confidenceSentence: _confidenceSentence(attributions.confidenceRationale),
      provenanceNote:
          'These drivers come directly from the model, not written by hand.',
    );
  }

  // ── Driver → sentence ──────────────────────────────────────────────────────

  static ExplanationDriver _driverLine(FeatureContribution c) {
    final label = featureLabel(c.feature);
    final verb = c.direction == ContributionDirection.increases
        ? 'pushed this estimate higher'
        : 'pulled this estimate lower';
    final valueText = _formatValue(c.feature, c.value);
    final sentence = valueText.isEmpty
        ? '$label $verb.'
        : '$label, measured $valueText, $verb.';
    return ExplanationDriver(
      label: label,
      direction: c.direction,
      valueText: valueText,
      sentence: sentence,
    );
  }

  // ── Confidence → sentence (fixed templates per stored strength) ─────────────

  static String _confidenceSentence(ConfidenceRationale r) {
    final agreePct = (r.agreement * 100).round();
    switch (r.strength) {
      case ConfidenceStrength.strong:
        return 'Confidence is strong — the model clearly favoured '
            '${r.predictedClass} over ${r.runnerUpClass}, and $agreePct% of its '
            'decision trees agreed.';
      case ConfidenceStrength.moderate:
        return 'Confidence is moderate — the model leaned toward '
            '${r.predictedClass} over ${r.runnerUpClass}, with $agreePct% of its '
            'decision trees in agreement.';
      case ConfidenceStrength.weak:
        return 'Confidence is limited — ${r.predictedClass} only narrowly edged '
            'out ${r.runnerUpClass} ($agreePct% of decision trees agreed), so '
            'read this estimate with extra caution.';
    }
  }

  // ── Feature key → human label ──────────────────────────────────────────────

  /// Base environmental quantities the engineered features derive from.
  static const Map<String, String> _baseLabels = {
    'temperature': 'Temperature',
    'humidity': 'Humidity',
    'precipitation': 'Rainfall',
    'us_aqi': 'Air quality (AQI)',
    'pm2_5': 'PM2.5 particles',
    'pm10': 'PM10 particles',
    'aqi_available': 'Air-quality data',
  };

  /// Display unit for a base quantity (documented metadata, not fabricated).
  /// Empty means unit-less.
  static const Map<String, String> _baseUnits = {
    'temperature': '°C',
    'humidity': '%',
    'precipitation': 'mm',
    'us_aqi': '',
    'pm2_5': ' µg/m³',
    'pm10': ' µg/m³',
  };

  /// Map an engineered feature key to a human-readable label, deterministically.
  ///
  /// Handles the documented feature families: raw same-week values, `_lagN`
  /// (earlier weeks), `_rollN` (moving averages), `_anomaly` (vs seasonal
  /// normal), the cyclical week encoding, and city one-hots.
  static String featureLabel(String key) {
    if (key.startsWith('city_')) return 'City (${key.substring(5)})';
    if (key == 'week_sin' || key == 'week_cos') return 'Time of year';

    final parsed = _parse(key);
    final base = _baseLabels[parsed.base] ?? _titleize(parsed.base);
    return parsed.qualifier == null ? base : '$base (${parsed.qualifier})';
  }

  static String _formatValue(String key, double value) {
    if (key.startsWith('city_') ||
        key == 'week_sin' ||
        key == 'week_cos' ||
        key == 'aqi_available') {
      return '';
    }
    final parsed = _parse(key);
    // A seasonal-anomaly (deviation) value has no absolute unit — show it bare.
    final unit = parsed.isDeviation ? '' : (_baseUnits[parsed.base] ?? '');
    return '${_formatNumber(value)}$unit';
  }

  static _ParsedFeature _parse(String key) {
    if (key.endsWith('_anomaly')) {
      return _ParsedFeature(
        base: key.substring(0, key.length - '_anomaly'.length),
        qualifier: 'vs seasonal normal',
        isDeviation: true,
      );
    }
    final match = RegExp(r'^(.+)_(lag|roll)(\d+)$').firstMatch(key);
    if (match != null) {
      final base = match.group(1)!;
      final kind = match.group(2)!;
      final n = int.parse(match.group(3)!);
      final qualifier = kind == 'lag'
          ? (n == 1 ? 'previous week' : '$n weeks earlier')
          : '$n-week average';
      return _ParsedFeature(base: base, qualifier: qualifier);
    }
    return _ParsedFeature(base: key);
  }

  static String _formatNumber(double v) {
    // Whole numbers show without a trailing ".0"; others to one decimal.
    return v == v.roundToDouble()
        ? v.toStringAsFixed(0)
        : v.toStringAsFixed(1);
  }

  static String _titleize(String snake) {
    return snake
        .split('_')
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}

class _ParsedFeature {
  final String base;
  final String? qualifier;
  final bool isDeviation;

  const _ParsedFeature({
    required this.base,
    this.qualifier,
    this.isDeviation = false,
  });
}
