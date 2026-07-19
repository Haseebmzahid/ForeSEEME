/// Explainable Health Intelligence — pure view models (Sprint M-EHI).
///
/// The presentation-ready shape the Explainable Health Intelligence screen
/// renders. Framework-free (no `package:flutter`), mirroring
/// `adherence_journey_model.dart` and `weekly_report.dart`: only immutable data
/// classes live here; ALL composition lives in
/// `domain/services/health_intelligence_service.dart`.
///
/// Nothing in this layer is generated or recomputed. Every field is a
/// deterministic mapping over signals ForeSeeMe already computes — the model's
/// own risk attributions, the deterministic risk trend, the user's supportive
/// adherence insights, and the EPA AQI band. It is descriptive and
/// **non-diagnostic**: it explains the environmental *estimate* and the user's
/// own logged routine, never the person's body or a clinical state. Advisory
/// (recommendation) text is NOT built here — that stays behind the existing
/// cited, guarded providers (GOLDEN_RULES Rule 11).
library;

import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';

// ── Section 1 — Health Summary ("How am I?") ────────────────────────────────

/// A concise, human-readable summary of today's environmental risk standing.
class HealthSummary {
  /// The current risk level, or `null` when no estimate is available.
  final RiskLevel? level;

  /// Display label, e.g. "Low Risk" or "Assessment pending".
  final String levelLabel;

  /// Model confidence as a whole percent (0–100), or `null` with no estimate.
  final int? confidencePercent;

  /// One-line, non-diagnostic assessment, e.g. "Conditions look stable today."
  final String assessment;

  /// True when a real estimate backs this summary.
  final bool hasEstimate;

  const HealthSummary({
    required this.level,
    required this.levelLabel,
    required this.confidencePercent,
    required this.assessment,
    required this.hasEstimate,
  });
}

// ── Section 2 — Why? (the signature section) ────────────────────────────────

/// Whether a reason currently helps ("✓") or wants attention ("!").
enum ReasonTone { positive, attention }

/// A single plain-language contributor to *why* the risk is what it is.
///
/// Descriptive only — each line restates an existing, stored signal (an
/// adherence trend, a model driver, the AQI band, the risk trend). Never a
/// medical claim about the person.
class WhyReason {
  final ReasonTone tone;
  final String text;

  const WhyReason({required this.tone, required this.text});
}

// ── Section 3 — Health Contributors ─────────────────────────────────────────

/// Qualitative state of a contributor. [comingSoon] is a first-class,
/// **honest** state for signals ForeSeeMe does not yet collect (symptoms, peak
/// flow) — shown as a roadmap item rather than a fabricated reading.
enum ContributorStatus { excellent, good, moderate, attention, unavailable, comingSoon }

extension ContributorStatusX on ContributorStatus {
  String get label => switch (this) {
    ContributorStatus.excellent => 'Excellent',
    ContributorStatus.good => 'Good',
    ContributorStatus.moderate => 'Moderate',
    ContributorStatus.attention => 'Needs attention',
    ContributorStatus.unavailable => 'No data yet',
    ContributorStatus.comingSoon => 'Coming soon',
  };
}

/// An expandable contributor card's data: a titled factor, its qualitative
/// [status], the "because" line explaining it, and an optional in-app
/// "Learn more" destination (an existing route — no new content).
class HealthContributor {
  /// Stable key: `medication` | `environment` | `symptoms` | `peak_flow`.
  final String key;
  final String title;
  final ContributorStatus status;

  /// Plain-language reason for the [status], drawn from existing data, e.g.
  /// "92% adherence this week." For a coming-soon factor this is the roadmap note.
  final String because;

  /// Optional deeper detail shown when the card is expanded (non-diagnostic).
  final String? detail;

  /// An existing in-app route for "Learn more", or `null` when there is none.
  final String? learnMoreRoute;
  final String? learnMoreLabel;

  const HealthContributor({
    required this.key,
    required this.title,
    required this.status,
    required this.because,
    this.detail,
    this.learnMoreRoute,
    this.learnMoreLabel,
  });

  bool get isComingSoon => status == ContributorStatus.comingSoon;
}

// ── Section 5 — Trend Explanation ("What changed?") ─────────────────────────

enum TrendChangeDirection { improved, worsened, steady }

/// One "what changed this week" line — only produced where a REAL delta exists
/// (adherence week-over-week, the 6-week risk trend). Never invented.
class TrendChange {
  final String label;
  final TrendChangeDirection direction;

  /// The change phrased in words, e.g. "improved 8%" or "held steady".
  final String detail;

  const TrendChange({
    required this.label,
    required this.direction,
    required this.detail,
  });
}

// ── Section 6 — Health Timeline ─────────────────────────────────────────────

enum TimelineMarker { done, pending, missed, info, upcoming }

/// One compact chapter of today's journey (Morning / Afternoon / Evening /
/// Tomorrow), sourced from today's dose states + the environmental estimate.
class TimelineEntry {
  final String period;
  final TimelineMarker marker;
  final String text;

  const TimelineEntry({
    required this.period,
    required this.marker,
    required this.text,
  });
}

// ── Section 7 — Environmental Context ───────────────────────────────────────

/// Today's environmental snapshot + the single biggest factor behind the
/// estimate (the top model driver). All values are the estimate's own stored
/// features; the primary-trigger note describes the *estimate*, non-diagnostically.
class EnvironmentalContext {
  final bool hasData;
  final int? aqi;
  final String? aqiBandLabel;
  final int? temperatureC;
  final int? humidityPercent;

  /// Human label of the top environmental driver, e.g. "Air quality (AQI)".
  final String? primaryTriggerLabel;

  /// A fixed, non-diagnostic note about that trigger's role in the estimate.
  final String? primaryTriggerNote;

  const EnvironmentalContext({
    required this.hasData,
    this.aqi,
    this.aqiBandLabel,
    this.temperatureC,
    this.humidityPercent,
    this.primaryTriggerLabel,
    this.primaryTriggerNote,
  });
}

// ── The composed view (screen root model) ───────────────────────────────────

/// The full Explainable Health Intelligence view — a deterministic composition
/// of existing signals. The screen binds to this; the recommendation section is
/// rendered separately by the existing cited, guarded cards.
class HealthIntelligenceView {
  final String? city;
  final HealthSummary summary;
  final String whyTitle;
  final List<WhyReason> whyReasons;
  final List<HealthContributor> contributors;
  final List<TrendChange> trendChanges;
  final List<TimelineEntry> timeline;
  final EnvironmentalContext environment;

  /// The current estimate, or `null` — lets the screen decide whether to show
  /// the high-risk emergency affordance (reusing the existing EmergencyCard).
  final RiskEstimateModel? estimate;

  const HealthIntelligenceView({
    required this.city,
    required this.summary,
    required this.whyTitle,
    required this.whyReasons,
    required this.contributors,
    required this.trendChanges,
    required this.timeline,
    required this.environment,
    required this.estimate,
  });

  /// True when the current estimate classifies as high risk — the screen then
  /// surfaces the emergency affordance (Content Safety Policy).
  bool get isHighRisk => estimate?.riskLevel == RiskLevel.high;
}
