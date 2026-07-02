import 'package:fyp_foreseeme/features/insights/domain/models/adherence_insights.dart';
import 'package:fyp_foreseeme/features/insights/domain/models/health_recommendation.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';

/// A titled block of the weekly report (deterministic, descriptive copy).
class WeeklyReportSection {
  final String title;
  final String body;

  const WeeklyReportSection({required this.title, required this.body});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WeeklyReportSection &&
          other.title == title &&
          other.body == body;

  @override
  int get hashCode => Object.hash(title, body);
}

/// The composed Weekly Health Report (Sprint 5, Prompt 8).
///
/// A proactive digest that ties together **existing** signals — the week's
/// environmental risk, the user's adherence, and a cited recommendation — into
/// one descriptive, non-diagnostic touchpoint. Framework-free (pure Dart): the
/// pieces come from existing providers and the copy is composed deterministically
/// by [composeWeeklyReport] (no generated text; the advisory is a cited lookup).
class WeeklyReport {
  /// The Monday (UTC) of the ISO week this report covers.
  final DateTime weekOf;

  /// The user's city, or `null` when unknown.
  final String? city;

  /// The week's environmental risk estimate, or `null` when none is available.
  final RiskEstimateModel? risk;

  /// The user's supportive adherence insights (never a grade).
  final AdherenceInsights adherence;

  /// The cited recommendation, or `null` if none could be surfaced.
  final HealthRecommendation? recommendation;

  final WeeklyReportSection riskSection;
  final WeeklyReportSection adherenceSection;

  /// The cited-guidance section, or `null` when no recommendation is available.
  final WeeklyReportSection? recommendationSection;

  const WeeklyReport({
    required this.weekOf,
    required this.city,
    required this.risk,
    required this.adherence,
    required this.recommendation,
    required this.riskSection,
    required this.adherenceSection,
    required this.recommendationSection,
  });

  /// A week has real risk data when an estimate exists.
  bool get hasRisk => risk != null;

  /// Nothing to summarise yet — no estimate and no logged adherence.
  bool get isEmpty => risk == null && !adherence.hasData;
}
