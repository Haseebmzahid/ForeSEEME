/// A single **cited, deterministic** advisory (Sprint 4, Prompt 6).
///
/// Immutable content value object — the app never composes medical text
/// (Rule 11). Every instance is a fixed entry from the verified content library
/// (`docs/recommendation_rules.md`), mirroring the backend
/// `recommendation_lookup.Recommendation` field-for-field so the dashboard card
/// and the alert inbox show identical advice. Framework-free (no Flutter, no
/// Firebase) — this is a lookup result, not a persisted document, so it carries
/// no `fromJson`/`toJson` (cf. `RiskAppearance`).
class HealthRecommendation {
  /// Stable id, e.g. `rec-resp-air` (also the alert payload's recommendation id).
  final String id;

  /// Risk-driver category this advisory serves (`respiratory` | `cardiovascular`
  /// | `*` for the default).
  final String category;

  /// Human risk-driver label, e.g. `Air quality` | `Heat` (`*` for the default).
  final String driver;

  /// The advisory itself — verbatim from the cited authority, never generated.
  final String text;

  /// Attribution label, e.g. `WHO — Air pollution`. Always non-empty.
  final String source;

  /// `https://` link to the cited authority. Always present.
  final String sourceUrl;

  /// In-app route to the relevant verified resource / help, e.g. `/resources`.
  final String deepLink;

  /// When-to-seek-help line — always routes to professional/emergency care.
  final String escalation;

  const HealthRecommendation({
    required this.id,
    required this.category,
    required this.driver,
    required this.text,
    required this.source,
    required this.sourceUrl,
    required this.deepLink,
    required this.escalation,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is HealthRecommendation && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'HealthRecommendation($id, $category/$driver)';
}
