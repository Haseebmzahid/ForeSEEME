import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/trend_direction.dart';

/// How many trailing estimates the trend looks back over (the "6-week trend"
/// in the Risk Details design). Fewer available points still compute a trend;
/// this only bounds the window.
const int kTrendWindowWeeks = 6;

/// Minimum points needed to judge a direction at all. With a single estimate
/// there is nothing to compare against, so the trend is [TrendDirection.insufficient].
const int kMinPointsForTrend = 2;

/// Dead-band (in risk-level steps) around "no change". The latest level must
/// differ from the mean of the earlier levels by more than half a level before
/// we call it rising/falling — otherwise it is [TrendDirection.stable]. This
/// keeps single-step noise from flipping the badge.
const double kTrendDeadband = 0.5;

/// Ordinal score of a risk level (Low < Medium < High).
int _scoreOf(RiskLevel level) => switch (level) {
  RiskLevel.low => 0,
  RiskLevel.medium => 1,
  RiskLevel.high => 2,
};

/// Deterministic Rising / Stable / Falling / Insufficient from [history].
///
/// Order-independent: the estimates are sorted by [RiskEstimateModel.generatedAt]
/// ascending first. The direction compares the **latest** level against the
/// **mean of the earlier** levels in the window, with a [kTrendDeadband]. Uses
/// the classified [RiskLevel] regardless of confidence, so the result is a pure
/// function of the level sequence.
TrendDirection computeTrend(List<RiskEstimateModel> history) {
  if (history.length < kMinPointsForTrend) return TrendDirection.insufficient;

  final ordered = [...history]
    ..sort((a, b) => a.generatedAt.compareTo(b.generatedAt));
  final scores = ordered.map((e) => _scoreOf(e.riskLevel)).toList();

  final latest = scores.last.toDouble();
  final prior = scores.sublist(0, scores.length - 1);
  final priorMean = prior.reduce((a, b) => a + b) / prior.length;
  final delta = latest - priorMean;

  if (delta > kTrendDeadband) return TrendDirection.rising;
  if (delta < -kTrendDeadband) return TrendDirection.falling;
  return TrendDirection.stable;
}
