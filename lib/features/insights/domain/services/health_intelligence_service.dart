// Explainable Health Intelligence — deterministic composition (Sprint M-EHI).
//
// Framework-free, pure, unit-testable — mirrors `weekly_report_use_case.dart`
// and `risk_trend_service.dart`. It takes signals ForeSeeMe ALREADY computes
// (the model's risk estimate + genuine attributions, the deterministic risk
// trend, the user's supportive adherence insights + weekly reflection, today's
// dose states, and the current mission) and maps them, via FIXED templates,
// into a presentation-ready `HealthIntelligenceView`.
//
// It never recomputes a model number, never invents a reading for a signal the
// app does not collect (symptoms, peak flow → an honest "coming soon"), and
// never composes advisory/medical text — recommendations stay behind the
// existing cited, guarded providers (GOLDEN_RULES Rule 11). Every sentence is
// non-diagnostic: it describes the environmental *estimate* and the user's own
// logged routine, not the person's body.

import 'package:fyp_foreseeme/features/insights/domain/models/adherence_insights.dart';
import 'package:fyp_foreseeme/features/insights/domain/models/health_intelligence.dart';
import 'package:fyp_foreseeme/features/insights/domain/services/environmental_insights.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_journey_model.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_attributions.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/trend_direction.dart';
import 'package:fyp_foreseeme/features/risk/domain/services/aqi_band.dart';

/// Composes the Explainable Health Intelligence view from existing signals.
///
/// Stateless; the single public entry is [compose]. All inputs are already
/// resolved by their existing providers — this service performs no I/O.
class HealthIntelligenceService {
  const HealthIntelligenceService();

  /// How many environmental drivers feed the "Why?" reasons (top-N, ranked by
  /// the backend — never re-ranked here).
  static const int _maxWhyDrivers = 2;

  HealthIntelligenceView compose({
    required String? city,
    required RiskEstimateModel? estimate,
    required TrendDirection trend,
    required AdherenceInsights adherence,
    required WeeklyReflection? reflection,
    required TodaysMission mission,
    required DayJourneyCard? today,
    required List<EnvironmentalDriver> drivers,
  }) {
    return HealthIntelligenceView(
      city: city,
      estimate: estimate,
      summary: _summary(city, estimate, trend),
      whyTitle: _whyTitle(estimate),
      whyReasons: _whyReasons(estimate, trend, adherence, reflection, drivers),
      contributors: _contributors(estimate, adherence, reflection),
      trendChanges: _trendChanges(estimate, trend, reflection, adherence),
      timeline: _timeline(estimate, today, mission),
      environment: _environment(estimate, drivers),
    );
  }

  // ── Section 1: Summary ─────────────────────────────────────────────────────

  HealthSummary _summary(
    String? city,
    RiskEstimateModel? estimate,
    TrendDirection trend,
  ) {
    if (estimate == null) {
      return const HealthSummary(
        level: null,
        levelLabel: 'Assessment pending',
        confidencePercent: null,
        assessment:
            'No environmental risk estimate is available for your area yet.',
        hasEstimate: false,
      );
    }
    final where = (city == null || city.isEmpty) ? 'your area' : city;
    final assessment = switch (estimate.riskLevel) {
      RiskLevel.low => trend == TrendDirection.rising
          ? 'Conditions are low but edging up in $where today.'
          : 'Conditions look stable in $where today.',
      RiskLevel.medium =>
        'Conditions are moderate in $where today — worth staying aware.',
      RiskLevel.high =>
        'Conditions are elevated in $where today. Take extra care.',
    };
    return HealthSummary(
      level: estimate.riskLevel,
      levelLabel: '${estimate.riskLevel.toJson()} Risk',
      confidencePercent: (estimate.confidence.clamp(0.0, 1.0) * 100).round(),
      assessment: assessment,
      hasEstimate: true,
    );
  }

  // ── Section 2: Why? ────────────────────────────────────────────────────────

  String _whyTitle(RiskEstimateModel? estimate) {
    if (estimate == null) return 'What shapes your risk?';
    return 'Why is your risk ${estimate.riskLevel.toJson().toLowerCase()}?';
  }

  List<WhyReason> _whyReasons(
    RiskEstimateModel? estimate,
    TrendDirection trend,
    AdherenceInsights adherence,
    WeeklyReflection? reflection,
    List<EnvironmentalDriver> drivers,
  ) {
    final reasons = <WhyReason>[];

    // 1) Medication routine — the user's own logged behaviour (never a grade).
    final medReason = _medicationReason(adherence, reflection);
    if (medReason != null) reasons.add(medReason);

    // 2) Environmental drivers — genuine, ranked model attributions.
    final aqiCovered = drivers.any(_isAqiFeature);
    for (final d in drivers.take(_maxWhyDrivers)) {
      final easing = d.direction == ContributionDirection.decreases;
      reasons.add(WhyReason(
        tone: easing ? ReasonTone.positive : ReasonTone.attention,
        text: easing
            ? '${d.label} is easing today’s estimate'
            : '${d.label} is pushing today’s estimate up',
      ));
    }

    // 3) Air quality band — only if AQI wasn't already a listed driver (avoids
    // saying the same thing twice).
    if (estimate != null && !aqiCovered) {
      final band = aqiBandFor(estimate.aqi);
      final calm = band == AqiBand.good || band == AqiBand.moderate;
      reasons.add(WhyReason(
        tone: calm ? ReasonTone.positive : ReasonTone.attention,
        text: 'Air quality is ${band.label.toLowerCase()} today',
      ));
    }

    // 4) Recent risk trend for the area (deterministic 6-week direction).
    switch (trend) {
      case TrendDirection.falling:
        reasons.add(const WhyReason(
          tone: ReasonTone.positive,
          text: 'Your area’s recent risk trend is easing',
        ));
      case TrendDirection.stable:
        reasons.add(const WhyReason(
          tone: ReasonTone.positive,
          text: 'Your area’s recent risk trend is stable',
        ));
      case TrendDirection.rising:
        reasons.add(const WhyReason(
          tone: ReasonTone.attention,
          text: 'Your area’s recent risk trend is climbing',
        ));
      case TrendDirection.insufficient:
        break; // Not enough history — say nothing rather than guess.
    }

    return List.unmodifiable(reasons);
  }

  WhyReason? _medicationReason(
    AdherenceInsights adherence,
    WeeklyReflection? reflection,
  ) {
    if (!adherence.hasData) return null;
    final delta = reflection?.comparedToLastWeek ?? 0;
    if (delta > 0) {
      return const WhyReason(
        tone: ReasonTone.positive,
        text: 'Your medication adherence is improving',
      );
    }
    if (delta < 0) {
      return const WhyReason(
        tone: ReasonTone.attention,
        text: 'Your medication adherence dipped this week',
      );
    }
    if (adherence.isPerfect) {
      return const WhyReason(
        tone: ReasonTone.positive,
        text: 'You’ve taken every logged dose',
      );
    }
    return const WhyReason(
      tone: ReasonTone.positive,
      text: 'Your medication routine is steady',
    );
  }

  // ── Section 3: Contributors ────────────────────────────────────────────────

  List<HealthContributor> _contributors(
    RiskEstimateModel? estimate,
    AdherenceInsights adherence,
    WeeklyReflection? reflection,
  ) {
    return List.unmodifiable([
      _medicationContributor(adherence, reflection),
      _environmentContributor(estimate),
      // Honest roadmap items — ForeSeeMe does not yet collect these, so it never
      // fabricates a reading (GOLDEN_RULES: no fabricated calculations).
      const HealthContributor(
        key: 'symptoms',
        title: 'Symptoms',
        status: ContributorStatus.comingSoon,
        because:
            'Symptom check-ins aren’t part of ForeSeeMe yet — this factor '
            'will appear once symptom tracking arrives.',
      ),
      const HealthContributor(
        key: 'peak_flow',
        title: 'Peak Flow',
        status: ContributorStatus.comingSoon,
        because:
            'Peak-flow logging is coming in a future update, and will feed into '
            'your risk picture here.',
      ),
    ]);
  }

  HealthContributor _medicationContributor(
    AdherenceInsights adherence,
    WeeklyReflection? reflection,
  ) {
    if (!adherence.hasData) {
      return const HealthContributor(
        key: 'medication',
        title: 'Medication',
        status: ContributorStatus.unavailable,
        because: 'Log a few doses and your adherence picture will appear here.',
        learnMoreRoute: '/resources',
        learnMoreLabel: 'Medication tips',
      );
    }
    final percent = reflection?.adherencePercent;
    final status = percent == null
        ? ContributorStatus.good
        : _statusForPercent(percent);
    final because = percent != null
        ? '$percent% adherence this week.'
        : 'You’re on a ${adherence.currentStreakDays}-day streak.';
    final detail = adherence.strongestBucket != null
        ? 'You’re most consistent in ${adherence.strongestBucket!.phrase}.'
        : null;
    return HealthContributor(
      key: 'medication',
      title: 'Medication',
      status: status,
      because: because,
      detail: detail,
      learnMoreRoute: '/resources',
      learnMoreLabel: 'Medication tips',
    );
  }

  HealthContributor _environmentContributor(RiskEstimateModel? estimate) {
    if (estimate == null) {
      return const HealthContributor(
        key: 'environment',
        title: 'Environment',
        status: ContributorStatus.unavailable,
        because: 'No environmental data for your area yet.',
        learnMoreRoute: '/resources',
        learnMoreLabel: 'Air quality',
      );
    }
    final band = aqiBandFor(estimate.aqi);
    final status = switch (band) {
      AqiBand.good => ContributorStatus.excellent,
      AqiBand.moderate => ContributorStatus.moderate,
      AqiBand.unhealthyForSensitiveGroups ||
      AqiBand.unhealthy => ContributorStatus.attention,
      AqiBand.veryUnhealthy || AqiBand.hazardous => ContributorStatus.attention,
    };
    return HealthContributor(
      key: 'environment',
      title: 'Environment',
      status: status,
      because: 'AQI is ${estimate.aqi.round()} (${band.label}) today.',
      detail:
          '${estimate.temperature.round()}°C, '
          '${estimate.humidity.round()}% humidity in ${estimate.city}.',
      learnMoreRoute: '/resources',
      learnMoreLabel: 'Air quality',
    );
  }

  ContributorStatus _statusForPercent(int percent) {
    if (percent >= 90) return ContributorStatus.excellent;
    if (percent >= 70) return ContributorStatus.good;
    if (percent >= 40) return ContributorStatus.moderate;
    return ContributorStatus.attention;
  }

  // ── Section 5: Trend changes ("what changed this week") ────────────────────

  List<TrendChange> _trendChanges(
    RiskEstimateModel? estimate,
    TrendDirection trend,
    WeeklyReflection? reflection,
    AdherenceInsights adherence,
  ) {
    final changes = <TrendChange>[];

    // Adherence — a real week-over-week delta from the reflection.
    if (reflection != null && adherence.hasData) {
      final delta = reflection.comparedToLastWeek;
      if (delta > 0) {
        changes.add(TrendChange(
          label: 'Medication adherence',
          direction: TrendChangeDirection.improved,
          detail: 'improved $delta%',
        ));
      } else if (delta < 0) {
        changes.add(TrendChange(
          label: 'Medication adherence',
          direction: TrendChangeDirection.worsened,
          detail: 'eased ${delta.abs()}%',
        ));
      } else {
        changes.add(const TrendChange(
          label: 'Medication adherence',
          direction: TrendChangeDirection.steady,
          detail: 'held steady',
        ));
      }
    }

    // Risk — the deterministic 6-week direction (only when judgeable).
    final disease = estimate?.disease;
    final riskLabel = (disease == null || disease.isEmpty)
        ? 'Environmental risk'
        : '$disease risk';
    switch (trend) {
      case TrendDirection.falling:
        changes.add(TrendChange(
          label: riskLabel,
          direction: TrendChangeDirection.improved,
          detail: 'decreased',
        ));
      case TrendDirection.rising:
        changes.add(TrendChange(
          label: riskLabel,
          direction: TrendChangeDirection.worsened,
          detail: 'increased',
        ));
      case TrendDirection.stable:
        changes.add(TrendChange(
          label: riskLabel,
          direction: TrendChangeDirection.steady,
          detail: 'held steady',
        ));
      case TrendDirection.insufficient:
        break;
    }

    // A supportive fact — the week's longest streak (never a grade).
    if (reflection != null && reflection.longestStreak > 0) {
      changes.add(TrendChange(
        label: 'Longest streak',
        direction: TrendChangeDirection.improved,
        detail:
            '${reflection.longestStreak} '
            '${reflection.longestStreak == 1 ? 'day' : 'days'}',
      ));
    }

    return List.unmodifiable(changes);
  }

  // ── Section 6: Timeline ────────────────────────────────────────────────────

  List<TimelineEntry> _timeline(
    RiskEstimateModel? estimate,
    DayJourneyCard? today,
    TodaysMission mission,
  ) {
    final entries = <TimelineEntry>[];

    // Morning / Evening dose states — reused from today's journey card (no new
    // computation; the same states the Adherence Journey timeline shows).
    if (today != null) {
      entries.add(_doseEntry('Morning', today.morning));
    }

    // Midday environmental marker — the day's air-quality reading.
    if (estimate != null) {
      final band = aqiBandFor(estimate.aqi);
      entries.add(TimelineEntry(
        period: 'Afternoon',
        marker: TimelineMarker.info,
        text: 'Air quality ${band.label.toLowerCase()} (AQI ${estimate.aqi.round()})',
      ));
    }

    if (today != null) {
      entries.add(_doseEntry('Evening', today.evening));
    }

    // Tomorrow — a forward-looking line from the current mission state.
    entries.add(TimelineEntry(
      period: 'Tomorrow',
      marker: TimelineMarker.upcoming,
      text: switch (mission.state) {
        MissionState.pending => 'Finish today’s remaining dose',
        MissionState.allComplete => 'Maintain your routine tomorrow',
        MissionState.dayOver => 'A fresh start — keep your streak going',
        MissionState.noMedications => 'Add a medication to start tracking',
      },
    ));

    return List.unmodifiable(entries);
  }

  TimelineEntry _doseEntry(String period, DoseCompletionState state) {
    return switch (state) {
      DoseCompletionState.taken => TimelineEntry(
        period: period,
        marker: TimelineMarker.done,
        text: '$period medication completed',
      ),
      DoseCompletionState.pending => TimelineEntry(
        period: period,
        marker: TimelineMarker.pending,
        text: '$period medication pending',
      ),
      DoseCompletionState.missed => TimelineEntry(
        period: period,
        marker: TimelineMarker.missed,
        text: '$period dose missed',
      ),
      DoseCompletionState.none => TimelineEntry(
        period: period,
        marker: TimelineMarker.info,
        text: 'No $period dose scheduled',
      ),
    };
  }

  // ── Section 7: Environmental context ───────────────────────────────────────

  EnvironmentalContext _environment(
    RiskEstimateModel? estimate,
    List<EnvironmentalDriver> drivers,
  ) {
    if (estimate == null) {
      return const EnvironmentalContext(hasData: false);
    }
    final top = drivers.isNotEmpty ? drivers.first : null;
    return EnvironmentalContext(
      hasData: true,
      aqi: estimate.aqi.round(),
      aqiBandLabel: aqiBandFor(estimate.aqi).label,
      temperatureC: estimate.temperature.round(),
      humidityPercent: estimate.humidity.round(),
      primaryTriggerLabel: top?.label,
      primaryTriggerNote: top == null
          ? null
          : '${top.label} is the biggest factor in today’s estimate for '
                '${estimate.city}.',
    );
  }

  static bool _isAqiFeature(EnvironmentalDriver d) =>
      d.feature.startsWith('us_aqi') ||
      d.feature.startsWith('pm2_5') ||
      d.feature.startsWith('pm10');
}
