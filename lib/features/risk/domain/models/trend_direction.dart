/// Direction of a city's risk over its trailing history.
///
/// Pure-Dart (no Flutter imports), mirroring [RiskLevel]. [insufficient] is a
/// first-class value — when there is too little history to judge a direction we
/// say so explicitly rather than inventing a (wrong) arrow.
enum TrendDirection { rising, stable, falling, insufficient }
