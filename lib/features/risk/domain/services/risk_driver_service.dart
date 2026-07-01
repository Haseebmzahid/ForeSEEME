import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';

/// The kind of environmental signal driving an estimate — presentation maps this
/// to an icon (kept out of the framework-free domain).
enum RiskDriverKind { airQuality, heat, humidity }

/// The dominant risk driver for an estimate: a kind + display label + value.
///
/// Pure value object (no Flutter) so it is reusable and unit-testable. Example:
/// air-quality driver → `RiskDriver(airQuality, 'PM2.5', '184')`.
class RiskDriver {
  final RiskDriverKind kind;
  final String label;
  final String value;

  const RiskDriver(this.kind, this.label, this.value);
}

/// Returns whichever environmental signal is most elevated on a coarse reference
/// scale — a presentational heuristic over the estimate's own feature values (not
/// an additional clinical claim, and it never alters the frozen contract).
///
/// This is the single, shared home for the "primary driver" derivation used by
/// the dashboard risk card and the Risk Details screen.
RiskDriver dominantDriver(RiskEstimateModel e) {
  final aqiN = (e.aqi / 300).clamp(0.0, 2.0);
  final tempN = ((e.temperature - 10) / 30).clamp(0.0, 2.0);
  final humN = (e.humidity / 100).clamp(0.0, 2.0);

  if (aqiN >= tempN && aqiN >= humN) {
    return RiskDriver(
      RiskDriverKind.airQuality,
      'PM2.5',
      e.aqi.round().toString(),
    );
  }
  if (tempN >= humN) {
    return RiskDriver(
      RiskDriverKind.heat,
      'Temperature',
      '${e.temperature.round()}°C',
    );
  }
  return RiskDriver(
    RiskDriverKind.humidity,
    'Humidity',
    '${e.humidity.round()}%',
  );
}
