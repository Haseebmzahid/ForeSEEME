// Pure-Dart staleness policy for risk estimates.
//
// Framework-free: imports NO `package:flutter`. Mirrors the other risk domain
// services (`risk_trend_service`, `risk_comparison_service`) — deterministic pure
// functions over the model with an injectable clock for tests.
//
// This centralises the single staleness threshold + classification that every
// risk surface (dashboard `RiskCard`, Risk Details, national map) shares, so no
// screen can silently present an out-of-date estimate as current
// (SPRINT_5 Prompt 11; audit H2 "stale-data handling"). The threshold previously
// lived privately inside `risk_card.dart`; it now has one home.

import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';

/// How old a risk estimate may be before it is flagged "possibly out of date".
///
/// Estimates are produced by the weekly scheduled batch (ADR-002): a fresh one
/// lands roughly every 7 days. The threshold is **7 days + 2 days grace = 9
/// days**, so an estimate crosses it only once at least one expected weekly run
/// has been missed — never merely because a fresh run is running a little late.
const Duration kRiskStaleAfter = Duration(days: 9);

/// Freshness of a stored estimate relative to [kRiskStaleAfter].
enum RiskFreshness { fresh, stale }

/// Classifies [generatedAt] against [kRiskStaleAfter].
///
/// [now] is injectable so tests are deterministic; it defaults to the current
/// time. Both instants are compared in UTC, matching the model's UTC-normalised
/// [RiskEstimateModel.generatedAt]. The boundary is exclusive: an estimate
/// exactly [kRiskStaleAfter] old is still [RiskFreshness.fresh].
RiskFreshness riskFreshness(DateTime generatedAt, {DateTime? now}) {
  final reference = (now ?? DateTime.now()).toUtc();
  final age = reference.difference(generatedAt.toUtc());
  return age > kRiskStaleAfter ? RiskFreshness.stale : RiskFreshness.fresh;
}

/// Convenience over [riskFreshness] taking the model directly.
RiskFreshness estimateFreshness(RiskEstimateModel estimate, {DateTime? now}) =>
    riskFreshness(estimate.generatedAt, now: now);

/// Whether [generatedAt] is older than the staleness threshold — the common
/// boolean check the surfaces gate their staleness notice on.
bool isRiskStale(DateTime generatedAt, {DateTime? now}) =>
    riskFreshness(generatedAt, now: now) == RiskFreshness.stale;

/// Human-friendly age of an estimate ("just now" / "20 min ago" / "3h ago" /
/// "2 days ago"). Presentation-neutral text; the widgets style it.
///
/// Clock skew (a [generatedAt] slightly in the future) degrades to "just now"
/// rather than ever rendering a negative/future age.
String riskAgeLabel(DateTime generatedAt, {DateTime? now}) {
  final reference = (now ?? DateTime.now()).toUtc();
  final diff = reference.difference(generatedAt.toUtc());
  if (diff.isNegative) return 'just now';
  if (diff.inMinutes < 60) {
    return diff.inMinutes <= 1 ? 'just now' : '${diff.inMinutes} min ago';
  }
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return diff.inDays == 1 ? '1 day ago' : '${diff.inDays} days ago';
}
