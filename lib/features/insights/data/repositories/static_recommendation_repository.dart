import '../../domain/models/health_recommendation.dart';
import '../../domain/repositories/recommendation_repository.dart';

/// The verified recommendation content library (Sprint 4, Prompt 6).
///
/// A fixed, cited table keyed by `(category, driver)` — the single source of
/// truth `docs/recommendation_rules.md`. Mirrors the backend
/// `recommendation_lookup.py` **field-for-field** (id, text, source, sourceUrl,
/// deepLink, escalation) so the dashboard card and the alert inbox surface
/// identical advice. Nothing here is generated (Rule 11); the lookup is total
/// (unknown keys → the cited [_default]).
class StaticRecommendationRepository implements RecommendationRepository {
  const StaticRecommendationRepository();

  static const HealthRecommendation _respAir = HealthRecommendation(
    id: 'rec-resp-air',
    category: 'respiratory',
    driver: 'Air quality',
    text:
        'Limit prolonged or heavy outdoor exertion; keep windows closed during '
        'peak smog; a well-fitted N95/FFP2 mask reduces fine-particle exposure; '
        'run a HEPA purifier indoors.',
    source: 'WHO — Air pollution',
    sourceUrl: 'https://www.who.int/health-topics/air-pollution',
    deepLink: '/resources',
    escalation:
        'If breathing worsens (frequent wheeze/breathlessness), seek medical '
        'care; emergency → Rescue 1122.',
  );

  static const HealthRecommendation _respSeasonal = HealthRecommendation(
    id: 'rec-resp-seasonal',
    category: 'respiratory',
    driver: 'Respiratory',
    text:
        'Keep your reliever inhaler with you and follow your asthma action '
        'plan; avoid crowded indoor spaces during peak respiratory season.',
    source: 'CDC — Asthma',
    sourceUrl: 'https://www.cdc.gov/asthma/',
    deepLink: '/resources',
    escalation:
        'Seek care promptly if symptoms escalate; emergency → Rescue 1122.',
  );

  static const HealthRecommendation _cardioAir = HealthRecommendation(
    id: 'rec-cardio-air',
    category: 'cardiovascular',
    driver: 'Air quality',
    text:
        'On high-AQI days, reduce strenuous outdoor activity; sensitive groups '
        '(heart/lung conditions) should limit prolonged exertion and keep '
        'medications on hand.',
    source: 'US EPA — AirNow AQI',
    sourceUrl: 'https://www.airnow.gov/aqi/aqi-basics/',
    deepLink: '/resources',
    escalation:
        'Chest discomfort/shortness of breath → seek urgent care; emergency → '
        'Rescue 1122.',
  );

  static const HealthRecommendation _cardioHeat = HealthRecommendation(
    id: 'rec-cardio-heat',
    category: 'cardiovascular',
    driver: 'Heat',
    text:
        'Drink water regularly, avoid the hottest hours, and keep cool. Heart '
        'disease, hypertension or diabetes reduce heat tolerance — watch for '
        'dizziness, headache or nausea.',
    source: 'WHO — Heatwaves',
    sourceUrl: 'https://www.who.int/health-topics/heatwaves',
    deepLink: '/nearby-hospitals',
    escalation:
        'Heat exhaustion not improving, or chest pain/confusion → seek help '
        'immediately; emergency → Rescue 1122.',
  );

  /// Total-lookup fallback — always sourced, never empty, non-diagnostic.
  static const HealthRecommendation _default = HealthRecommendation(
    id: 'rec-default',
    category: '*',
    driver: '*',
    text:
        'Check your local Air Quality Index and follow official guidance for '
        'your area. This is general information, not personal medical advice.',
    source: 'US EPA — AirNow AQI',
    sourceUrl: 'https://www.airnow.gov/aqi/aqi-basics/',
    deepLink: '/resources',
    escalation:
        'For personal guidance consult a healthcare professional; emergency → '
        'Rescue 1122.',
  );

  static const Map<String, HealthRecommendation> _table = {
    'respiratory|Air quality': _respAir,
    'respiratory|Respiratory': _respSeasonal,
    'cardiovascular|Air quality': _cardioAir,
    'cardiovascular|Heat': _cardioHeat,
  };

  /// The safe cited default (exposed so callers/tests can reference it directly).
  static const HealthRecommendation defaultRecommendation = _default;

  /// All entries including the default — used by integrity tests.
  static const List<HealthRecommendation> all = [
    _respAir,
    _respSeasonal,
    _cardioAir,
    _cardioHeat,
    _default,
  ];

  @override
  HealthRecommendation lookup(String category, String driver) {
    return _table['$category|$driver'] ?? _default;
  }
}
